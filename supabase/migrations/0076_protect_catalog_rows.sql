-- =====================================================================
--  LÅTSNURRAN – Tre hål som granskningen av 0069–0075 hittade
--
--  1. SPELET KUNDE RADERA NATTENS LÄKNING.
--     0071 läkte 404 låtar ur Apples artistkatalog och märkte dem
--     preview_source = 'catalog': de hittas inte via sökningen, så de får
--     aldrig sökas om. start_random_track fick undantaget. poll_track_start
--     kördes aldrig om och stod kvar med 0068:s kropp, där det fattas på två
--     ställen:
--
--       * reservlåtens cacheprövning krävde preview_checked_at < 30 dagar,
--         så en katalograd skickades till sökningen 30 dagar efter läkningen
--       * misslyckades sökningen nollställdes preview_url utan villkor
--
--     Sedan var kedjan sluten: _warm_pool_enqueue hoppar över katalograder,
--     så raden läktes aldrig igen, och _retire_unplayable plockade bort den
--     ur potten. _mark_unfindable() skrevs i 0071 med exakt rätt spärr – och
--     anropades inte från någon rad. Nu gör den det.
--
--  2. STÄDNINGEN SAKNADE LIVE-PAUSEN.
--     _warm_pool_enqueue, _artist_probe_enqueue och _artist_probe_collect
--     pausar alla när det finns en rad i pending_tracks. _retire_unplayable
--     fick inte den spärren när den började gå var femte minut i 0074, och
--     pending_tracks.pool_id kaskaderar vid delete: raderas låten mitt i ett
--     uppslag försvinner rummets pending-rad och värden får "Ingen pågående
--     låtstart" mitt i en runda.
--
--  3. STEG 3 KUNDE LÄKA IN FEL NAMNE.
--     Matchningen i 0075 jämför pottens artistnyckel och titeln, men aldrig
--     svarets artistName. För steg 2 gör det ingenting – svaret ÄR en artists
--     katalog. Steg 3 är attribute=artistTerm, en sökning över artister, och
--     kan svara med en annan artist som har en låt med samma titel. Den skulle
--     sparas som 'catalog', alltså med löftet att aldrig verifieras om.
--
--     Villkoret är strikt likhet på _artist_key. Stavar Apple artisten med
--     andra accenter än potten uteblir läkningen och raden pensioneras i
--     stället – men retired_tracks behåller allt, och en pensionerad rad går
--     att bära tillbaka. En felläkt rad går inte att upptäcka alls.
--
--  Bara funktionskroppar. Additiv + idempotent. Kör efter 0075.
-- =====================================================================

-- --- 1. spelet skyddar katalogen ---------------------------------------
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
  v_track  public.track_pool;
  v_url    text;
  v_req    bigint;
  v_bad_net boolean;
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
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, net_retries = v_p.net_retries + 1 where room_id = p_room_id;
    return null;
  end if;

  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 6000
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
    timeout_milliseconds := 6000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1, net_retries = 0
    where room_id = p_room_id;
  return null;
end $function$;

-- --- 2. städningen pausar för live-trafik -------------------------------
create or replace function public._retire_unplayable(p_batch int default 50)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n int := 0;
begin
  -- LIVE-TRAFIKEN GÅR FÖRE, samma paus som de andra bakgrundsjobben har.
  -- pending_tracks.pool_id kaskaderar vid delete: raderas låten mitt i ett
  -- uppslag försvinner rummets pending-rad, och värdens nästa poll_track_start
  -- kastar "Ingen pågående låtstart" mitt i festen.
  if exists (select 1 from public.pending_tracks) then
    return 0;
  end if;

  with klara as (
    select tp.id, tp.title, tp.artist, tp.year, tp.sv, tp.genre, tp.preview_checked_at
      from public.track_pool tp
      join public.artist_probe ap
        on ap.artist_key = public._artist_key(tp.artist) and ap.sv = tp.sv
     where tp.preview_url is null
       and tp.preview_checked_at is not null      -- 1. sökningen har provat
       and ap.probed_at is not null               -- 2. artistkatalogen har provat
       and ap.term_probed_at is not null          -- 3. artistTerm har provat
       and ap.term_probed_at < now() - interval '2 hours'
     limit least(greatest(coalesce(p_batch, 50), 0), 500)
  ), flytt as (
    insert into public.retired_tracks
      (id, title, artist, year, sv, genre, preview_checked_at, reason)
    select id, title, artist, year, sv, genre, preview_checked_at,
           'ingen träff hos Apple: sökning, artistkatalog och artistTerm har alla provats'
      from klara
    on conflict (id) do nothing
    returning id
  )
  delete from public.track_pool tp where tp.id in (select id from flytt);

  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- --- 3. steg 3 kollar att svaret gäller RÄTT artist ---------------------
create or replace function public._artist_probe_collect()
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n       int := 0;
  p         record;
  v_status  int;
  v_timed   boolean;
  v_body    text;
  v_json    jsonb;
  v_cands   bigint[];
  v_req     bigint;
  v_found   int;
  v_namn    text;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
