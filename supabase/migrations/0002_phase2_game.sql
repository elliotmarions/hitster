-- =====================================================================
--  LÅTSNURRAN – Fas 2
--  Spelplan: discokula (rundor), bingobrickor och kryss – allt i realtid.
--
--  Kör i Supabase SQL Editor efter 0001. Idempotent (går att köra om).
--
--  All spellogik är SERVER-AUKTORITATIV via SECURITY DEFINER-RPC:er:
--   - spin_wheel: servern slumpar kategorin så ALLA klienter garanterat får
--     samma resultat (klienten animerar bara hjulet till den kategorin).
--   - mark_cross: servern validerar att rutan matchar rundans kategori och
--     räknar ut vinst (hel rad/kolumn) – klienten kan inte fuska.
-- =====================================================================

-- --- Utökning av rooms ----------------------------------------------
alter table public.rooms
  add column if not exists winner_player_id uuid
  references public.players (id) on delete set null;

-- --- Tabeller --------------------------------------------------------

-- En runda = ett snurr. Kategorin gäller tills nästa snurr.
create table if not exists public.rounds (
  id                  uuid primary key default gen_random_uuid(),
  room_id             uuid not null references public.rooms (id) on delete cascade,
  round_number        int not null default 1,
  category            text check (category in ('decade', 'artist', 'exact_year', 'before_after_2000')),
  spun_by             uuid,
  current_track_id    text,                 -- Fas 3+
  current_track_meta  jsonb,                -- Fas 3+ (dolt tills revealed)
  timer_start_at      timestamptz,          -- när 25s-timern startar (= när snurret landar). Synk via tidsstämpel.
  state               text not null default 'playing'
                        check (state in ('spinning', 'playing', 'revealed')),
  created_at          timestamptz not null default now()
);
create index if not exists rounds_room_idx on public.rounds (room_id, round_number desc);

