-- =====================================================================
--  LÅTSNURRAN – Säkerhetshärdning
--
--  Täpper hål som en fientlig klient (som pratar direkt med PostgREST,
--  förbi vår app) annars kunde utnyttja:
--
--  1) KOLUMNRÄTTIGHETER. RLS-policyer styr RADER, inte KOLUMNER. Policyn
--     players_update_self lät en spelare uppdatera ALLA kolumner i sin egen
--     rad – t.ex. team_id (byta till vinnande lag), is_host eller room_id.
--     Klienten skriver aldrig direkt i players → UPDATE/DELETE återkallas
--     helt (lämna rum går via leave_room-RPC:n). rooms_update_host lät
--     värden skriva alla kolumner – t.ex. winner_player_id, som triggar
--     statistik-räknaren → vinst-farmning. Klienten uppdaterar bara de tre
--     reglagen → rättigheten begränsas till exakt de kolumnerna.
--
--  2) INDATA-GRÄNSER. Inga längdgränser fanns server-side på namn/svar –
--     megabyte-strängar hade broadcastats i realtid till alla i rummet.
--     Nu: visningsnamn ≤ 40, rumsnamn ≤ 60, lagnamn ≤ 40, svar ≤ 300,
--     lagfärg måste vara en hex-färg. Dessutom tak: 30 spelare/rum,
--     20 lag/rum, 20 skapade rum per värd och timme.
--
--  3) KRYPTOGRAFISK RUMSKOD. gen_room_code använde random() (förutsägbar
--     PRNG) → byts till gen_random_bytes (pgcrypto).
--
--  4) FUNKTIONSRÄTTIGHETER. Postgres ger som standard EXECUTE till PUBLIC
--     på nya funktioner → även oinloggade (anon) kunde anropa RPC:erna
--     (de stoppades av medlemskontrollerna, men brände DB-tid). PUBLIC/anon
--     återkallas; authenticated behåller/får explicita grants. OBS för
--     framtida migrationer: default privileges ändras så att NYA funktioner
--     INTE får PUBLIC execute – varje ny RPC måste alltså avslutas med
--     "grant execute on function ... to authenticated;".
--
--  5) STÄDNING. Döda Spotify-kolumner tas bort (song_source, playlist_uri,
--     spotify_connected). Gamla rum (>30 dagar) rensas dagligen via pg_cron
--     (cascade tar spelare/rundor/brickor/svar/lag; player_stats behålls).
--
--  Medveten kvarvarande begränsning (dokumenterad, ej fixad): facit
--  (rounds.current_track_meta) är läsbart för rummets medlemmar medan låten
--  spelar, och ljud-URL:en avslöjar ändå låten för den som slår upp den.
--  Fusk-skydd mot tekniskt kunniga spelare kräver server-side-ljud – utanför
--  spelets hederssystem-ambition.
--
--  Idempotent. Kör efter 0022.
-- =====================================================================

-- ====================================================================
--  1) Kolumnrättigheter
-- ====================================================================

-- players: klienten läser bara; all skrivning går via RPC:er.
revoke update, delete on table public.players from authenticated;
drop policy if exists players_update_self on public.players;
drop policy if exists players_delete_self on public.players;

-- rooms: värden får bara toggla spelreglerna direkt – inget annat.
revoke update on table public.rooms from authenticated;
grant update (erase_rule_enabled, team_mode, swedish_mode)
  on public.rooms to authenticated;
-- (Policyn rooms_update_host ligger kvar och begränsar raden till värdens rum.)

-- ====================================================================
--  2) Döda Spotify-kolumner bort
-- ====================================================================
alter table public.rooms drop column if exists song_source;
alter table public.rooms drop column if exists playlist_uri;
alter table public.players drop column if exists spotify_connected;

-- ====================================================================
--  3) Kryptografisk rumskod
-- ====================================================================
-- OBS: gen_random_bytes (pgcrypto) ligger i extensions-schemat på Supabase →
-- search_path måste inkludera det.
create or replace function public.gen_room_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  -- Utan tvetydiga tecken (0/O, 1/I/L). 31 tecken × 5 positioner ≈ 28,6 M koder.
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code  text;
  i int;
begin
  loop
    v_bytes := gen_random_bytes(5);
    v_code := '';
    for i in 0..4 loop
      v_code := v_code || substr(alphabet, (get_byte(v_bytes, i) % 31) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.rooms r where r.code = v_code);
  end loop;
  return v_code;
end;
$$;

-- ====================================================================
--  4) create_room: längdgränser + max 20 nya rum per värd och timme
-- ====================================================================
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
  if length(trim(p_display_name)) > 40 then
    raise exception 'Visningsnamnet är för långt (max 40 tecken)';
  end if;
  if length(coalesce(trim(p_name), '')) > 60 then
    raise exception 'Rumsnamnet är för långt (max 60 tecken)';
  end if;
  if (select count(*) from public.rooms
      where host_user_id = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Du har skapat många rum på kort tid – vänta en stund.';
  end if;

  insert into public.rooms (code, name, host_user_id)
  values (public.gen_room_code(), nullif(trim(p_name), ''), v_uid)
  returning * into v_room;

  insert into public.players (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, trim(p_display_name), true);

  return v_room;
end;
$$;

-- ====================================================================
--  5) join_room: längdgräns + max 30 spelare per rum
-- ====================================================================
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
  if length(trim(p_display_name)) > 40 then
    raise exception 'Visningsnamnet är för långt (max 40 tecken)';
  end if;

  select * into v_room from public.rooms
  where code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));

  if v_room.id is null then
    raise exception 'Rummet hittades inte' using errcode = 'no_data_found';
  end if;

  -- Fullt rum stoppar bara NYA spelare (den som redan är med får uppdatera sitt namn).
  if not exists (select 1 from public.players
                 where room_id = v_room.id and user_id = v_uid)
     and (select count(*) from public.players where room_id = v_room.id) >= 30 then
    raise exception 'Rummet är fullt (max 30 spelare)';
  end if;

  insert into public.players (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, trim(p_display_name), false)
  on conflict (room_id, user_id)
  do update set display_name = excluded.display_name, last_seen_at = now();

  return v_room;