begin
  for p in select * from public.artist_probe where stage in (1, 2, 3) loop
    select status_code, timed_out, content into v_status, v_timed, v_body
      from net._http_response where id = p.request_id;
    if not found then
      continue;
    end if;

    if coalesce(v_status, 0) <> 200 or coalesce(v_timed, false) then
      update public.artist_probe set stage = 0, request_id = null
       where artist_key = p.artist_key and sv = p.sv;
      v_n := v_n + 1;
      continue;
    end if;

    select min(tp.artist) into v_namn from public.track_pool tp
     where tp.preview_url is null and tp.sv = p.sv
       and public._artist_key(tp.artist) = p.artist_key;

    -- ---- steg 1: välj artist-id ------------------------------------
    if p.stage = 1 then
      begin
        v_json := v_body::jsonb;
      exception when others then
        v_json := null;
      end;

      select array_agg(x.aid order by x.rang, x.ord) into v_cands
      from (
        select (r ->> 'artistId')::bigint as aid,
               row_number() over () as ord,
               case when public._norm_title(r ->> 'artistName') = p.artist_key then 0
                    when public._norm_title(r ->> 'artistName') like p.artist_key || ' %' then 1
                    else 2 end as rang
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'artistId', '') <> ''
          and (public._norm_title(r ->> 'artistName') = p.artist_key
               or public._norm_title(r ->> 'artistName') like p.artist_key || ' %')
        limit 3
      ) x;

      if v_cands is null or array_length(v_cands, 1) is null then
        v_req := net.http_get(url := public._itunes_artist_term_url(coalesce(v_namn, p.artist_key)),
                              timeout_milliseconds := 6000);
        update public.artist_probe
           set stage = 3, request_id = v_req, requested_at = now(), probed_at = now()
         where artist_key = p.artist_key and sv = p.sv;
        v_n := v_n + 1;
        continue;
      end if;

      v_req := net.http_get(url := public._itunes_catalog_url(v_cands[1]),
                            timeout_milliseconds := 6000);
      update public.artist_probe
         set stage = 2, request_id = v_req, cand_ids = v_cands, cand_ix = 1,
             requested_at = now()
       where artist_key = p.artist_key and sv = p.sv;
      v_n := v_n + 1;
      continue;
    end if;

    -- ---- steg 2 och 3: matcha ---------------------------------------
    --  Skillnaden mot 0072: skräpordet i titeln flyttat från WHERE till
    --  ORDER BY. En ren titel vinner, en "(Live)"-variant duger i nödfall.
    with kat as (
      select distinct on (public._norm_title(public._clean_title(trackname)))
             public._norm_title(public._clean_title(trackname)) as ntitel,
             previewurl, track_id
      from public._itunes_rows(v_body)
      where lower(collectionname) !~ v_junk_cn
        and public._norm_title(public._clean_title(trackname)) <> ''
        -- Steg 3 är en SÖKNING över artister och kan svara med en namne.
        -- Steg 2 är en katalog och behöver inte villkoret: artist-id:t är
        -- redan namnkontrollerat i steg 1, och Apples stavning av artisten
        -- behöver inte vara pottens.
        and (p.stage = 2 or public._artist_key(artistname) = p.artist_key)
      order by public._norm_title(public._clean_title(trackname)),
               (lower(trackname) ~ v_junk_tn),   -- false före true
               length(trackname)
    )
    update public.track_pool tp
       set preview_url        = k.previewurl,
           itunes_track_id    = k.track_id,
           preview_source     = 'catalog',
           preview_checked_at = now()
      from kat k
     where tp.preview_url is null
       and tp.sv = p.sv
       and public._artist_key(tp.artist) = p.artist_key
       and public._norm_title(public._clean_title(tp.title)) = k.ntitel;
    get diagnostics v_found = row_count;

    if p.stage = 2 then
      if v_found = 0 and p.cand_ix < coalesce(array_length(p.cand_ids, 1), 0) then
        v_req := net.http_get(url := public._itunes_catalog_url(p.cand_ids[p.cand_ix + 1]),
                              timeout_milliseconds := 6000);
        update public.artist_probe
           set request_id = v_req, cand_ix = p.cand_ix + 1, requested_at = now()
         where artist_key = p.artist_key and sv = p.sv;
      else
        if exists (select 1 from public.track_pool tp
                    where tp.preview_url is null and tp.sv = p.sv
                      and public._artist_key(tp.artist) = p.artist_key) then
          v_req := net.http_get(url := public._itunes_artist_term_url(coalesce(v_namn, p.artist_key)),
                                timeout_milliseconds := 6000);
          update public.artist_probe
             set stage = 3, request_id = v_req, requested_at = now(),
                 probed_at = now(), found = artist_probe.found + v_found
           where artist_key = p.artist_key and sv = p.sv;
        else
          update public.artist_probe
             set stage = 0, request_id = null, probed_at = now(),
                 term_probed_at = now(), found = artist_probe.found + v_found
           where artist_key = p.artist_key and sv = p.sv;
        end if;
      end if;
    else
      update public.artist_probe
         set stage = 0, request_id = null, probed_at = coalesce(probed_at, now()),
             term_probed_at = now(), found = artist_probe.found + v_found
       where artist_key = p.artist_key and sv = p.sv;
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

notify pgrst, 'reload schema';
