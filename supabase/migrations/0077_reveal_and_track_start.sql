-- =====================================================================
--  LÅTSNURRAN – 0077
--
--  1. ETT SENT "LÅS IN" ÅNGRADE VÄRDENS "VISA SVAR NU".
--     lock_answer avslutas med
--
--       update public.rounds set ... answers_revealed = (v_locked >= v_total)
--
--     — ovillkorligt. Hade värden redan avslöjat rundan med reveal_answers
--     (typiskt när ett lag är segt) och någon låste in EFTER det, räknades
--     flaggan om till false igen: facit försvann för alla, svarsvyn hoppade
--     tillbaka till inmatningsrutorna och mark_cross stängde sin grind.
--     Värden fick trycka "Visa svar nu" en gång till.
--
--     Verifierat i en tillbakarullad transaktion med tre spelare före fixen:
--       A låser              -> locked 1, revealed false
--       värden visar svar    -> locked 1, revealed TRUE
--       A låser en gång till -> locked 1, revealed FALSE   <-- buggen
--
--     Notera sista steget: A var REDAN låst. RPC:n saknade helt spärr mot att
--     låsa in efter avslöjandet, så även ett dubbelklick räckte. Nu returnerar
--     den befintliga raden direkt när rundan är avslöjad, och flaggan kan bara
--     gå från false till true (`or`, inte `=`).
--
--  2. KLIENTEN GAV UPP INNAN SERVERN VAR KLAR.
--     start_random_track köar upp till 4 låtförsök × 2 söksteg, och varje
--     net.http_get hade 6 s timeout = 48 s i värsta fall. Klientens
--     pollningsfönster var 26 s. Servern kunde alltså fortfarande leta när
--     värden fick "Låtstarten tog för lång tid – försök igen."
--
--     Timeouten sänks till 4 s (iTunes svarar normalt under en sekund; en
--     sökning som tagit fyra är död). Klienten får i samma veva polla tills
--     SERVERN säger ifrån i stället för att räkna sekunder själv – serverns
--     egen uppgivningslogik är den som vet när det är slut.
--
--  3. INGEN UTOM VÄRDEN VISSTE ATT EN LÅT VAR PÅ VÄG.
--     Prep-overlayn ("Letar upp låten…") drevs av klientens EGET
--     knapptryck, så bara värden såg den. Alla andra satt i tystnad med
--     "Värden styr rundan" tills klippet plötsligt startade. Nu sätter
--     start_random_track rounds.state = 'loading' när uppslaget köas, vilket
--     når alla via realtiden. (Ny statusvärde => rounds_state_check måste
--     utökas. Samma lärdom som 0037.)
--
--  4. POLLNINGEN VAR EN ENDA FLIK.
--     Hela tillståndsmaskinen drevs av värdens klient. Backgroundade värden
--     fliken strypte mobilen setTimeout och rundan stod still för alla.
--     poll_track_start kräver därför inte längre att anroparen är VÄRD, bara
--     att hen är med i rummet – klienten låter övriga spelare hoppa in som
--     reservpollare först efter några sekunders tystnad.
--
--     Två samtidiga pollare fick inte finnas förut heller, men var omöjligt
--     då (bara en värd). Nu låses pending-raden med `for update`, så två
--     pollare inte kan skicka var sin net.http_get för samma rad. Låsordning
--     oförändrad: rate_limits -> pending_tracks -> resten.
-- =====================================================================

-- --------------------------------------------------------------------
-- 3: nytt tillåtet state-värde.
-- REGEL (0037): ett nytt state kräver ändring på BÅDA ställena – den som
-- skriver värdet och den här constrainten.
-- --------------------------------------------------------------------
alter table public.rounds drop constraint if exists rounds_state_check;
alter table public.rounds add constraint rounds_state_check
  check (state = any (array['spinning', 'playing', 'revealed', 'loading']));


-- --------------------------------------------------------------------
-- 1: lock_answer – kan inte längre ta tillbaka ett avslöjande.
-- --------------------------------------------------------------------
create or replace function public.lock_answer(p_room_id uuid, p_answer text, p_bonus text default '')
returns public.round_answers
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid      uuid := auth.uid();
  v_room     public.rooms;
  v_player   public.players;
  v_round    public.rounds;
  v_ans      public.round_answers;
  v_locked   int;
  v_total    int;
  v_revealed boolean;
  v_kapten   uuid;
  v_bonus    text;
