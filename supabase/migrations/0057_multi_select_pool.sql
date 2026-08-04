-- ====================================================================
--  0057  Multival i lobbyn: flera åldersspann och genrer samtidigt
-- --------------------------------------------------------------------
--  Tidigare kunde rummet bara stå på EN pottkategori: ett åldersspann
--  ELLER en genre, plus en kryssruta för svenskt. Nu väljs fritt – t.ex.
--  "Svenska + 20–29 år + 30–39 år + Pop".
--
--  SEMANTIK: union inom en dimension, snitt mellan dimensioner.
--  Två åldersspann = låtar ur endera. Åldersspann + genre = låtar som är
--  BÅDA. Tom dimension = inget filter på den dimensionen.
--
--  SPRÅKET BYTER INNEBÖRD. Förut var filtret `tp.sv = swedish_mode`, en
--  LIKHET: med rutan ur fick man bara ICKE-svenska låtar, så de 4 159
--  svenska var oåtkomliga i normalspel trots att de utgör 43 % av potten.
--  Nu är svenska en vanlig chip: vald = bara svenska, ovald = ingen
--  språkgräns (allt). Det är vad etiketten alltid har lovat.
--
--  ETT FILTER, ETT STÄLLE. Villkoret låg tidigare kopierat i fyra
--  funktioner, och 0055 varnade själv för att de måste hållas i synk. De
--  gjorde det inte: poll_track_start (senast rörd i 0040) saknade
--  genrefiltret helt, eftersom genren kom i 0043 som bara ändrade
--  start_random_track. Valde man Pop och första låtens ljudklipp inte gick
--  att hitta, plockade ersättningsvalet ur HELA potten. Nu delar alla
--  _pool_match() och kan inte glida isär igen.
--
--  Funktionskropparna nedan är kopierade ordagrant ur sina senaste
--  versioner (start_random_track ur 0043, poll_track_start ur 0040) med
--  enbart WHERE-villkoret utbytt – så ingen tidigare fix tappas.
--
--  Additiv + idempotent. Kör efter 0056.
-- ====================================================================

-- --- 1. kolumnerna ---
alter table public.rooms
  add column if not exists year_bands jsonb not null default '[]'::jsonb,
  add column if not exists genres     jsonb not null default '[]'::jsonb;

-- Flytta över befintliga enkelval så pågående rum behåller sin pott.
update public.rooms
   set year_bands = jsonb_build_array(
         jsonb_build_object('min', year_min, 'max', year_max))
 where year_bands = '[]'::jsonb and (year_min is not null or year_max is not null);

update public.rooms
   set genres = jsonb_build_array(genre)
 where genres = '[]'::jsonb and genre is not null;

-- Värden skriver dem direkt (RLS rooms_update_host begränsar till egna rum).
grant update (year_bands, genres) on public.rooms to authenticated;

-- --- 2. filtret, på ETT ställe ---
create or replace function public._pool_match(
  p_track   public.track_pool,
  p_swedish boolean,
  p_bands   jsonb,
  p_genres  jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    -- svenska: vald = bara svenska, ovald = ingen språkgräns
    (not coalesce(p_swedish, false) or p_track.sv)
    -- åldersspann: union, tom lista = ingen gräns
    and (coalesce(jsonb_array_length(p_bands), 0) = 0 or exists (
          select 1 from jsonb_array_elements(p_bands) b
           where (b ->> 'min' is null or p_track.year >= (b ->> 'min')::int)
             and (b ->> 'max' is null or p_track.year <= (b ->> 'max')::int)))
    -- genrer: union, tom lista = ingen gräns
    and (coalesce(jsonb_array_length(p_genres), 0) = 0
         or public._genre_key(p_track.genre) in (
              select jsonb_array_elements_text(p_genres)))
$$;

-- --- 2b. year_min/year_max lever kvar som HÄRLETT spann ---
-- De används inte längre för att filtrera potten (det gör _pool_match), men
-- _room_categories() läser dem för att avgöra om rummet är i ÅLDERSLÄGE, dvs
-- vilket hjul och vilka brickkategorier som gäller. Den funktionen anropas
-- från fyra ställen i 0031/0032/0040; att skriva om dem alla vore onödig
-- risk. Triggern håller i stället spannet i synk med bandvalet.
--
-- Spannet är bandens ytterkanter: saknar något band undre (eller övre) gräns
-- blir motsvarande kant null, annars min av min och max av max.
--
-- Röres INTE när year_bands står stilla, så en äldre klient som fortfarande
-- skriver year_min/year_max direkt fungerar oförändrat under utrullningen.
create or replace function public._sync_year_envelope()
returns trigger language plpgsql set search_path = public as $function$
begin
  if tg_op = 'UPDATE' and new.year_bands is not distinct from old.year_bands then
    return new;
  end if;
  if coalesce(jsonb_array_length(new.year_bands), 0) = 0 then
    new.year_min := null;
    new.year_max := null;
  else
    select case when bool_or(b ->> 'min' is null) then null else min((b ->> 'min')::int) end,
           case when bool_or(b ->> 'max' is null) then null else max((b ->> 'max')::int) end
      into new.year_min, new.year_max
      from jsonb_array_elements(new.year_bands) b;
  end if;
  return new;
end;
$function$;

drop trigger if exists rooms_sync_year_envelope on public.rooms;
create trigger rooms_sync_year_envelope
  before insert or update on public.rooms
  for each row execute function public._sync_year_envelope();

-- --- 3. låtväljarna ---
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

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 3, 1);
end $function$;

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

-- --- 4. räknaren i lobbyn ---
-- Den gamla signaturen (year_min, year_max, genre) måste BORT, inte bara
-- ersättas: en ny signatur skapar annars en överlagring och PostgREST ser
-- två funktioner med samma namn.
drop function if exists public.track_pool_selection_count(boolean, int, int, text);

create or replace function public.track_pool_selection_count(
  p_swedish boolean default false,
  p_bands   jsonb   default '[]'::jsonb,
  p_genres  jsonb   default '[]'::jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $function$
declare
  v_antal bigint;
begin
  perform public._rate_limit('pool_selection_count', 60, interval '1 minute');
  select count(*) into v_antal from public.track_pool tp
   where public._pool_match(tp, p_swedish, p_bands, p_genres);
  return v_antal;
end;
$function$;

-- --- 5. de breda räknarna ---
-- "all" räknade tidigare `where not sv`, vilket stämde när svenskt läge var
-- ett exklusivt val. Nu betyder "Alla låtar" allt, svenskt inkluderat.
create or replace function public.track_pool_counts()
returns jsonb
language plpgsql security definer set search_path = public
as $function$
declare
  v_counts jsonb;
begin
  perform public._rate_limit('pool_counts', 20, interval '1 minute');
  select jsonb_build_object('all', count(*),
                            'sv',  count(*) filter (where sv))
    into v_counts
  from public.track_pool;
  return v_counts;
end;
$function$;

grant execute on function public._pool_match(public.track_pool, boolean, jsonb, jsonb) to anon, authenticated;
grant execute on function public.track_pool_selection_count(boolean, jsonb, jsonb) to authenticated;
grant execute on function public.track_pool_counts() to authenticated;
grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
