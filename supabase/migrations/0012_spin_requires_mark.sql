-- =====================================================================
--  HITSTER BINGO ONLINE – Kryssa innan du snurrar igen
--
--  Om förra rundan avslöjats och någon som svarade RÄTT ännu inte kryssat
--  sitt kryss, ska värden inte kunna snurra vidare (då skulle krysset gå
--  förlorat). Spärren gäller bara den som FAKTISKT kan kryssa: har enheten
--  ingen ledig ruta i rundans kategori blockerar den inte (undviker dödläge).
--
--  Additiv + idempotent. Kör efter 0011.
-- =====================================================================

create or replace function public.spin_wheel(p_room_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_prev  public.rounds;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats constant text[] := array['decade', 'artist', 'exact_year', 'approx_year', 'title'];
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan snurra'; end if;

  -- SPÄRR: lämna inte en avslöjad runda medan någon rätt-svarande ännu inte
  -- kryssat (och har en ledig ruta i kategorin att kryssa).
  select * into v_prev from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_prev.id is not null and v_prev.current_track_id is not null and v_prev.answers_revealed then
    if exists (
      select 1
      from public.round_answers ra
      join public.bingo_cards bc
        on bc.room_id = p_room_id
       and (
         (v_room.team_mode and bc.team_id = ra.team_id)
         or (not v_room.team_mode and bc.player_id = ra.player_id)
       )
      where ra.round_id = v_prev.id
        and coalesce(ra.override_correct, ra.auto_correct) is true
        and coalesce(ra.has_marked, false) = false
        and exists (
          select 1 from jsonb_array_elements(bc.grid) cell
          where cell ->> 'category' = v_prev.category
            and (cell ->> 'filled')::boolean = false
        )
    ) then
      raise exception 'Alla som hade rätt måste kryssa innan du snurrar igen';
    end if;
  end if;

  v_cat := cats[floor(random() * 5)::int + 1];
  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  insert into public.rounds (room_id, round_number, category, spun_by, state, timer_start_at)
  values (p_room_id, v_num, v_cat, v_uid, 'playing', now() + interval '4.2 seconds')
  returning * into v_round;

  update public.rooms set status = 'playing'
    where id = p_room_id and status <> 'finished';
  return v_round;
end;
$$;

notify pgrst, 'reload schema';