end;
$$;

-- ====================================================================
--  6) create_team: längd-/färgvalidering + max 20 lag per rum
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

  if length(coalesce(trim(p_name), '')) > 40 then
    raise exception 'Lagnamnet är för långt (max 40 tecken)';
  end if;
  if p_color is not null and p_color !~ '^#[0-9A-Fa-f]{3,8}$' then
    raise exception 'Ogiltig lagfärg';
  end if;
  if (select count(*) from public.teams where room_id = p_room_id) >= 20 then
    raise exception 'Rummet har redan max antal lag (20)';
  end if;

  select coalesce(max(sort), 0) + 1 into v_sort from public.teams where room_id = p_room_id;
  insert into public.teams (room_id, name, color, sort)
  values (p_room_id, coalesce(nullif(trim(p_name), ''), 'Lag ' || v_sort), p_color, v_sort)
  returning * into v_team;
  return v_team;
end;
$$;

-- ====================================================================
--  7) lock_answer: svarslängd max 300 tecken (annars som 0019)
-- ====================================================================
create or replace function public.lock_answer(p_room_id uuid, p_answer text)
returns public.round_answers
language plpgsql security definer set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_room     public.rooms;
  v_player   public.players;
  v_round    public.rounds;
  v_ans      public.round_answers;
  v_locked   int;
  v_total    int;
  v_revealed boolean;
begin
  if length(coalesce(p_answer, '')) > 300 then
    raise exception 'Svaret är för långt (max 300 tecken)';
  end if;

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
    set locked_count = v_locked,
        locked_units = coalesce((
          select jsonb_agg(u) from (
            select case when v_room.team_mode then ra.team_id else ra.player_id end as u
            from public.round_answers ra
            where ra.round_id = v_round.id and ra.locked
          ) s
        ), '[]'::jsonb),
        answers_revealed = (v_locked >= v_total)
    where id = v_round.id
    returning answers_revealed into v_revealed;

  if v_revealed then
    perform public._grade_round(v_round.id);
  end if;

  return v_ans;
end;
$$;

-- ====================================================================
--  8) start_track: kräv https-URL + sanera metadatat (bara kända fält)
-- ====================================================================
create or replace function public.start_track(
  p_room_id uuid,
  p_track_uri text,
  p_track_meta jsonb
)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_meta  jsonb;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  if p_track_uri is null or p_track_uri !~ '^https://' or length(p_track_uri) > 600 then
    raise exception 'Ogiltig ljud-URL';
  end if;
  -- Släpp bara igenom fälten spelet använder, med rimliga längder.
  v_meta := jsonb_build_object(
    'name',   left(coalesce(p_track_meta ->> 'name', ''), 200),
    'artist', left(coalesce(p_track_meta ->> 'artist', ''), 200),
    'year',   left(coalesce(p_track_meta ->> 'year', ''), 8)
  );

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;

  update public.rounds
    set current_track_id = p_track_uri,
        current_track_meta = v_meta,
        state = 'playing',
        -- start_at: 3 s fram i tiden så alla klienter hinner starta synkat.
        timer_start_at = now() + interval '3 seconds'
    where id = v_round.id
    returning * into v_round;

  return v_round;
end;
$$;

-- ====================================================================
--  9) Funktionsrättigheter: bort med PUBLIC/anon, in med explicit grant
-- ====================================================================

-- leave_room (0018) saknade explicit grant och levde på default-PUBLIC.
grant execute on function public.leave_room(uuid) to authenticated;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_room', 'join_room', 'leave_room', 'gen_room_code', 'gen_bingo_grid',
        'is_room_member', 'spin_wheel', 'start_game', 'ensure_card', 'mark_cross',
        'unmark_cross', 'erase_cross', 'reset_game', 'start_track', 'lock_answer',
        'reveal_answers', 'override_answer', 'create_team', 'delete_team',
        'assign_player', '_grade_round', '_judge_answer', '_fuzzy_text',
        '_norm_text', '_grid_has_line', 'on_room_stats'
      )
  loop
    execute format('revoke execute on function %s from public', f.sig);
    execute format('revoke execute on function %s from anon', f.sig);
  end loop;
end $$;

-- Nya funktioner ska INTE få PUBLIC execute automatiskt. Kom ihåg i framtida
-- migrationer: avsluta alltid nya RPC:er med
--   grant execute on function public.<namn>(...) to authenticated;
alter default privileges in schema public revoke execute on functions from public;

-- ====================================================================
--  10) Daglig städning av gamla rum (pg_cron, om tillgängligt)
-- ====================================================================
do $$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'latsnurran-cleanup') then
    perform cron.unschedule('latsnurran-cleanup');
  end if;
  -- 04:17 UTC varje natt: radera rum äldre än 30 dagar. Cascade tar spelare,
  -- rundor, brickor, svar, lag och händelser. player_stats påverkas inte.
  perform cron.schedule(
    'latsnurran-cleanup',
    '17 4 * * *',
    $job$delete from public.rooms where created_at < now() - interval '30 days'$job$
  );
exception when others then
  raise notice 'pg_cron kunde inte aktiveras (%) – rumsstädning hoppas över.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
