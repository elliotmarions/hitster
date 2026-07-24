-- =====================================================================
--  LÅTSNURRAN – Lugna ner låtförsöken (10 → 3)
--
--  Original är normalfallet – en låt utan spelbart original är ovanligt. 10
--  försök (0035) var i överkant. 3 räcker gott (låten + två till) och håller
--  det snärtigt. Klientens poll-fönster kortas i takt (src/lib/game.js).
--  Bara attempts_left ändras här. Additiv + idempotent. Kör efter 0035.
-- =====================================================================

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
  perform public._rate_limit('track_start', 20, interval '1 minute');
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

  -- attempts_left 3 (var 10): original är normalfallet → 3 räcker gott.
  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 3, 1);
end $$;

grant execute on function public.start_random_track(uuid) to authenticated;

notify pgrst, 'reload schema';
