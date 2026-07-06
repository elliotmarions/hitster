-- =====================================================================
--  HITSTER BINGO ONLINE – Svarsfas (skriv & lås in gissning)
--
--  Efter att låten spelat klart (timern slut) får varje lag skriva sitt
--  svar och LÅSA IN det. När ALLA lag i rummet låst in avslöjas svaren –
--  och facit – för alla samtidigt.
--
--  Server-auktoritativt via SECURITY DEFINER-RPC + RLS:
--   - lock_answer: sparar + låser ditt svar (går bara efter att klippet
--     spelat klart). Räknar om hur många som låst och sätter
--     answers_revealed = true när alla lag är klara.
--   - reveal_answers: värdens säkerhetsventil (visa svaren även om någon
--     aldrig svarar).
--   - RLS: du ser BARA ditt eget svar tills answers_revealed = true.
--
--  Additiv migration (rör ingen befintlig logik). Idempotent. Kör efter 0005.
--  OBS manuell körning: kör även `notify pgrst, 'reload schema';` sist så
--  PostgREST ser de nya funktionerna.
-- =====================================================================

-- --- Utökning av rounds ---------------------------------------------
alter table public.rounds
  add column if not exists answers_revealed boolean not null default false;
alter table public.rounds
  add column if not exists locked_count int not null default 0;

-- --- Tabell: ett svar per lag och runda ------------------------------
create table if not exists public.round_answers (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  round_id    uuid not null references public.rounds (id) on delete cascade,
  player_id   uuid not null references public.players (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  answer      text not null default '',
  locked      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (round_id, player_id)
);
create index if not exists round_answers_round_idx on public.round_answers (round_id);
create index if not exists round_answers_room_idx on public.round_answers (room_id);

-- --- RPC: lås in mitt svar för senaste rundan -----------------------
-- Tillåts bara EFTER att klippet spelat klart (timer_start_at + ~timer).
-- Går inte att ändra efter att man låst.
create or replace function public.lock_answer(p_room_id uuid, p_answer text)
returns public.round_answers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_player public.players;
  v_round  public.rounds;
  v_ans    public.round_answers;
  v_locked int;
  v_total  int;
begin
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;
  if v_round.current_track_id is null or v_round.timer_start_at is null then
    raise exception 'Ingen låt har spelats än';
  end if;
  -- 24 s marginal (timern är 25 s) så klient/server-klockor inte krockar.
  if now() < v_round.timer_start_at + interval '24 seconds' then
    raise exception 'Vänta tills låten spelat klart innan du låser in svaret';
  end if;

  insert into public.round_answers (room_id, round_id, player_id, user_id, answer, locked)
  values (p_room_id, v_round.id, v_player.id, v_uid, coalesce(p_answer, ''), true)
  on conflict (round_id, player_id) do update
    set answer = case when public.round_answers.locked then public.round_answers.answer
                      else excluded.answer end,
        locked = true,
        updated_at = now()
  returning * into v_ans;

  -- Räkna om: alla lag i rummet som låst → avslöja för alla.
  select count(*) into v_locked from public.round_answers
    where round_id = v_round.id and locked;
  select count(*) into v_total from public.players where room_id = p_room_id;

  update public.rounds
    set locked_count = v_locked,
        answers_revealed = (v_locked >= v_total)
    where id = v_round.id;

  return v_ans;
end;
$$;

-- --- RPC: värden avslöjar svaren direkt (säkerhetsventil) ------------
create or replace function public.reveal_answers(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan avslöja svaren'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  update public.rounds set answers_revealed = true where id = v_round.id;
end;
$$;

-- --- Row Level Security ----------------------------------------------
alter table public.round_answers enable row level security;

-- Du ser ditt EGET svar alltid; andras svar bara när rundan är avslöjad.
drop policy if exists answers_select on public.round_answers;
create policy answers_select on public.round_answers
  for select to authenticated using (
    public.is_room_member(room_id)
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.rounds r
        where r.id = round_id and r.answers_revealed
      )
    )
  );
-- (Alla skrivningar sker via RPC:erna ovan – inga insert/update-policys.)

-- --- Behörigheter ----------------------------------------------------
grant select on public.round_answers to authenticated;
grant execute on function public.lock_answer(uuid, text) to authenticated;
grant execute on function public.reveal_answers(uuid) to authenticated;

-- --- Realtid ---------------------------------------------------------
alter table public.round_answers replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'round_answers'
  ) then
    alter publication supabase_realtime add table public.round_answers;
  end if;
end $$;

-- Så PostgREST ser de nya RPC:erna direkt (schema-cache-krångel vid manuell körning).
notify pgrst, 'reload schema';