begin
  perform public._rate_limit('answer', 30, interval '1 minute');
  if length(coalesce(p_answer, '')) > 300 then
    raise exception 'Svaret är för långt (max 300 tecken)';
  end if;
  -- Bonusen är ett årtal, inget annat. Trimmas hårt så att inget långt
  -- fritextsvar kan smugglas in i kolumnen.
  v_bonus := left(trim(coalesce(p_bonus, '')), 10);

  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1
    for update;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;
  if v_round.current_track_id is null or v_round.timer_start_at is null then
    raise exception 'Ingen låt har spelats än';
  end if;
  if now() < v_round.timer_start_at - interval '1 second' then
    raise exception 'Vänta tills låten börjat spela';
  end if;

  -- Rundan är redan avslöjad: det finns ingenting att låsa in längre, och att
  -- gå vidare hade räknat om answers_revealed och tagit tillbaka facit.
  -- Tyst retur i stället för fel – den som hamnar här har oftast bara tryckt
  -- två gånger, eller haft ett svar i luften när värden avslöjade.
  if coalesce(v_round.answers_revealed, false) then
    if v_room.team_mode then
      select * into v_ans from public.round_answers
        where round_id = v_round.id and team_id = v_player.team_id;
    else
      select * into v_ans from public.round_answers
        where round_id = v_round.id and player_id = v_player.id;
    end if;
    return v_ans;
  end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;

    v_kapten := public._team_captain(v_player.team_id);
    if v_kapten is not null and v_kapten <> v_player.id then
      raise exception 'Bara lagkaptenen låser in lagets svar';
    end if;

    select * into v_ans from public.round_answers
      where round_id = v_round.id and team_id = v_player.team_id;
    if v_ans.id is null then
      insert into public.round_answers (room_id, round_id, team_id, user_id, answer, bonus_year, locked)
      values (p_room_id, v_round.id, v_player.team_id, v_uid, coalesce(p_answer, ''), v_bonus, true)
      returning * into v_ans;
    elsif not v_ans.locked then
      update public.round_answers
        set answer = coalesce(p_answer, ''), bonus_year = v_bonus, locked = true, updated_at = now()
        where id = v_ans.id returning * into v_ans;
    end if;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.teams where room_id = p_room_id;
  else
    insert into public.round_answers (room_id, round_id, player_id, user_id, answer, bonus_year, locked)
    values (p_room_id, v_round.id, v_player.id, v_uid, coalesce(p_answer, ''), v_bonus, true)
    on conflict (round_id, player_id) do update
      set answer = case when public.round_answers.locked then public.round_answers.answer
                        else excluded.answer end,
          bonus_year = case when public.round_answers.locked then public.round_answers.bonus_year
                            else excluded.bonus_year end,
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
        -- Enkelriktad: ett avslöjande kan bara tändas, aldrig släckas.
        answers_revealed = coalesce(answers_revealed, false) or (v_locked >= v_total)
    where id = v_round.id
    returning answers_revealed into v_revealed;

  if v_revealed then
    perform public._grade_round(v_round.id);
  end if;

  return v_ans;
end;
$function$;

grant execute on function public.lock_answer(uuid, text, text) to authenticated;


