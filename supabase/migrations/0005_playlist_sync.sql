-- =====================================================================
--  HITSTER BINGO ONLINE – Fas 4: synkad uppspelning (separat "Starta låt")
--
--  Flöde: värden SNURRAR (spin_wheel → kategori, oförändrad sedan 0003).
--  När alla är redo trycker värden STARTA LÅT → start_track sätter en (slumpad)
--  låt + start_at (timer_start_at) på senaste rundan. Alla klienter startar då
--  samma låt synkat vid start_at, kör 25s-timern och pausar automatiskt.
--
--  Additiv migration (rör inte spin_wheel) → helt säker för live-sidan.
--  Kör efter 0004.
-- =====================================================================

create or replace function public.start_track(
  p_room_id uuid,
  p_track_uri text,
  p_track_meta jsonb
)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  -- Senaste rundan (den värden nyss snurrade).
  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;

  update public.rounds
    set current_track_id = p_track_uri,
        current_track_meta = p_track_meta,
        state = 'playing',
        -- start_at: 3 s fram i tiden så alla klienter hinner starta synkat.
        timer_start_at = now() + interval '3 seconds'
    where id = v_round.id
    returning * into v_round;

  return v_round;
end;
$$;

grant execute on function public.start_track(uuid, text, jsonb) to authenticated;
