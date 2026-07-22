-- =====================================================================
--  LÅTSNURRAN – Rate limiting (anropsspärr per användare)
--
--  0023 satte TAK (30 spelare/rum, 20 rum/timme, längdgränser) men ingen
--  TAKT: en skriptad klient som pratar direkt med PostgREST kunde anropa
--  spin_wheel, start_random_track m.fl. hur ofta som helst. Det bränner
--  Supabase-kvoten, spammar realtidskanalen till alla i rummet och – i
--  start_random_tracks fall – låter databasen hamra iTunes åt angriparen.
--
--  Lösningen är en räknare per (användare, hink) med rullande fönster:
--
--    perform public._rate_limit('spin', 30, interval '1 minute');
--
--  läggs som FÖRSTA rad i varje RPC. Överskrids taket kastas ett fel med
--  SQLSTATE PT429 → PostgREST svarar HTTP 429 Too Many Requests.
--
--  Utöver hinken tickar varje anrop även en global hink ('*', 400/min) så
--  att ingen kan kringgå taket genom att blanda anropstyper. Global hink
--  räknas alltid FÖRST → samma låsordning överallt → inga deadlocks.
--
--  ── VIKTIGT ATT FÖRSTÅ: rollback ──────────────────────────────────────
--  Ett PostgREST-anrop är EN transaktion. Kastar RPC:n ett fel rullas hela
--  anropet tillbaka – inklusive räknarens ökning. Konsekvenser:
--
--   • Lyckade anrop räknas och spärras korrekt. När taket väl nåtts blir
--     räknaren stående på taket (varje nytt försök ökar till tak+1, kastar,
--     rullas tillbaka) → spärren håller tills fönstret löper ut. ✔
--   • Anrop som ändå misslyckas av annan orsak ("Bara värden kan …") räknas
--     INTE. Att hamra med ogiltiga anrop begränsas alltså inte här – det är
--     billiga, indexerade uppslag, och angriparen måste dessutom känna till
--     ett rums-UUID. Medveten avgränsning; riktig kantspärr kräver ett lager
--     framför PostgREST (klienten pratar direkt med Supabase, inte via
--     Vercel, så vercel.json hjälper inte).
--   • UNDANTAG som fixas här: join_room. Där är det just de misslyckade
--     anropen som är attacken (gissa rumskoder), så "okänd kod" returnerar
--     nu null i stället för att kasta → transaktionen committar och varje
--     försök räknas. Klientens rooms.js tolkar null som "hittades inte".
--
--  ── FÖR FRAMTIDA MIGRATIONER ─────────────────────────────────────────
--  Varje NY eller OMSKRIVEN RPC måste börja med perform public._rate_limit
--  (annars tappas spärren tyst) och sluta med grant execute … to
--  authenticated (0023:s default privileges ger inte PUBLIC execute).
--
--  Funktionerna nedan är hämtade ordagrant från live-databasen och har fått
--  exakt en rad tillagd var. Ingen annan logik är ändrad (utom join_room,
--  se ovan).
--
--  Idempotent. Kör efter 0026.
-- =====================================================================

-- ====================================================================
--  1) Räknartabellen
-- ====================================================================
-- UNLOGGED: räknarna är kortlivade och får gärna nollställas vid en krasch
-- – slipper WAL-skrivningar för varje anrop.
create unlogged table if not exists public.rate_limits (
  user_id      uuid        not null,
  bucket       text        not null,
  window_start timestamptz not null default now(),
  hits         int         not null default 0,
  primary key (user_id, bucket)
);

-- Ingen klient ska nå tabellen: RLS på utan policyer + inga grants alls.
-- SECURITY DEFINER-funktionerna nedan kör som ägaren och går förbi RLS.
alter table public.rate_limits enable row level security;
revoke all on table public.rate_limits from anon, authenticated;

create index if not exists rate_limits_window_idx on public.rate_limits (window_start);

-- ====================================================================
--  2) Själva spärren
-- ====================================================================