-- --------------------------------------------------------------------
-- 2 + 3: start_random_track – kortare timeout, och alla ser att det söks.
-- Oförändrad i övrigt (kroppen är live-dumpen från 0071/0076).
-- --------------------------------------------------------------------
create or replace function public.start_random_track(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  delete from public.pending_tracks where room_id = p_room_id;

  -- Steg 1: ospelad i rummet OCH inte känd som ohittbar.
  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;

  -- Steg 2: släpp kravet på ospelad, behåll bortsorteringen av ohittbara.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
        and (tp.preview_url is not null
             or tp.preview_checked_at is null
             or tp.preview_checked_at < now() - interval '7 days')
      order by random() limit 1;
  end if;

  -- Steg 3: smal pott där allt är markerat – hellre en osäker låt än inget.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  -- Cacheträff: starta direkt, utan att fråga iTunes. Katalograder har ingen
  -- hållbarhetsgräns – de är inte hittade via sökningen och kan inte
  -- verifieras om den vägen.
  if v_track.preview_url is not null
     and (v_track.preview_source = 'catalog'
          or v_track.preview_checked_at > now() - interval '30 days') then
    update public.rounds
      set current_track_id = v_track.preview_url,
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;
    return;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 4, 1);

  -- Säg till ALLA att en låt är på väg. Utan det här visste bara värden
  -- (som tryckte på knappen) att något hände, och övriga satt i tystnad.
  update public.rounds set state = 'loading' where id = v_round.id;
end $function$;

grant execute on function public.start_random_track(uuid) to authenticated;


-- --------------------------------------------------------------------
-- 2 + 4: poll_track_start – vilken medlem som helst får driva uppslaget,
-- och pending-raden låses så två pollare inte dubbelsöker.
-- Oförändrad i övrigt (kroppen är live-dumpen efter 0076).
-- --------------------------------------------------------------------
create or replace function public.poll_track_start(p_room_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_p     public.pending_tracks;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_track  public.track_pool;
  v_url    text;
  v_req    bigint;
  v_bad_net boolean;
begin
  perform public._rate_limit('track_poll', 200, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  -- Medlemskap räcker (0077). Förut krävdes värd, vilket band hela
  -- tillståndsmaskinen till en enda flik: backgroundade värden den strypte
  -- mobilen timers och rundan stod still för alla andra.
  if not exists (
    select 1 from public.players p where p.room_id = p_room_id and p.user_id = v_uid
  ) then
    raise exception 'Du är inte med i rummet';
  end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  -- for update: två pollare får inte skicka var sin sökning för samma rad.
  select * into v_p from public.pending_tracks where room_id = p_room_id for update;
  if v_p.room_id is null then
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

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
    return null;
  end if;

  select * into v_track from public.track_pool where id = v_p.pool_id;

  v_bad_net := coalesce(v_status, 0) <> 200 or coalesce(v_timed, false);
  v_url := null;
  if not v_bad_net then
    v_url := public._itunes_pick(v_body, v_track.title, v_track.artist);
  end if;

  if v_url is not null then
    update public.rounds
      set current_track_id = v_url,
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

    update public.track_pool
      set preview_url = v_url, preview_checked_at = now()
      where id = v_track.id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  if v_bad_net then
    if v_p.net_retries >= 1 then
      delete from public.pending_tracks where room_id = p_room_id;
      raise exception 'Kunde inte nå musiktjänsten just nu (%) – vänta en stund och försök igen.',
        case when coalesce(v_timed, false) then 'timeout' else 'svar ' || coalesce(v_status, 0)::text end;
    end if;
    v_req := net.http_get(
      url := case when v_p.search_stage = 1
                  then public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist)
                  else public._itunes_search_url(v_track.title || ' ' || v_track.artist) end,
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, net_retries = v_p.net_retries + 1 where room_id = p_room_id;
    return null;
  end if;

  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2, net_retries = 0 where room_id = p_room_id;
    return null;
  end if;

  -- Katalograder får ALDRIG nollställas här: de hittades inte via sökningen
  -- och kan inte verifieras den vägen, så en miss betyder ingenting om dem.
  -- _mark_unfindable() bär spärren (0071) – tidigare skrevs raden rakt av.
  perform public._mark_unfindable(v_p.pool_id);

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      and tp.id <> v_p.pool_id
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;
  if v_track.id is null then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  -- Samma undantag som start_random_track fick i 0071: katalograder har ingen
  -- hållbarhetsgräns. Utan det skickades de till sökningen efter 30 dagar.
  if v_track.preview_url is not null
     and (v_track.preview_source = 'catalog'
          or v_track.preview_checked_at > now() - interval '30 days') then
    update public.rounds
      set current_track_id = v_track.preview_url,
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

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1, net_retries = 0
    where room_id = p_room_id;
  return null;
end $function$;

grant execute on function public.poll_track_start(uuid) to authenticated;
