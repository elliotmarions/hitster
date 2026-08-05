-- =====================================================================
--  LÅTSNURRAN – Suddregeln gäller alla årtalskategorier
--
--  Sudd var låst till 'exact_year' sedan 0002. Regeln fanns för att belöna
--  den som prickar ett ÅRTAL, men spelet har fått fler sätt att göra just
--  det sedan dess: 'approx_year' (±3) i normalläget och 'approx_year_1'
--  (±1) i åldersläget. Rätt gissning där gav ingen sudd-rätt, vilket är
--  godtyckligt – det är samma sorts svar, med en annan tolerans.
--
--  Nu: sudd på alla tre.
--
--  AVGRÄNSNING – två årsnära kategorier ingår MEDVETET inte:
--    'decade'       svaret är ett decennium, inte ett årtal.
--    'before_after' man väljer sida, inte år. En ren gissning träffar rätt
--                   varannan gång, och sudd på femtio procents odds är en
--                   annan regel än den här – inte en tolerans till.
--
--  Övriga spärrar är oförändrade: suddregeln måste vara påslagen i rummet,
--  svaren avslöjade, det egna svaret rätt, och målbrickan får inte vara ens
--  egen (eller det egna lagets).
--
--  Klienten speglar listan i ERASE_CATEGORIES (src/lib/constants.js).
--  Additiv + idempotent. Kör efter 0062.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_card   public.bingo_cards;
  v_myans  public.round_answers;
  v_grid   jsonb;
  -- Kategorier där svaret ÄR ett årtal. Se avgränsningen i huvudet.
  v_year_cats constant text[] := array['exact_year', 'approx_year', 'approx_year_1'];
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if not coalesce(v_room.erase_rule_enabled, false) then
    raise exception 'Suddregeln är avstängd';
  end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null or not (v_round.category = any(v_year_cats)) then
    raise exception 'Sudd tillåts bara när kategorin är ett årtal';
  end if;

  -- SPÄRR: sudd kräver att din egen enhet gissat rätt (avslöjat + rätt).
  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan du suddar';
  end if;
  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;
  if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
    raise exception 'Bara rätt svar får sudda';
  end if;

  select * into v_card from public.bingo_cards where id = p_target_card and room_id = p_room_id;
  if v_card.id is null then raise exception 'Brickan finns inte'; end if;
  if v_room.team_mode then
    if v_card.team_id = v_player.team_id then raise exception 'Du kan inte sudda på ditt eget lags bricka'; end if;
  else
    if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$function$;

grant execute on function public.erase_cross(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
