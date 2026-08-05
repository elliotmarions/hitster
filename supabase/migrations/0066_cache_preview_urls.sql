-- =====================================================================
--  LÅTSNURRAN – Cacha preview-URL:er och sluta hamra på iTunes
--
--  SYMTOM efter 0065: inte längre tvärnit, men många rundor misslyckas och
--  låtstarten tar lång tid. Ibland funkar det efter några försök.
--
--  DIAGNOS. "Lång tid" är avslöjande. En misslyckad MATCHNING är snabb:
--  svaret kommer på en halvsekund, ingen träff, vidare direkt. Att det drar
--  ut betyder att anropen inte besvaras – timeout på 4000 ms, sex gånger
--  (3 låtar × 2 sökningar) = 24 sekunder, precis under klientens 26.
--
--  Och det finns en självförstärkande loop: varje miss utlöser ett nytt
--  iTunes-anrop, och när värden dessutom trycker "Starta låt" flera gånger
--  växer anropstakten. Apples sök-API tål ungefär 20 anrop per minut och
--  svarar annars 403 – som koden inte skilde från "ingen träff" och därför
--  besvarade med ännu fler anrop. Ju sämre det gick, desto hårdare tryckte
--  servern på.
--
--  TRE ÅTGÄRDER
--
--   1. CACHE. En låt som en gång hittats slås aldrig upp igen:
--      track_pool.preview_url + preview_checked_at, giltig i 30 dagar. Är
--      låten cachad startar rundan direkt i start_random_track – noll
--      iTunes-anrop, ingen pollning, ingen väntan. Det är den stora vinsten:
--      potten värms upp av spelandet och anropen glesnar för varje kväll.
--      Träffen som cachas är den strikta matchningens, så rätt facit följer
--      med (0062).
--
--   2. TRANSPORTFEL BRÄNNER INTE LÅTAR. Ett 403 eller en timeout säger
--      ingenting om låten – att då kasta den och prova en annan är att
--      straffa fel part och skicka ännu ett anrop. Nu görs samma sökning om
--      EN gång; hjälper inte det avbryts starten direkt med ett begripligt
--      fel. Misslyckanden går därmed från 24 sekunder till några få.
--
--   3. TIMEOUT 4000 → 6000 ms. Fyra sekunder var snålt när Apple svarar
--      långsamt men korrekt. Går nu att höja utan att spränga klientens
--      26-sekundersfönster, eftersom transportfel inte längre kedjas.
--
--  Additiv + idempotent. Kör efter 0065.
-- =====================================================================

-- --- 1. cache-kolumner ------------------------------------------------
--  track_pool är oläsbar för klienter (revoke i 0024), så preview-URL:en
--  läcker inget facit i förväg.
alter table public.track_pool
  add column if not exists preview_url        text,
  add column if not exists preview_checked_at timestamptz;

-- Räknare för omtag vid transportfel (skilt från attempts_left, som räknar LÅTAR).
alter table public.pending_tracks
  add column if not exists net_retries int not null default 0;

-- --- 2. start_random_track: använd cachen när den finns ---------------
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

  delete from public.pending_tracks where room_id = p_room_id;

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  -- CACHETRÄFF: starta direkt, utan att fråga iTunes.
  if v_track.preview_url is not null
     and v_track.preview_checked_at > now() - interval '30 days' then
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

    -- Ingen pending-rad: klientens första poll ser att rundan har en låt
    -- och returnerar den direkt.
    return;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 6000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 3, 1);
end $function$;

-- --- 3. poll_track_start: fyll cachen, skilj transportfel från missar --
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
  v_clean  text;
  v_ntitle text;
  v_req    bigint;
  v_bad_net boolean;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
begin
  perform public._rate_limit('track_poll', 200, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  select * into v_p from public.pending_tracks where room_id = p_room_id;
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

  v_hit := null;
  if not v_bad_net then
    begin
      v_json := v_body::jsonb;
    exception when others then
      v_json := null;
    end;
    if v_json is not null then
      v_word := coalesce(
        nullif(split_part(public._norm_title(coalesce(v_track.artist, '')), ' ', 1), ''),
        public._norm_title(coalesce(v_track.artist, '')));
      v_clean  := lower(public._clean_title(v_track.title));
      v_ntitle := public._norm_title(public._clean_title(v_track.title));

      select x.r into v_hit
      from (
        select r,
               lower(coalesce(r ->> 'trackName', ''))      as tn,
               lower(coalesce(r ->> 'collectionName', '')) as cn,
               public._norm_title(r ->> 'trackName')       as ntn,
               public._norm_title(r ->> 'artistName')      as nan
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'previewUrl', '') like 'https://%'
      ) x
      where (v_word = '' or ' ' || x.nan || ' ' like '% ' || v_word || ' %')
        and x.cn !~ v_junk_cn
        and (x.tn = v_clean or x.tn !~ v_junk_tn)
        and v_ntitle <> ''
        and (x.ntn = v_ntitle
             or x.ntn like v_ntitle || ' %'
             or v_ntitle like x.ntn || ' %')
      order by
        (case when x.ntn = v_ntitle then 0
              when x.ntn like v_ntitle || ' %' then 1
              else 2 end),
        length(x.tn)
      limit 1;
    end if;
  end if;

  if v_hit is not null then
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

    -- Fyll cachen: nästa gång låten dras startar den utan iTunes-anrop.
    update public.track_pool
      set preview_url = v_hit ->> 'previewUrl', preview_checked_at = now()
      where id = v_track.id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  -- TRANSPORTFEL: låten är oskyldig. Gör om SAMMA sökning en gång, ge sedan
  -- upp direkt i stället för att kedja sex anrop mot ett API som just sagt nej.
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
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, net_retries = v_p.net_retries + 1 where room_id = p_room_id;
    return null;
  end if;

  -- Svaret kom fram men innehöll ingen match: bredda sökningen, sedan ny låt.
  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2, net_retries = 0 where room_id = p_room_id;
    return null;
  end if;

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
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
    timeout_milliseconds := 6000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1, net_retries = 0
    where room_id = p_room_id;
  return null;
end $function$;

grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
