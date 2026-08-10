-- =====================================================================
--  LÅTSNURRAN – ett valt årsspann väger lika mycket som ett annat
--
--  _pool_match() unionar rummets band och `order by random()` går över
--  hela unionen, så varje LÅT får samma chans. Mätt i potten just nu:
--  1950–1960 är 99 låtar, 1989–1998 är 1557. Ett rum som valt båda
--  spelar därför 94 % nittiotal, och det smala spannet syns knappt.
--  Det är inte vad två rader i lobbyn ser ut att betyda.
--
--  Urvalet görs därför i två led i stället för ett, så att en rad väger
--  lika oavsett hur många låtar den råkar täcka. Band som inte har någon
--  träff kvar efter språk- och genrefiltren räknas inte med – annars
--  hade urvalet ibland pekat på tomma intet och rundan fallit.
--
--  Tomt year_bands = ingen årsgräns och inget att välja mellan; då är
--  _pool_bands() en ren genomgång och allt beteende är oförändrat. Ett
--  enda band ger likaså exakt samma pott som förut.
--
--  Funktionskropparna är i övrigt oförändrade sedan 0077.
--
--  Additiv + idempotent. Kör efter 0077.
-- =====================================================================

-- --- 1. bandet som ska gälla för den här dragningen -------------------
--  Volatile: den läser random() och får inte veckas ihop av planeraren.
--  Anropas därför också EN gång till en variabel, aldrig inne i ett
--  where-villkor som prövas per rad.
create or replace function public._pool_bands(
  p_swedish boolean, p_bands jsonb, p_genres jsonb)
returns jsonb
language sql
volatile
set search_path = public
as $function$
  select coalesce(
    (select jsonb_build_array(b)
       from jsonb_array_elements(coalesce(p_bands, '[]'::jsonb)) b
      where exists (
        select 1 from public.track_pool tp
         where public._pool_match(tp, p_swedish, jsonb_build_array(b), p_genres))
      order by random()
      limit 1),
    coalesce(p_bands, '[]'::jsonb));
$function$;

-- Ingen grant: klienten anropar den aldrig, och SECURITY DEFINER-kropparna
-- nedan kör som ägaren. Allowlisten i 0070 gäller alltså fortfarande.


-- --- 2. start_random_track -------------------------------------------
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
  v_bands jsonb;
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

  -- Samma band gäller alla tre stegen: faller steg 1 ska steg 2 leta i det
  -- urval rundan redan bestämt sig för, inte i ett annat.
  v_bands := public._pool_bands(v_room.swedish_mode, v_room.year_bands, v_room.genres);

  -- Steg 1: ospelad i rummet OCH inte känd som ohittbar.
  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;

  -- Steg 2: släpp kravet på ospelad, behåll bortsorteringen av ohittbara.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
        and (tp.preview_url is not null
             or tp.preview_checked_at is null
             or tp.preview_checked_at < now() - interval '7 days')
      order by random() limit 1;
  end if;

  -- Steg 3: smal pott där allt är markerat – hellre en osäker låt än inget.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
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


-- --- 3. poll_track_start ---------------------------------------------
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
  v_bands  jsonb;
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

  -- Ersättaren hämtas på samma villkor som den första låten. Ett nytt anrop,
  -- inte det gamla värdet: den låt som föll bort kan ha varit den sista
  -- spelbara i sitt band, och då ska ersättaren komma från ett band som
  -- fortfarande har något att ge.
  v_bands := public._pool_bands(v_room.swedish_mode, v_room.year_bands, v_room.genres);

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
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

notify pgrst, 'reload schema';
