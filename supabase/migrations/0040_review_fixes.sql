-- ====================================================================
--  0040  Tre småfixar efter genomgången av 24 juli
-- --------------------------------------------------------------------
--  1. ORDGRÄNSER I SKRÄPORDSFILTRET (poll_track_start)
--     Filtret som sållar bort remixer/karaoke matchade mitt inne i ord:
--     "cover" träffade "Uncover" (Zara Larsson) och "Discover". Bara
--     \mlive\M hade ordgränser; nu har hela alternativlistan det.
--
--     OBS vad detta INTE löser: titlar där skräpordet är ett riktigt ord
--     ("Run For Cover", "Cover Me In Sunshine", "Live Forever") matchar
--     fortfarande. De hänger kvar på undantaget x.tn = v_clean, dvs. att
--     iTunes-titeln är exakt lika med den rensade pott-titeln. Så är det
--     designat – alternativet vore att sluta filtrera på de orden alls.
--
--  2. reset_game NOLLSTÄLLDE INTE VINNARLISTAN
--     winner_unit_ids och winner_round_id låg kvar från förra partiet.
--     Osynligt i UI:t (WinBanner kräver status = 'finished') men det är
--     gammal state som ligger och väntar på att någon läser den.
--
--  3. DÖD ÖVERLAGRING gen_bingo_grid()
--     Noll-argumentvarianten ersattes av gen_bingo_grid(text[]) i 0031 och
--     anropas inte längre. Två överlagringar med samma namn är precis det
--     som gav PGRST203-strulet i 0013 – bort med den.
--
--  Funktionerna nedan är hämtade ordagrant ur live-databasen och har fått
--  exakt de ändringar som beskrivs ovan. Ingen övrig logik är rörd.
-- ====================================================================

-- ====================================================================
--  1. Skräpordsfiltret får ordgränser
-- ====================================================================
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
  v_req    bigint;
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
        and x.cn !~ v_junk_cn
        and (x.tn = v_clean or x.tn !~ v_junk_tn)
      order by
        (case when x.tn = v_clean then 0 when x.tn like v_clean || '%' then 1 else 2 end),
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

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

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
end $function$
;

-- ====================================================================
--  2. reset_game nollställer hela vinnar-staten
-- ====================================================================
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
  update public.bingo_cards
    set grid = public.gen_bingo_grid(public._room_categories(v_room.year_min, v_room.year_max)),
        has_won = false
    where room_id = p_room_id;
  update public.rooms
    set winner_player_id = null, winner_team_id = null,
        winner_unit_ids = '[]'::jsonb, winner_round_id = null,
        status = case when p_back_to_lobby then 'lobby' else 'playing' end
    where id = p_room_id;
end $function$
;

-- ====================================================================
--  3. Bort med den döda överlagringen
-- ====================================================================
drop function if exists public.gen_bingo_grid();
