-- =====================================================================
--  LÅTSNURRAN – Kom ihåg vilka låtar som INTE går att hitta
--
--  MÄTNING (50 slumpade låtar ur svenska potten, serverns egen strikta
--  matchning, skarpa iTunes-svar):
--
--      limit=8    missar 15/50 = 30 %
--      limit=15   missar 15/50 = 30 %
--      limit=25   missar 15/50 = 30 %
--
--  Identiskt. Antalet träffar spelar ingen roll – för de låtarna finns rätt
--  titel inte i svaret ÖVER HUVUD TAGET. Att höja limit igen skulle alltså
--  inte hjälpa (och det var limit-höjningen som orsakade timeout-haveriet i
--  0062). Sveriges topplistearkiv innehåller mycket som aldrig nått iTunes
--  SE, särskilt äldre och smalare spår.
--
--  KONSEKVENSEN AV 30 % är inte främst misslyckade rundor (tre försök ger
--  2,7 %) utan VÄNTAN: varje omöjlig låt kostar två sökningar innan servern
--  går vidare, så en runda som lyckas på tredje försöket tar flera sekunder
--  extra. Det är precis det som märks som "tar extra lång tid".
--
--  ROTEN TILL PROBLEMET: potten glömmer. Samma omöjliga låt dras om och om
--  igen, kväll efter kväll, och kostar två anrop varje gång.
--
--  ÅTGÄRD. 0066 lade in cachen för lyckade uppslag; nu kommer även de
--  MISSLYCKADE ihåg. Ger stage 2 ett giltigt svar utan match markeras låten
--  som ohittbar (preview_checked_at satt, preview_url null) och hoppas över
--  i urvalet i 7 dagar. Dödvikten filtreras alltså bort av spelandet självt:
--
--    kväll 1  ~30 % av dragningarna kostar två bomanrop
--    kväll 2  de flesta av dem är redan bortsorterade
--
--  TTL:n finns för att en miss kan bero på Apple, inte på låten – efter 7
--  dagar provas den igen. Transportfel markerar ALDRIG (0066 hanterar dem
--  separat); annars hade ett 403-regn svartlistat halva potten.
--
--  Dessutom: attempts_left 3 → 4. Med 30 % ohittbara sjunker risken att en
--  runda misslyckas från 2,7 % till 0,8 %, och kostnaden faller ändå i takt
--  med att de ohittbara sorteras bort.
--
--  Additiv + idempotent. Kör efter 0066.
-- =====================================================================

-- Snabb uppslagning i urvalet (delvis index – bara de markerade raderna).
create index if not exists track_pool_unfindable_idx
  on public.track_pool (preview_checked_at)
  where preview_url is null;

-- --- 1. urvalet hoppar över kända omöjliga låtar ----------------------
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

  -- Cacheträff: starta direkt, utan att fråga iTunes.
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
    return;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 6000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 4, 1);
end $function$;

-- --- 2. poll: markera ohittbara, hoppa över dem i omtagen -------------
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

    update public.track_pool
      set preview_url = v_hit ->> 'previewUrl', preview_checked_at = now()
      where id = v_track.id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  -- Transportfel: låten är oskyldig, markera den INTE. Gör om samma sökning
  -- en gång och ge sedan upp direkt.
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

  -- Giltigt svar utan match på den rensade titeln: bredda till råtiteln.
  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2, net_retries = 0 where room_id = p_room_id;
    return null;
  end if;

  -- Båda sökningarna gav giltiga svar utan match: låten går inte att hitta.
  -- Markera den så att urvalet slipper dra den igen den närmaste veckan.
  update public.track_pool
    set preview_url = null, preview_checked_at = now()
    where id = v_p.pool_id;

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

  -- Nästa låt kan redan vara cachad – då startar rundan direkt utan anrop.
  if v_track.preview_url is not null
     and v_track.preview_checked_at > now() - interval '30 days' then
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

grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
