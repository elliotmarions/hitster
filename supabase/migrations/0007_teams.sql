-- =====================================================================
--  HITSTER BINGO ONLINE – Lagläge (spela som lag)
--
--  Lobbyn får en på/av-knapp "Lagläge". När PÅ delar värden in spelarna i
--  lag; varje lag spelar med EN gemensam bricka och ETT gemensamt svar, och
--  vem som helst i laget kan kryssa/svara. Vinst = ett lag fyller rad/kolumn.
--  När AV spelar alla individuellt precis som förut (oförändrat beteende).
--
--  Spelenheten blir alltså "lag ELLER spelare" beroende på rooms.team_mode.
--  RPC:erna nedan löser upp rätt bricka/svar utifrån läget.
--
--  Additiv + idempotent. Kör efter 0006. Avsluta manuell körning läser om
--  PostgREST-schemat sist (notify pgrst).
-- =====================================================================

-- --- rooms: lagläge + lagvinnare ------------------------------------
alter table public.rooms add column if not exists team_mode boolean not null default false;
alter table public.rooms add column if not exists winner_team_id uuid;

-- --- teams -----------------------------------------------------------
create table if not exists public.teams (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  name        text not null,
  color       text,
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists teams_room_idx on public.teams (room_id);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'rooms_winner_team_fk') then
    alter table public.rooms add constraint rooms_winner_team_fk
      foreign key (winner_team_id) references public.teams (id) on delete set null;
  end if;
end $$;

-- --- players: lagtillhörighet ---------------------------------------
alter table public.players add column if not exists team_id uuid
  references public.teams (id) on delete set null;

-- --- bingo_cards: kan tillhöra ett lag istället för en spelare -------
alter table public.bingo_cards add column if not exists team_id uuid
  references public.teams (id) on delete cascade;
alter table public.bingo_cards alter column player_id drop not null;
alter table public.bingo_cards alter column user_id drop not null;
create unique index if not exists bingo_cards_team_uidx
  on public.bingo_cards (room_id, team_id) where team_id is not null;

-- --- round_answers: kan tillhöra ett lag ----------------------------
alter table public.round_answers add column if not exists team_id uuid
  references public.teams (id) on delete cascade;
alter table public.round_answers alter column player_id drop not null;
create unique index if not exists round_answers_team_uidx
  on public.round_answers (round_id, team_id) where team_id is not null;

-- ====================================================================
--  Lag-administration (bara värden) – SECURITY DEFINER
-- ====================================================================

create or replace function public.create_team(p_room_id uuid, p_name text, p_color text default null)
returns public.teams
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_team public.teams;
  v_sort int;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan skapa lag'; end if;

  select coalesce(max(sort), 0) + 1 into v_sort from public.teams where room_id = p_room_id;
  insert into public.teams (room_id, name, color, sort)
  values (p_room_id, coalesce(nullif(trim(p_name), ''), 'Lag ' || v_sort), p_color, v_sort)
  returning * into v_team;
  return v_team;
end;
$$;

create or replace function public.delete_team(p_room_id uuid, p_team_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan ta bort lag'; end if;

  update public.players set team_id = null where room_id = p_room_id and team_id = p_team_id;
  delete from public.teams where id = p_team_id and room_id = p_room_id;
end;
$$;

-- Placera (eller flytta) en spelare i ett lag. p_team_id = null → ta ur lag.
create or replace function public.assign_player(p_room_id uuid, p_player_id uuid, p_team_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan dela in lag'; end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams where id = p_team_id and room_id = p_room_id
  ) then
    raise exception 'Laget finns inte i rummet';
  end if;

  update public.players set team_id = p_team_id
    where id = p_player_id and room_id = p_room_id;
end;
$$;

-- ====================================================================
--  Spel-RPC:er omskrivna för lag ELLER spelare (utifrån rooms.team_mode)
-- ====================================================================

-- --- starta spelet: dela ut brickor per lag / per spelare -----------
create or replace function public.start_game(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_p    public.players;
  v_tid  uuid;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta spelet'; end if;

  -- Färsk giv: rensa gamla brickor (byter läge/omstart från lobbyn).
  delete from public.bingo_cards where room_id = p_room_id;

  if v_room.team_mode then
    -- Spelare utan lag → eget lag (uppkallat efter spelaren).
    for v_p in select * from public.players where room_id = p_room_id and team_id is null loop
      insert into public.teams (room_id, name, sort)
      values (p_room_id, v_p.display_name, 900)
      returning id into v_tid;
      update public.players set team_id = v_tid where id = v_p.id;
    end loop;

    -- En bricka per lag.
    insert into public.bingo_cards (room_id, team_id, grid)
    select p_room_id, t.id, public.gen_bingo_grid()
      from public.teams t where t.room_id = p_room_id;
  else
    -- En bricka per spelare (oförändrat läge).
    insert into public.bingo_cards (room_id, player_id, user_id, grid)
    select p_room_id, p.id, p.user_id, public.gen_bingo_grid()
      from public.players p where p.room_id = p_room_id;
  end if;

  update public.rooms
    set status = 'playing', winner_player_id = null, winner_team_id = null
    where id = p_room_id;
end;
$$;

-- --- säkerställ bricka för den som kommer in (sena joins) ------------
create or replace function public.ensure_card(p_room_id uuid)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_tid    uuid;
begin
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  if v_room.team_mode then
    v_tid := v_player.team_id;
    if v_tid is null then
      insert into public.teams (room_id, name, sort)
      values (p_room_id, v_player.display_name, 900) returning id into v_tid;
      update public.players set team_id = v_tid where id = v_player.id;
    end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_tid;
    if v_card.id is not null then return v_card; end if;
    insert into public.bingo_cards (room_id, team_id, grid)
    select p_room_id, v_tid, public.gen_bingo_grid()
    where not exists (select 1 from public.bingo_cards where room_id = p_room_id and team_id = v_tid);
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_tid;
    return v_card;
  end if;

  -- Solo-läge (oförändrat)
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

-- --- kryssa en ruta (lag- eller spelarbricka) -----------------------
create or replace function public.mark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  v_label  text;
  r int; c int; line_full boolean;
begin
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_player.team_id;
  else
    select * into v_card from public.bingo_cards where room_id = p_room_id and player_id = v_player.id;
  end if;
  if v_card.id is null then raise exception 'Ingen bricka'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);

  for r in 0..4 loop
    line_full := true;
    for c in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;
  for c in 0..4 loop
    line_full := true;
    for r in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  if v_won then
    if v_room.team_mode then
      select name into v_label from public.teams where id = v_player.team_id;
      update public.rooms set status = 'finished', winner_team_id = v_player.team_id, winner_player_id = null
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'HITSTER_WIN', jsonb_build_object('team_id', v_player.team_id, 'display_name', v_label));
    else
      update public.rooms set status = 'finished', winner_player_id = v_player.id
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'HITSTER_WIN', jsonb_build_object('player_id', v_player.id, 'display_name', v_player.display_name));
    end if;
  end if;

  return v_card;
