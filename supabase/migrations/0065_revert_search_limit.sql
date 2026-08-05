-- =====================================================================
--  LÅTSNURRAN – Tillbaka till 8 iTunes-träffar + ärligare felmeddelande
--
--  SYMTOM efter 0062: "Hittade ingen spelbar låt just nu" på VARJE låtstart,
--  inte på enstaka låtar.
--
--  Det utesluter titelkravet som orsak. Mätt mot skarpa iTunes-svar med
--  serverns egen urvalslogik missar det strängare filtret 18 % av låtarna
--  mot tidigare 13 % – med tre försök per runda blir det 0,5 % misslyckade
--  rundor, inte 100 %. Ett fel som slår ut allt samtidigt sitter inte i en
--  matchning som bevisligen matchar.
--
--  Kvar av 0062 finns då bara ÅTGÄRD 3: limit 8 → 25 i sök-URL:en. Den
--  tredubblar svaret (mätt: 7,8 kB → 20,7 kB i snitt, upp till 39 kB) medan
--  timeouten stod kvar på 4000 ms. Överskrids den sätter pg_net timed_out,
--  poll_track_start ser inget 200-svar, och alla tre försöken faller –
--  exakt det observerade beteendet, oberoende av vilken låt som dragits.
--
--  Alltså: limit tillbaka till 8. Det återställer nätverksprofilen till den
--  som bevisligen fungerade före 0062, och behåller den faktiska buggfixen
--  (titeln måste matcha). Priset är att rätt titel oftare saknas bland
--  träffarna – vilket ger en överhoppad låt, inte fel facit.
--
--  DIAGNOS: felmeddelandet skilde inte på "iTunes svarade inte" och "hittade
--  ingen match". Det är därför symtomet ovan gick att tolka på två sätt. Nu
--  säger texten vilket det var, med statuskoden. Ingen schemaändring – bara
--  variabler som redan fanns i funktionen.
--
--  Additiv + idempotent. Kör efter 0064.
-- =====================================================================

-- limit 25 → 8 igen (samma URL som före 0062).
create or replace function public._itunes_search_url(p_term text)
returns text language sql immutable as $$
  select 'https://itunes.apple.com/search?media=music&entity=song&limit=8&country=SE&term='
         || public._urlencode(p_term)
$$;

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
    -- Skilj på "musiktjänsten svarade inte" och "svaret innehöll ingen match".
    -- Utan den skillnaden går samma text att tolka som både nätverksfel och
    -- matchningsfel, vilket kostade en felsökningsrunda.
    if coalesce(v_status, 0) <> 200 or coalesce(v_timed, false) then
      raise exception 'Kunde inte nå musiktjänsten just nu (svar: %) – försök igen.',
        case when coalesce(v_timed, false) then 'timeout' else coalesce(v_status, 0)::text end;
    end if;
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
    timeout_milliseconds := 4000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1
    where room_id = p_room_id;
  return null;
end $function$;

grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