-- Räknar upp EN hink och kastar om taket överskrids. Upserten låser raden
-- (user_id, bucket) → två samtidiga anrop kan inte båda slinka igenom.
create or replace function public._rate_limit_hit(
  p_uid    uuid,
  p_bucket text,
  p_limit  int,
  p_window interval
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hits int;
begin
  insert into public.rate_limits as rl (user_id, bucket, window_start, hits)
  values (p_uid, p_bucket, now(), 1)
  on conflict (user_id, bucket) do update
    -- Fönstret utgånget → börja om på 1, annars öka.
    set hits = case when rl.window_start < now() - p_window then 1
                    else rl.hits + 1 end,
        window_start = case when rl.window_start < now() - p_window then now()
                    else rl.window_start end
  returning rl.hits into v_hits;

  if v_hits > p_limit then
    -- PT429 → PostgREST svarar HTTP 429. hint = hinken, för felsökning.
    raise exception 'För många anrop på kort tid – vänta en stund och försök igen.'
      using errcode = 'PT429', hint = p_bucket;
  end if;
end;
$$;

-- Publika ingången: global hink först (låsordning), sedan den specifika.
create or replace function public._rate_limit(
  p_bucket text,
  p_limit  int,
  p_window interval default interval '1 minute'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Inte inloggad'; end if;
  perform public._rate_limit_hit(v_uid, '*', 400, interval '1 minute');
  perform public._rate_limit_hit(v_uid, p_bucket, p_limit, p_window);
end;
$$;

-- Hjälparna anropas bara inifrån andra SECURITY DEFINER-funktioner (som kör
-- som ägaren) → klienten ska inte kunna nå dem.
revoke execute on function public._rate_limit_hit(uuid, text, int, interval) from public, anon, authenticated;
revoke execute on function public._rate_limit(text, int, interval) from public, anon, authenticated;

-- ====================================================================
--  3) RPC:erna med spärr
-- ====================================================================

-- --- assign_player(uuid,uuid,uuid) ---
CREATE OR REPLACE FUNCTION public.assign_player(p_room_id uuid, p_player_id uuid, p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('team_admin', 60, interval '1 minute');
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
$function$
;

-- --- create_room(text,text) ---
CREATE OR REPLACE FUNCTION public.create_room(p_name text, p_display_name text)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('room_create', 5, interval '1 minute');
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
$function$
;

-- --- create_team(uuid,text,text) ---
CREATE OR REPLACE FUNCTION public.create_team(p_room_id uuid, p_name text, p_color text DEFAULT NULL::text)
 RETURNS teams
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_team public.teams;
  v_sort int;
begin
  perform public._rate_limit('team_admin', 60, interval '1 minute');
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
$function$
;

-- --- delete_team(uuid,uuid) ---
CREATE OR REPLACE FUNCTION public.delete_team(p_room_id uuid, p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('team_admin', 60, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan ta bort lag'; end if;

  update public.players set team_id = null where room_id = p_room_id and team_id = p_team_id;
  delete from public.teams where id = p_team_id and room_id = p_room_id;
end;
$function$
;

-- --- ensure_card(uuid) ---
CREATE OR REPLACE FUNCTION public.ensure_card(p_room_id uuid)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_tid    uuid;
begin
  perform public._rate_limit('card', 30, interval '1 minute');
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
$function$
;

-- --- erase_cross(uuid,uuid,integer) ---
CREATE OR REPLACE FUNCTION public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_card   public.bingo_cards;
  v_myans  public.round_answers;
  v_grid   jsonb;
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
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

  -- SPÄRR: sudd kräver att din egen enhet gissat rätt (avslöjat + rätt).
  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan du suddar';
  end if;
  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;
  if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
    raise exception 'Bara rätt svar får sudda';
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
$function$
;

-- --- join_room(text,text) ---
CREATE OR REPLACE FUNCTION public.join_room(p_code text, p_display_name text)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('room_join', 15, interval '1 minute');
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

  -- Okänd kod: returnera null i stället för att kasta fel. Ett kastat fel
  -- rullar tillbaka HELA anropet – även räknaren ovan – vilket skulle göra
  -- kodgissning gratis. Klienten (rooms.js) tolkar null som "hittades inte".
  if v_room.id is null then
    return null;
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
$function$
;

-- --- leave_room(uuid) ---
CREATE OR REPLACE FUNCTION public.leave_room(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('room_leave', 20, interval '1 minute');
  if v_uid is null then return; end if;
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then return; end if;

  -- Ta bort min egen spelar-rad (om jag är med i rummet).
  delete from public.players where room_id = p_room_id and user_id = v_uid;

  -- Om VÄRDEN lämnar ett rum som inte redan är avslutat: avsluta för alla.
  if v_room.host_user_id = v_uid and v_room.status <> 'finished' then
    update public.rooms
      set status = 'finished',
          ended_reason = 'host_left',
          winner_player_id = null,
          winner_team_id = null
      where id = p_room_id;
  end if;
end;
$function$
;

-- --- lock_answer(uuid,text) ---
CREATE OR REPLACE FUNCTION public.lock_answer(p_room_id uuid, p_answer text)
 RETURNS round_answers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  perform public._rate_limit('answer', 30, interval '1 minute');
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
$function$
;

-- --- mark_cross(uuid,integer) ---
CREATE OR REPLACE FUNCTION public.mark_cross(p_room_id uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_myans  public.round_answers;
  v_grid   jsonb;
  v_won    boolean := false;
  v_label  text;
  v_unit   uuid;
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
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

  -- SPÄRR (ovillkorlig): kryss kräver att DENNA rundas låt spelats och
  -- avslöjats, att den egna enhetens svar var rätt (auto eller värdens
  -- override) OCH bara ETT kryss per runda. Ingen låt än = inget kryss.
  if v_round.current_track_id is null then
    raise exception 'Starta låten och gissa innan ni kryssar';
  end if;
  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan ni kryssar';
  end if;
  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;
  if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
    raise exception 'Bara rätt svar får kryssa den här rundan';
  end if;
  if coalesce(v_myans.has_marked, false) then
    raise exception 'Ni har redan kryssat en ruta den här rundan';
  end if;

  -- Efter att spelet avgjorts får man bara kryssa i den AVGÖRANDE rundan (för
  -- att hinna bli medvinnare); inte i någon annan.
  if v_room.status = 'finished' and v_room.winner_round_id is distinct from v_round.id then
    raise exception 'Spelet är avgjort';
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Krysset är lagt: markera att enheten förbrukat rundans kryss.
  if v_myans.id is not null then
    update public.round_answers set has_marked = true where id = v_myans.id;
  end if;

  if v_won then
    v_unit := case when v_room.team_mode then v_player.team_id else v_player.id end;

    if v_room.status <> 'finished' then
      -- Första vinsten avgör rundan.
      if v_room.team_mode then
        select name into v_label from public.teams where id = v_unit;
        update public.rooms
          set status = 'finished', winner_round_id = v_round.id,
              winner_unit_ids = jsonb_build_array(v_unit),
              winner_team_id = v_unit, winner_player_id = null
          where id = p_room_id;
        insert into public.room_events (room_id, type, payload)
        values (p_room_id, 'GAME_WIN', jsonb_build_object('team_id', v_unit, 'display_name', v_label));
      else
        update public.rooms
          set status = 'finished', winner_round_id = v_round.id,
              winner_unit_ids = jsonb_build_array(v_unit),
              winner_player_id = v_unit
          where id = p_room_id;
        insert into public.room_events (room_id, type, payload)
        values (p_room_id, 'GAME_WIN', jsonb_build_object('player_id', v_unit, 'display_name', v_player.display_name));
      end if;
    elsif v_room.winner_round_id = v_round.id then
      -- Oavgjort: lägg till som medvinnare (om inte redan med).
      update public.rooms
        set winner_unit_ids = case when winner_unit_ids ? v_unit::text
                                   then winner_unit_ids
                                   else winner_unit_ids || to_jsonb(v_unit) end
        where id = p_room_id;
    end if;
  end if;

  return v_card;
end;
$function$
;

-- --- override_answer(uuid,uuid,boolean) ---
CREATE OR REPLACE FUNCTION public.override_answer(p_room_id uuid, p_answer_id uuid, p_correct boolean)
 RETURNS round_answers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_ans  public.round_answers;
begin
  perform public._rate_limit('answer_override', 60, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan rätta svar'; end if;

  update public.round_answers
    set override_correct = p_correct
    where id = p_answer_id and room_id = p_room_id
    returning * into v_ans;
  if v_ans.id is null then raise exception 'Svaret finns inte'; end if;
  return v_ans;
end;
$function$
;

-- --- poll_track_start(uuid) ---
CREATE OR REPLACE FUNCTION public.poll_track_start(p_room_id uuid)
 RETURNS rounds
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_p     public.pending_tracks;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_json   jsonb;
  v_track  public.track_pool;
  v_hit    jsonb;
  v_word   text;
  v_req    bigint;
begin
  perform public._rate_limit('track_poll', 200, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  select * into v_p from public.pending_tracks where room_id = p_room_id;
  if v_p.room_id is null then
    -- Ingen pågående uppslagning: redan klart om rundan fått sin låt.
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  -- Uppslag som hör till en gammal runda: kasta det.
  if v_round.id is null or v_p.round_id <> v_round.id or v_round.current_track_id is not null then
    delete from public.pending_tracks where room_id = p_room_id;
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  select status_code, timed_out, content into v_status, v_timed, v_body
    from net._http_response where id = v_p.request_id;
  if not found then
    return null;  -- svaret har inte kommit än → klienten pollar igen
  end if;

  select * into v_track from public.track_pool where id = v_p.pool_id;

  -- Tolka svaret; fel/skräp behandlas som "ingen träff".
  v_hit := null;
  if coalesce(v_status, 0) = 200 and not coalesce(v_timed, false) then
    begin
      v_json := v_body::jsonb;
    exception when others then
      v_json := null;
    end;
    if v_json is not null then
      -- Föredra träff där artistnamnet matchar (första ordet, som previewApi.js).
      v_word := lower(split_part(coalesce(v_track.artist, ''), ' ', 1));
      select r into v_hit
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'previewUrl', '') like 'https://%'
          and lower(coalesce(r ->> 'artistName', '')) like '%' || v_word || '%'
        limit 1;
      if v_hit is null then
        select r into v_hit
          from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
          where coalesce(r ->> 'previewUrl', '') like 'https://%'
          limit 1;
      end if;
    end if;
  end if;

  if v_hit is not null then
    -- Träff! Sätt låten på rundan + spara facit bakom reveal-spärren.
    update public.rounds
      set current_track_id = v_hit ->> 'previewUrl',
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id
      returning * into v_round;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  -- Ingen träff: prova bredare sökterm (rå titel), därefter en annan låt.
  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2 where room_id = p_room_id;
    return null;
  end if;

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and tp.id <> v_p.pool_id
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1
    where room_id = p_room_id;
  return null;
end $function$
;

-- --- reset_game(uuid,boolean) ---
CREATE OR REPLACE FUNCTION public.reset_game(p_room_id uuid, p_back_to_lobby boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('game_control', 20, interval '1 minute');
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
$function$
;

-- --- reveal_answers(uuid) ---
CREATE OR REPLACE FUNCTION public.reveal_answers(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
begin
  perform public._rate_limit('answer_reveal', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan avslöja svaren'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  update public.rounds set answers_revealed = true where id = v_round.id;
  perform public._grade_round(v_round.id);
end;
$function$
;

-- --- send_team_message(uuid,text) ---
CREATE OR REPLACE FUNCTION public.send_team_message(p_room_id uuid, p_body text)
 RETURNS team_messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_body   text := trim(coalesce(p_body, ''));
  v_recent int;
  v_msg    public.team_messages;
begin
  perform public._rate_limit('chat', 40, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if not v_room.team_mode then raise exception 'Lagchatten finns bara i lagläge'; end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;
  if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;

  if v_body = '' then raise exception 'Skriv något först'; end if;
  if length(v_body) > 300 then raise exception 'Meddelandet är för långt (max 300 tecken)'; end if;

  -- Enkel flood-spärr i samma anda som 0023:s övriga gränser.
  select count(*) into v_recent from public.team_messages
    where user_id = v_uid and created_at > now() - interval '10 seconds';
  if v_recent >= 15 then raise exception 'Ta det lugnt – för många meddelanden på kort tid'; end if;

  insert into public.team_messages (room_id, team_id, player_id, user_id, author_name, body)
  values (
    p_room_id,
    v_player.team_id,
    v_player.id,
    v_uid,
    coalesce(nullif(trim(v_player.display_name), ''), 'Spelare'),
    v_body
  )
  returning * into v_msg;

  return v_msg;
end;
$function$
;

-- --- spin_wheel(uuid) ---
CREATE OR REPLACE FUNCTION public.spin_wheel(p_room_id uuid)
 RETURNS rounds
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_prev  public.rounds;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats constant text[] := array['decade', 'artist', 'exact_year', 'approx_year', 'title'];
begin
  perform public._rate_limit('spin', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan snurra'; end if;

  -- SPÄRR: lämna inte en avslöjad runda medan någon rätt-svarande ännu inte
  -- kryssat (och har en ledig ruta i kategorin att kryssa).
  select * into v_prev from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_prev.id is not null and v_prev.current_track_id is not null and v_prev.answers_revealed then
    if exists (
      select 1
      from public.round_answers ra
      join public.bingo_cards bc
        on bc.room_id = p_room_id
       and (
         (v_room.team_mode and bc.team_id = ra.team_id)
         or (not v_room.team_mode and bc.player_id = ra.player_id)
       )
      where ra.round_id = v_prev.id
        and coalesce(ra.override_correct, ra.auto_correct) is true
        and coalesce(ra.has_marked, false) = false
        and exists (
          select 1 from jsonb_array_elements(bc.grid) cell
          where cell ->> 'category' = v_prev.category
            and (cell ->> 'filled')::boolean = false
        )
    ) then
      raise exception 'Alla som hade rätt måste kryssa innan du snurrar igen';
    end if;
  end if;

  v_cat := cats[floor(random() * 5)::int + 1];
  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  insert into public.rounds (room_id, round_number, category, spun_by, state, timer_start_at)
  values (p_room_id, v_num, v_cat, v_uid, 'playing', now() + interval '4.2 seconds')
  returning * into v_round;

  update public.rooms set status = 'playing'
    where id = p_room_id and status <> 'finished';
  return v_round;
end;
$function$
;

-- --- start_game(uuid) ---
CREATE OR REPLACE FUNCTION public.start_game(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_p    public.players;
  v_tid  uuid;
begin
  perform public._rate_limit('game_control', 20, interval '1 minute');
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
$function$
;

-- --- start_random_track(uuid) ---
CREATE OR REPLACE FUNCTION public.start_random_track(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_track public.track_pool;
  v_req   bigint;
begin
  perform public._rate_limit('track_start', 20, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;
  if v_round.current_track_id is not null then raise exception 'Rundan har redan en låt'; end if;

  -- Kasta ev. gammal påbörjad uppslagning (t.ex. efter avbruten polling).
  delete from public.pending_tracks where room_id = p_room_id;

  -- Slumpa en låt ur rätt pott, undvik repriser i rummet (round_tracks minns).
  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    -- Hela potten spelad i det här rummet → tillåt repriser.
    select tp.* into v_track from public.track_pool tp
      where tp.sv = v_room.swedish_mode order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 5, 1);
end $function$
;

-- --- unmark_cross(uuid,integer) ---
CREATE OR REPLACE FUNCTION public.unmark_cross(p_room_id uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  v_unit   uuid;
  v_list   jsonb;
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
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
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Bröts enhetens vinstlinje? Ta bort den ur vinnarlistan. Töms listan →
  -- tillbaka till spel; annars uppdatera primär vinnarkolumn till kvarvarande.
  if not v_won then
    v_unit := case when v_room.team_mode then v_player.team_id else v_player.id end;
    v_list := coalesce((
      select jsonb_agg(x) from jsonb_array_elements(v_room.winner_unit_ids) x
      where x <> to_jsonb(v_unit)
    ), '[]'::jsonb);

    if v_list = '[]'::jsonb then
      update public.rooms
        set status = 'playing', winner_round_id = null, winner_unit_ids = '[]'::jsonb,
            winner_team_id = null, winner_player_id = null
        where id = p_room_id;
    else
      update public.rooms
        set winner_unit_ids = v_list,
            winner_team_id = case when v_room.team_mode then (v_list ->> 0)::uuid else null end,
            winner_player_id = case when v_room.team_mode then null else (v_list ->> 0)::uuid end
        where id = p_room_id;
    end if;
  end if;

  -- Frigör rundans kryss så ett felklick kan läggas om.
  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is not null then
    if v_room.team_mode then
      update public.round_answers set has_marked = false
        where round_id = v_round.id and team_id = v_player.team_id;
    else
      update public.round_answers set has_marked = false
        where round_id = v_round.id and player_id = v_player.id;
    end if;
  end if;

  return v_card;
end;
$function$
;

-- --- track_pool_counts() ---
-- Var LANGUAGE sql + STABLE; en STABLE-funktion får inte skriva, så den kan
-- inte ticka räknaren. Skrivs därför om till plpgsql (samma fråga, samma svar).
-- Den räknar över hela låtpotten (~3 200 rader) vid varje anrop → värd att spärra.
create or replace function public.track_pool_counts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_counts jsonb;
begin
  perform public._rate_limit('pool_counts', 20, interval '1 minute');
  select jsonb_build_object('all', count(*) filter (where not sv),
                            'sv',  count(*) filter (where sv))
    into v_counts
  from public.track_pool;
  return v_counts;
end;
$$;

-- ====================================================================
--  4) Behörigheter
-- ====================================================================
-- create or replace behåller befintliga grants, men vi sätter dem explicit
-- så migrationen även fungerar på en databas byggd från noll.
grant execute on function public.create_room(text, text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;
grant execute on function public.reset_game(uuid, boolean) to authenticated;
grant execute on function public.spin_wheel(uuid) to authenticated;
grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;
grant execute on function public.track_pool_counts() to authenticated;
grant execute on function public.ensure_card(uuid) to authenticated;
grant execute on function public.mark_cross(uuid, integer) to authenticated;
grant execute on function public.unmark_cross(uuid, integer) to authenticated;
grant execute on function public.erase_cross(uuid, uuid, integer) to authenticated;
grant execute on function public.lock_answer(uuid, text) to authenticated;
grant execute on function public.reveal_answers(uuid) to authenticated;
grant execute on function public.override_answer(uuid, uuid, boolean) to authenticated;
grant execute on function public.create_team(uuid, text, text) to authenticated;
grant execute on function public.delete_team(uuid, uuid) to authenticated;
grant execute on function public.assign_player(uuid, uuid, uuid) to authenticated;
grant execute on function public.send_team_message(uuid, text) to authenticated;

-- ====================================================================
--  5) Städning av gamla räknare
-- ====================================================================
-- En rad per (användare, hink) och de flesta användare är anonyma gäster →
-- tabellen växer annars i evighet. Rader vars fönster är över ett dygn gamla
-- är per definition döda.
do $$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'latsnurran-rate-limit-cleanup') then
    perform cron.unschedule('latsnurran-rate-limit-cleanup');
  end if;
  perform cron.schedule(
    'latsnurran-rate-limit-cleanup',
    '43 * * * *',
    $job$delete from public.rate_limits where window_start < now() - interval '1 day'$job$
  );
exception when others then
  raise notice 'pg_cron kunde inte aktiveras (%) – städning av rate_limits hoppas över.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