end;
$$;

-- --- ångra eget kryss (lag- eller spelarbricka) ---------------------
create or replace function public.unmark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_grid   jsonb;
  v_won    boolean := false;
  r int; c int; line_full boolean;
begin
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_player.team_id;
  else
    select * into v_card from public.bingo_cards where room_id = p_room_id and player_id = v_player.id;
  end if;
  if v_card.id is null then raise exception 'Ingen bricka'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);

  for r in 0..4 loop
    line_full := true;
    for c in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;
  for c in 0..4 loop
    line_full := true;
    for r in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Bröts den registrerade vinstlinjen? Nollställ vinsten.
  if not v_won then
    if v_room.team_mode and v_room.winner_team_id = v_player.team_id then
      update public.rooms set status = 'playing', winner_team_id = null where id = p_room_id;
    elsif not v_room.team_mode and v_room.winner_player_id = v_player.id then
      update public.rooms set status = 'playing', winner_player_id = null where id = p_room_id;
    end if;
  end if;

  return v_card;
end;
$$;

-- --- sudda på en ANNAN enhets bricka (suddregel) --------------------
create or replace function public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
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
  if v_room.team_mode then
    if v_card.team_id = v_player.team_id then raise exception 'Du kan inte sudda på ditt eget lags bricka'; end if;
  else
    if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$$;

-- --- lås in svar (lag- eller spelarsvar) ----------------------------
create or replace function public.lock_answer(p_room_id uuid, p_answer text)
returns public.round_answers
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_ans    public.round_answers;
  v_locked int;
  v_total  int;
begin
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;
  if v_round.current_track_id is null or v_round.timer_start_at is null then
    raise exception 'Ingen låt har spelats än';
  end if;
  if now() < v_round.timer_start_at + interval '24 seconds' then
    raise exception 'Vänta tills låten spelat klart innan du låser in svaret';
  end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    -- Upsert per lag.
    select * into v_ans from public.round_answers
      where round_id = v_round.id and team_id = v_player.team_id;
    if v_ans.id is null then
      insert into public.round_answers (room_id, round_id, team_id, user_id, answer, locked)
      values (p_room_id, v_round.id, v_player.team_id, v_uid, coalesce(p_answer, ''), true)
      returning * into v_ans;
    elsif not v_ans.locked then
      update public.round_answers set answer = coalesce(p_answer, ''), locked = true, updated_at = now()
        where id = v_ans.id returning * into v_ans;
    end if;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.teams where room_id = p_room_id;
  else
    -- Upsert per spelare (oförändrat).
    insert into public.round_answers (room_id, round_id, player_id, user_id, answer, locked)
    values (p_room_id, v_round.id, v_player.id, v_uid, coalesce(p_answer, ''), true)
    on conflict (round_id, player_id) do update
      set answer = case when public.round_answers.locked then public.round_answers.answer
                        else excluded.answer end,
          locked = true, updated_at = now()
    returning * into v_ans;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.players where room_id = p_room_id;
  end if;

  update public.rounds
    set locked_count = v_locked, answers_revealed = (v_locked >= v_total)
    where id = v_round.id;

  return v_ans;
end;
$$;

-- --- återställ (spela igen / tillbaka till lobby) --------------------
create or replace function public.reset_game(p_room_id uuid, p_back_to_lobby boolean default false)
returns void
language plpgsql security definer set search_path = public
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
    set winner_player_id = null, winner_team_id = null,
        status = case when p_back_to_lobby then 'lobby' else 'playing' end
    where id = p_room_id;
end;
$$;

-- ====================================================================
--  RLS, behörigheter, realtid för teams
-- ====================================================================
alter table public.teams enable row level security;

drop policy if exists teams_select_members on public.teams;
create policy teams_select_members on public.teams
  for select to authenticated using (public.is_room_member(room_id));
-- (Alla skrivningar sker via RPC:erna ovan.)

grant select on public.teams to authenticated;
grant execute on function public.create_team(uuid, text, text) to authenticated;
grant execute on function public.delete_team(uuid, uuid) to authenticated;
grant execute on function public.assign_player(uuid, uuid, uuid) to authenticated;

alter table public.teams replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'teams'
  ) then
    alter publication supabase_realtime add table public.teams;
  end if;
end $$;

notify pgrst, 'reload schema';
