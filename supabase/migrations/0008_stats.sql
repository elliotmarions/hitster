-- =====================================================================
--  HITSTER BINGO ONLINE – Enkel spelarstatistik
--
--  Räknar spelade matcher och vinster per användare. Uppdateras helt
--  automatiskt via en trigger på rooms (ingen ändring i spel-RPC:erna):
--   - status blir 'playing' (ny match startad) → +1 spelad för alla i rummet
--   - winner_player_id sätts (solo)             → +1 vinst för spelaren
--   - winner_team_id sätts (lag)                → +1 vinst för alla i laget
--
--  RLS: man ser bara sin egen rad. Additiv + idempotent. Kör efter 0007.
-- =====================================================================

create table if not exists public.player_stats (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  games_played  int not null default 0,
  games_won     int not null default 0,
  updated_at    timestamptz not null default now()
);

-- --- Trigger som räknar upp statistiken -----------------------------
create or replace function public.on_room_stats()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- Ny match startad (lobby/finished -> playing): +1 spelad för alla i rummet.
  if new.status = 'playing' and coalesce(old.status, '') <> 'playing' then
    insert into public.player_stats (user_id, games_played)
    select p.user_id, 1 from public.players p where p.room_id = new.id
    on conflict (user_id) do update
      set games_played = public.player_stats.games_played + 1, updated_at = now();
  end if;

  -- Ny vinnare (solo): +1 vinst.
  if new.winner_player_id is not null
     and new.winner_player_id is distinct from old.winner_player_id then
    insert into public.player_stats (user_id, games_won)
    select pl.user_id, 1 from public.players pl where pl.id = new.winner_player_id
    on conflict (user_id) do update
      set games_won = public.player_stats.games_won + 1, updated_at = now();
  end if;

  -- Ny vinnare (lag): +1 vinst för alla i laget.
  if new.winner_team_id is not null
     and new.winner_team_id is distinct from old.winner_team_id then
    insert into public.player_stats (user_id, games_won)
    select pl.user_id, 1 from public.players pl where pl.team_id = new.winner_team_id
    on conflict (user_id) do update
      set games_won = public.player_stats.games_won + 1, updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists room_stats_trigger on public.rooms;
create trigger room_stats_trigger
  after update on public.rooms
  for each row execute function public.on_room_stats();

-- --- RLS: bara min egen statistik -----------------------------------
alter table public.player_stats enable row level security;
drop policy if exists stats_select_own on public.player_stats;
create policy stats_select_own on public.player_stats
  for select to authenticated using (user_id = auth.uid());

grant select on public.player_stats to authenticated;

notify pgrst, 'reload schema';