-- Varje spelares bingobricka. grid = flat array med 16 rutor (4x4, radvis).
-- Varje ruta: { "category": <kategori>, "filled": <bool> }.
create table if not exists public.bingo_cards (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  player_id   uuid not null references public.players (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  grid        jsonb not null,
  has_won     boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (room_id, player_id)
);
create index if not exists bingo_cards_room_idx on public.bingo_cards (room_id);

-- Händelselogg (vinst, sudd m.m.) – används mer i senare faser.
create table if not exists public.room_events (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  type        text not null,
  payload     jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists room_events_room_idx on public.room_events (room_id, created_at desc);

-- --- Bricka-generator: slumpad giltig latinsk kvadrat ----------------
-- Varje RAD och varje KOLUMN innehåller alla 4 kategorier exakt en gång.
-- Konstruktion: value(i,j) = (rp[i] + cp[j]) mod 4, där rp/cp är slumpade
-- permutationer av 0..3, sedan etiketteras 0..3 med en slumpad kategoriordning.
create or replace function public.gen_bingo_grid()
returns jsonb
language plpgsql
as $$
declare
  cats text[];
  rp   int[];
  cp   int[];
  i int;
  j int;
  v int;
  grid jsonb := '[]'::jsonb;
begin
  select array_agg(c order by random()) into cats
    from unnest(array['decade', 'artist', 'exact_year', 'before_after_2000']) as c;
  select array_agg(x order by random()) into rp from generate_series(0, 3) as x;
  select array_agg(x order by random()) into cp from generate_series(0, 3) as x;

  for i in 0..3 loop
    for j in 0..3 loop
      v := (rp[i + 1] + cp[j + 1]) % 4;               -- 0..3
      grid := grid || jsonb_build_object('category', cats[v + 1], 'filled', false);
    end loop;
  end loop;
  return grid;
end;
$$;

-- --- RPC: snurra discokulan (bara värden) ---------------------------
create or replace function public.spin_wheel(p_room_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats constant text[] := array['decade', 'artist', 'exact_year', 'before_after_2000'];
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan snurra'; end if;

  v_cat := cats[floor(random() * 4)::int + 1];
  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  -- timer_start_at ~4,2 s fram i tiden = ungefär när snurr-animationen landar.
  insert into public.rounds (room_id, round_number, category, spun_by, state, timer_start_at)
  values (p_room_id, v_num, v_cat, v_uid, 'playing', now() + interval '4.2 seconds')
  returning * into v_round;

  update public.rooms set status = 'playing'
    where id = p_room_id and status <> 'finished';
  return v_round;
end;
$$;

-- --- RPC: starta spelet (bara värden) – delar ut brickor ------------
create or replace function public.start_game(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta spelet'; end if;

  insert into public.bingo_cards (room_id, player_id, user_id, grid)
  select p_room_id, p.id, p.user_id, public.gen_bingo_grid()
    from public.players p
    where p.room_id = p_room_id
  on conflict (room_id, player_id) do nothing;

  update public.rooms set status = 'playing', winner_player_id = null where id = p_room_id;
end;
$$;

-- --- RPC: säkerställ att den som kommer in har en bricka (sena joins) -
create or replace function public.ensure_card(p_room_id uuid)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_player public.players;
  v_card   public.bingo_cards;
begin
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is not null then return v_card; end if;

  insert into public.bingo_cards (room_id, player_id, user_id, grid)
  values (p_room_id, v_player.id, v_uid, public.gen_bingo_grid())
  on conflict (room_id, player_id) do update set grid = public.bingo_cards.grid
  returning * into v_card;
  return v_card;
end;
$$;

-- --- RPC: kryssa en ruta (validerar kategori + räknar vinst) --------
create or replace function public.mark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  r int;
  c int;
  line_full boolean;
begin
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is null then raise exception 'Du har ingen bricka'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  if p_cell < 0 or p_cell > 15 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then
    return v_card; -- redan ikryssad, gör inget
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);

  -- Vinst: någon hel rad ELLER hel kolumn ifylld (täcker då alla 4 kategorier).
  for r in 0..3 loop
    line_full := true;
    for c in 0..3 loop
      if not ((v_grid -> (r * 4 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;
  for c in 0..3 loop
    line_full := true;
    for r in 0..3 loop
      if not ((v_grid -> (r * 4 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  if v_won then
    update public.rooms set status = 'finished', winner_player_id = v_player.id
      where id = p_room_id;
    insert into public.room_events (room_id, type, payload)
    values (p_room_id, 'GAME_WIN',
            jsonb_build_object('player_id', v_player.id, 'display_name', v_player.display_name));
  end if;

  return v_card;
end;
$$;

-- --- RPC: sudda ett kryss på en MEDSPELARES bricka (valfri regel) ----
create or replace function public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell int)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_card   public.bingo_cards;
  v_grid   jsonb;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if not coalesce(v_room.erase_rule_enabled, false) then
    raise exception 'Suddregeln är avstängd';
  end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null or v_round.category <> 'exact_year' then
    raise exception 'Sudd tillåts bara på kategorin Exakt årtal';
  end if;

  select * into v_card from public.bingo_cards where id = p_target_card and room_id = p_room_id;
  if v_card.id is null then raise exception 'Brickan finns inte'; end if;
  if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;

  if p_cell < 0 or p_cell > 15 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then
    return v_card; -- redan tom
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$$;

-- --- RPC: återställ (spela igen / tillbaka till lobby) – bara värden -
create or replace function public.reset_game(p_room_id uuid, p_back_to_lobby boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan återställa'; end if;

  delete from public.rounds where room_id = p_room_id;
  delete from public.room_events where room_id = p_room_id;
  update public.bingo_cards set grid = public.gen_bingo_grid(), has_won = false
    where room_id = p_room_id;
  update public.rooms
    set winner_player_id = null,
        status = case when p_back_to_lobby then 'lobby' else 'playing' end
    where id = p_room_id;
end;
$$;

-- --- Row Level Security ----------------------------------------------
alter table public.rounds enable row level security;
alter table public.bingo_cards enable row level security;
alter table public.room_events enable row level security;

drop policy if exists rounds_select_members on public.rounds;
create policy rounds_select_members on public.rounds
  for select to authenticated using (public.is_room_member(room_id));

drop policy if exists cards_select_members on public.bingo_cards;
create policy cards_select_members on public.bingo_cards
  for select to authenticated using (public.is_room_member(room_id));

drop policy if exists events_select_members on public.room_events;
create policy events_select_members on public.room_events
  for select to authenticated using (public.is_room_member(room_id));

-- (Alla skrivningar sker via RPC:erna ovan – inga direkta insert/update-policys.)

-- --- Behörigheter ----------------------------------------------------
grant select on public.rounds to authenticated;
grant select on public.bingo_cards to authenticated;
grant select on public.room_events to authenticated;
grant execute on function public.spin_wheel(uuid) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;
grant execute on function public.ensure_card(uuid) to authenticated;
grant execute on function public.mark_cross(uuid, int) to authenticated;
grant execute on function public.erase_cross(uuid, uuid, int) to authenticated;
grant execute on function public.reset_game(uuid, boolean) to authenticated;

-- --- Realtid ---------------------------------------------------------
alter table public.rounds replica identity full;
alter table public.bingo_cards replica identity full;
alter table public.room_events replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='rounds') then
    alter publication supabase_realtime add table public.rounds;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='bingo_cards') then
    alter publication supabase_realtime add table public.bingo_cards;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='room_events') then
    alter publication supabase_realtime add table public.room_events;
  end if;
end $$;
