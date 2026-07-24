-- =====================================================================
--  LÅTSNURRAN – Åldersgrupp / era (årsfönster på låtpotten)
--
--  Ny rums-inställning: ett valfritt årsfönster (year_min/year_max) som
--  begränsar vilka låtar servern slumpar. Används för åldersriktade
--  kategorier i lobbyn ("20–29 år", "30–39 år" …) som bygger på
--  reminiscensbågen: varje grupp mappas till eran då den var ung
--  (se src/lib/constants.js → AGE_GROUPS). null/null = hela potten.
--
--  Potten är oläsbar för klienter (RLS utan policy), så filtret MÅSTE ligga
--  server-side. Vi återskapar start_random_track + poll_track_start från 0024
--  med två extra villkor i varje pott-SELECT:
--    and (v_room.year_min is null or tp.year >= v_room.year_min)
--    and (v_room.year_max is null or tp.year <= v_room.year_max)
--
--  Värden sätter fönstret direkt (RLS rooms_update_host). Additiv + idempotent.
--  Kör efter 0025.
-- =====================================================================

alter table public.rooms
  add column if not exists year_min int,
  add column if not exists year_max int;

-- ====================================================================
--  Steg 1: värden begär en slumpad låt (nu med årsfönster)
-- ====================================================================
create or replace function public.start_random_track(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_track public.track_pool;
  v_req   bigint;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;
  if v_round.current_track_id is not null then raise exception 'Rundan har redan en låt'; end if;

  -- Kasta ev. gammal påbörjad uppslagning (t.ex. efter avbruten polling).
  delete from public.pending_tracks where room_id = p_room_id;

  -- Slumpa en låt ur rätt pott (sv + årsfönster), undvik repriser i rummet.
  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and (v_room.year_min is null or tp.year >= v_room.year_min)
      and (v_room.year_max is null or tp.year <= v_room.year_max)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    -- Hela (filtrerade) potten spelad i rummet → tillåt repriser inom fönstret.
    select tp.* into v_track from public.track_pool tp
      where tp.sv = v_room.swedish_mode
        and (v_room.year_min is null or tp.year >= v_room.year_min)
        and (v_room.year_max is null or tp.year <= v_room.year_max)
      order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 5, 1);
end $$;

-- ====================================================================
--  Steg 2: värdens klient pollar tills servern satt låten (årsfönster
--  gäller även när en annan låt måste väljas vid utebliven iTunes-träff)
-- ====================================================================
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
  v_req    bigint;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  select * into v_p from public.pending_tracks where room_id = p_room_id;
  if v_p.room_id is null then
    -- Ingen pågående uppslagning: redan klart om rundan fått sin låt.
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  -- Uppslag som hör till en gammal runda: kasta det.
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
      -- Föredra träff där artistnamnet matchar (första ordet, som previewApi.js).
      v_word := lower(split_part(coalesce(v_track.artist, ''), ' ', 1));
      select r into v_hit
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'previewUrl', '') like 'https://%'
          and lower(coalesce(r ->> 'artistName', '')) like '%' || v_word || '%'
        limit 1;
      if v_hit is null then
        select r into v_hit
          from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
          where coalesce(r ->> 'previewUrl', '') like 'https://%'
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

-- Behörigheter (create or replace behåller grants, men explicit sedan 0023).
grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
