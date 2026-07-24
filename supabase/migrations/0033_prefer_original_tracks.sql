-- =====================================================================
--  LÅTSNURRAN – Föredra originalinspelningar (bort från remixer/karaoke)
--
--  poll_track_start tog FÖRSTA iTunes-träffen med rätt artist + preview, utan
--  att skilja original från remix/karaoke/cover/live/instrumental. Följd: t.ex.
--  "Happier" (Marshmello) kunde bli en remix trots att originalet fanns i
--  träfflistan.
--
--  Nu RANKAS träffarna (mjuk nedprioritering via ORDER BY, inte hård
--  uteslutning – så en låt som *heter* något med t.ex. "live" fortfarande kan
--  väljas om den är enda träffen):
--    1. straffa remix/karaoke/cover/tribute/instrumental/acoustic/live/nightcore/
--       "made famous by"/"originally performed"/8-bit/lullaby ... (i track- och
--       albumnamn),
--    2. föredra exakt titelmatch (annars prefix), sedan
--    3. kortast trackName (färre suffix som "(... Version)").
--  Först artist-matchande träffar, därefter valfri (som tidigare fallback).
--
--  Bara matchningen ändras – årsfilter, rate-limit och facit-hantering är
--  identiska med 0030. Additiv + idempotent. Kör efter 0032 (ordningen spelar
--  ingen roll mot 0031/0032, men efter 0030 som den bygger på).
-- =====================================================================

create or replace function public.poll_track_start(p_room_id uuid)
returns public.rounds
language plpgsql security definer set search_path = public
as $$
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
  v_req    bigint;
  -- Markörer för icke-original (nedprioriteras, inte utesluts). Mjuk matchning
  -- ⇒ ofarligt att vara bred: en låt vars egen titel råkar innehålla ett ord
  -- straffas bara relativt, och plockas ändå om inget renare finns.
  v_junk_tn constant text :=
    '(remix|karaoke|cover|tribute|instrumental|acoustic|\mlive\M|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)';
  v_junk_cn constant text :=
    '(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)';
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
      v_word  := lower(split_part(coalesce(v_track.artist, ''), ' ', 1));
      v_clean := lower(public._clean_title(v_track.title));

      -- Pass 1: artist matchar → ranka original först.
      select x.r into v_hit
      from (
        select r,
               lower(coalesce(r ->> 'trackName', ''))      as tn,
               lower(coalesce(r ->> 'collectionName', '')) as cn,
               lower(coalesce(r ->> 'artistName', ''))     as an
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'previewUrl', '') like 'https://%'
      ) x
      where x.an like '%' || v_word || '%'
      order by
        (case when x.tn ~ v_junk_tn or x.cn ~ v_junk_cn then 1 else 0 end),
        (case when x.tn = v_clean then 0 when x.tn like v_clean || '%' then 1 else 2 end),
        length(x.tn)
      limit 1;

      -- Pass 2 (fallback): valfri artist, men fortfarande original + rätt titel först.
      if v_hit is null then
        select x.r into v_hit
        from (
          select r,
                 lower(coalesce(r ->> 'trackName', ''))      as tn,
                 lower(coalesce(r ->> 'collectionName', '')) as cn,
                 lower(coalesce(r ->> 'artistName', ''))     as an
          from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
          where coalesce(r ->> 'previewUrl', '') like 'https://%'
        ) x
        order by
          (case when x.tn ~ v_junk_tn or x.cn ~ v_junk_cn then 1 else 0 end),
          (case when x.an like '%' || v_word || '%' then 0 else 1 end),
          (case when x.tn = v_clean then 0 when x.tn like v_clean || '%' then 1 else 2 end),
          length(x.tn)
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

  -- Ny låt: samma pott-filter (sv + årsfönster), undvik repriser + samma id.
  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and (v_room.year_min is null or tp.year >= v_room.year_min)
      and (v_room.year_max is null or tp.year <= v_room.year_max)
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
end $$;

grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
