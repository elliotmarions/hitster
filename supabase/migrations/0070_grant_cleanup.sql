-- =====================================================================
--  LÅTSNURRAN – Städa rättigheterna som plattformen delat ut på nytt
--
--  BAKGRUND – OCH EN RÄTTELSE TILL NOTEN I 0069. Det stod där att
--  plattformen "återställt" 0023:s default-privilegier. Det stämmer inte.
--  0023 rad 385 lyder:
--
--      alter default privileges in schema public
--        revoke execute on functions from public;
--
--  – alltså bara från PUBLIC. Supabase default-ACL delar ut EXECUTE till
--  anon och authenticated UTTRYCKLIGEN, som namngivna roller, inte via
--  PUBLIC. Revoken tog därför aldrig i dem. Samma sak på tabellsidan
--  (`anon=arwdDxtm`).
--
--  Följden syns rakt igenom historiken: 0023 rensade rättigheterna på de
--  funktioner som fanns DÅ (rad 377–378), och de har varit stängda sedan
--  dess – mark_cross, spin_wheel, create_room. Men varje funktion som
--  skapats EFTER 0023, eller fått en ny signatur och därmed räknas som ny
--  (lock_answer via 0064, poll_track_start, track_pool_counts,
--  gen_bingo_grid(text[]) via 0031 …), föddes med anon=X authenticated=X.
--
--  LÄRDOMEN är alltså inte "plattformen ändrar saker bakom ryggen" utan:
--  `revoke ... from public` räcker INTE mot Supabase default-ACL. Roller
--  måste namnges. Det är därför den här migrationen revokar från
--  `public, anon, authenticated` överallt, inklusive i alter default
--  privileges.
--
--  0069 stängde de två värsta funktionerna; det här är hela genomgången.
--
--  MÄTT LÄGE 2026-08-07 (live-DB):
--    · 38 funktioner hade EXECUTE för anon, varav 11 SECURITY DEFINER
--    · anon hade INSERT/UPDATE/DELETE på samtliga speltabeller
--    · anon OCH authenticated hade TRUNCATE på samtliga speltabeller
--    · authenticated hade INSERT/UPDATE/DELETE på tabeller som saknar
--      policy för de kommandona (bingo_cards, rounds, teams, round_answers,
--      team_messages, room_events, player_stats)
--
--  HUR ILLA VAR DET? RLS räddade det mesta: det finns INGEN policy som gäller
--  anon, så anons skrivrättigheter var döda i praktiken, och authenticateds
--  extra rättigheter träffade tabeller utan skrivpolicy. TRUNCATE lyder dock
--  INTE under RLS – där var det bara PostgREST:s brist på verb som stod
--  emellan. Rättigheterna var alltså en andra lås som stod olåst: dagen någon
--  lägger till en policy en aning för brett blir hålet omedelbart verkligt.
--
--  MODELLEN EFTER DEN HÄR MIGRATIONEN:
--
--    anon            SELECT på tabellerna (och inget mer) + server_now().
--                    SELECT:en MÅSTE vara kvar: en besökare utan session som
--                    öppnar en rumslänk ska få 200 [] från RLS, inte 401.
--                    Det är så useRoom hamnar i 'notfound' och visar JoinGate
--                    i stället för ett fel. server_now() MÅSTE vara kvar:
--                    serverTime.js anropar den avsiktligt med bara apikey,
--                    förbi supabase-js auth-kö, för att klocksynken inte ska
--                    vänta på inloggningen (0045).
--
--    authenticated   SELECT på tabellerna, UPDATE på rooms begränsad till
--                    exakt lobbyns reglage, och EXECUTE på de 26 RPC:er som
--                    klienten faktiskt anropar – plus is_room_member och
--                    _my_team, som RLS-policyerna själva kallar och därför
--                    måste kunna köras av den som frågar.
--
--    ingen av dem    TRUNCATE, REFERENCES, TRIGGER, eller EXECUTE på interna
--                    hjälpfunktioner (_clean_title, _rate_limit, _judge_answer,
--                    gen_room_code, triggerfunktionerna …). Trigger-
--                    funktioner behöver ingen EXECUTE åt den som skriver:
--                    rättigheten prövas när triggern skapas, inte när den
--                    fyrar. Det är verifierat mot live-DB, inte antaget.
--
--  Listan är en ALLOWLIST, inte en radering rad för rad: allt återkallas och
--  bara det uppräknade delas ut igen. Nya funktioner måste alltså ta med sin
--  egen `grant execute ... to authenticated` – samma regel som gällt sedan
--  0023, nu med ett städat utgångsläge.
--
--  Idempotent. Ändrar inga funktionskroppar.
-- =====================================================================

-- --- 1. tabellerna ----------------------------------------------------
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from anon, authenticated;

-- Lobbyns reglage skrivs direkt av värden (RLS: rooms_update_host).
-- Kolumnlistan är hela skyddet mot att någon sätter status/winner_* och
-- farmar statistik via on_room_stats-triggern.
grant update (erase_rule_enabled, team_mode, swedish_mode,
              genre, genres, year_bands, year_min, year_max)
  on public.rooms to authenticated;

-- --- 2. funktionerna --------------------------------------------------
do $$
declare
  f record;
  -- RPC:er som klienten anropar (src/lib/game.js + src/lib/rooms.js),
  -- samt de två funktioner RLS-policyerna själva kallar.
  v_keep_auth constant text[] := array[
    'assign_player', 'close_room_if_host_absent', 'create_room', 'create_team',
    'delete_team', 'ensure_card', 'erase_cross', 'join_room', 'leave_room',
    'lock_answer', 'mark_cross', 'override_answer', 'poll_track_start',
    'remove_absent_player', 'reset_game', 'reveal_answers', 'send_team_message',
    'server_now', 'set_team_captain', 'spin_wheel', 'start_game',
    'start_random_track', 'touch_last_seen', 'track_pool_counts',
    'track_pool_genre_counts', 'track_pool_selection_count', 'unmark_cross',
    'is_room_member', '_my_team'
  ];
  -- Enda funktionen som ska gå att nå utan session (klocksynken).
  v_keep_anon constant text[] := array['server_now'];
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_userbyid(p.proowner) = 'postgres'
       and p.prokind = 'f'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (v_keep_auth) then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    if f.proname = any (v_keep_anon) then
      execute format('grant execute on function %s to anon', f.sig);
    end if;
  end loop;
end $$;

-- --- 3. stäng defaulten för det som skapas härnäst --------------------
-- Rollerna måste namnges; `from public` ensamt biter inte på Supabase
-- default-ACL (se noten överst). Verifierat efteråt: pg_default_acl för
-- postgres/public är nu 'postgres=X service_role=X'.
-- Raden för supabase_admin/public står kvar öppen och kan inte ändras
-- härifrån – den styr bara plattformens egna funktioner, inte våra.
alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated;

notify pgrst, 'reload schema';
