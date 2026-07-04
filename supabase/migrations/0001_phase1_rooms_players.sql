-- =====================================================================
--  HITSTER BINGO ONLINE – Fas 1
--  Rum, spelare och realtidslobby.
--
--  Kör denna i Supabase (SQL Editor -> New query -> klistra in -> Run),
--  eller via Supabase CLI (`supabase db push`).
--
--  Designval kring Row Level Security (RLS):
--  För att kunna GÅ MED i ett rum via kod måste man kunna slå upp rummet
--  INNAN man är medlem – men vi vill inte att vem som helst kan läsa alla
--  rum. Lösningen: all skrivning sker via SECURITY DEFINER-funktioner
--  (create_room / join_room) som kör med förhöjd behörighet, medan direkt
--  läsning/skrivning mot tabellerna är låst till rummets medlemmar.
-- =====================================================================

create extension if not exists pgcrypto;

-- --- Tabeller --------------------------------------------------------

create table if not exists public.rooms (
  id                  uuid primary key default gen_random_uuid(),
  code                text unique not null,
  name                text,
  host_user_id        uuid not null references auth.users (id) on delete cascade,
  status              text not null default 'lobby'
                        check (status in ('lobby', 'playing', 'finished')),
  song_source         text not null default 'playlist'
                        check (song_source in ('playlist', 'manual')),
  playlist_uri        text,
  erase_rule_enabled  boolean not null default false,
  created_at          timestamptz not null default now()
);

create table if not exists public.players (
  id                  uuid primary key default gen_random_uuid(),
  room_id             uuid not null references public.rooms (id) on delete cascade,
  user_id             uuid not null references auth.users (id) on delete cascade,
  display_name        text not null,
  is_host             boolean not null default false,
  spotify_connected   boolean not null default false,
  joined_at           timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  unique (room_id, user_id)
);

create index if not exists players_room_id_idx on public.players (room_id);

-- --- Hjälpfunktioner -------------------------------------------------

-- Är den inloggade användaren medlem i rummet?
-- SECURITY DEFINER för att undvika oändlig rekursion i RLS-policyn på players.
create or replace function public.is_room_member(p_room uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.players
    where room_id = p_room and user_id = auth.uid()
  );
$$;

-- Genererar en unik, läsbar rumskod (utan tvetydiga tecken som 0/O, 1/I/L).
create or replace function public.gen_room_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  i int;
begin
  loop
    v_code := '';
    for i in 1..5 loop
      v_code := v_code || substr(alphabet, floor(random() * length(alphabet))::int + 1, 1);
    end loop;
    -- Kvalificerad jämförelse (r.code vs variabeln v_code) för att undvika krock.
    exit when not exists (select 1 from public.rooms r where r.code = v_code);
  end loop;
  return v_code;
end;
$$;

-- --- RPC: skapa rum (blir värd) --------------------------------------
create or replace function public.create_room(p_name text, p_display_name text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'Inte inloggad';
  end if;
  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'Visningsnamn krävs';
  end if;

  insert into public.rooms (code, name, host_user_id)
  values (public.gen_room_code(), nullif(trim(p_name), ''), v_uid)
  returning * into v_room;

  insert into public.players (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, trim(p_display_name), true);

  return v_room;
end;
$$;

-- --- RPC: gå med i rum via kod ---------------------------------------
create or replace function public.join_room(p_code text, p_display_name text)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'Inte inloggad';
  end if;
  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'Visningsnamn krävs';
  end if;

  select * into v_room from public.rooms
  where code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));

  if v_room.id is null then
    raise exception 'Rummet hittades inte' using errcode = 'no_data_found';
  end if;

  -- Upsert: gå med, eller uppdatera namnet om man redan är i rummet.
  insert into public.players (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, trim(p_display_name), false)
  on conflict (room_id, user_id)
  do update set display_name = excluded.display_name, last_seen_at = now();

  return v_room;
end;
$$;

-- --- Row Level Security ----------------------------------------------

alter table public.rooms enable row level security;
alter table public.players enable row level security;

-- rooms: bara medlemmar får läsa; bara värden får uppdatera.
drop policy if exists rooms_select_members on public.rooms;
create policy rooms_select_members on public.rooms
  for select to authenticated
  using (public.is_room_member(id));

drop policy if exists rooms_update_host on public.rooms;
create policy rooms_update_host on public.rooms
  for update to authenticated
  using (host_user_id = auth.uid())
  with check (host_user_id = auth.uid());

-- players: bara medlemmar ser rummets spelare; man får bara ändra/radera sin egen rad.
drop policy if exists players_select_members on public.players;
create policy players_select_members on public.players
  for select to authenticated
  using (public.is_room_member(room_id));

drop policy if exists players_update_self on public.players;
create policy players_update_self on public.players
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists players_delete_self on public.players;
create policy players_delete_self on public.players
  for delete to authenticated
  using (user_id = auth.uid());

-- (Ingen INSERT-policy med flit: att skapa rum / gå med sker enbart via
--  create_room / join_room ovan.)

-- --- Behörigheter ----------------------------------------------------
grant select, update on public.rooms to authenticated;
grant select, update, delete on public.players to authenticated;
grant execute on function public.is_room_member(uuid) to authenticated;
grant execute on function public.create_room(text, text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;

-- --- Realtid ---------------------------------------------------------
-- replica identity full gör att DELETE-händelser innehåller room_id, så att
-- klientens filter (room_id=eq.…) fångar även när en spelare lämnar rummet.
alter table public.players replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players'
  ) then
    alter publication supabase_realtime add table public.players;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms'
  ) then
    alter publication supabase_realtime add table public.rooms;
  end if;
end $$;
