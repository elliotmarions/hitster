-- =====================================================================
--  0042  Lås in svaret medan låten spelar
-- ---------------------------------------------------------------------
--  Tidigare vägrade lock_answer allt som kom in före
--  `timer_start_at + 24s` – man fick skriva under klippet men inte låsa
--  förrän det tystnat. Nu får man låsa in när som helst under
--  uppspelningen, och när ALLA enheter låst avslöjas svaren direkt
--  (samma villkor som förut: v_locked >= v_total). Klienten tystar
--  låten så fort rundan får answers_revealed = true, så en runda där
--  alla är snabba är över på ett par sekunder.
--
--  ENDA kvarvarande tidsspärren: låten måste ha börjat spela. Utan den
--  skulle en modifierad klient kunna låsa in under 3-2-1-nedräkningen
--  och därmed avslöja facit innan någon hört ett ton. En sekunds
--  marginal mot klientklockornas drift.
--
--  Allt annat är oförändrat från 0028 – radlåset (`for update`) på
--  rundan är det som gör att sex samtidiga inlåsningar räknas rätt, och
--  det behövs mer än någonsin nu när knappen är öppen hela klippet.
--
--  Idempotent. Kör efter 0041.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.lock_answer(p_room_id uuid, p_answer text)
 RETURNS round_answers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid      uuid := auth.uid();
  v_room     public.rooms;
  v_player   public.players;
  v_round    public.rounds;
  v_ans      public.round_answers;
  v_locked   int;
  v_total    int;
  v_revealed boolean;
begin
  perform public._rate_limit('answer', 30, interval '1 minute');
  if length(coalesce(p_answer, '')) > 300 then
    raise exception 'Svaret är för långt (max 300 tecken)';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  -- FOR UPDATE: serialiserar samtidiga inlåsningar på samma runda. Utan det
  -- läser var och en sitt eget (föråldrade) antal inlåsta svar och den som
  -- skriver sist vinner → locked_count blir för lågt och answers_revealed
  -- sätts aldrig, dvs rundan låser sig när flera trycker "Lås in" samtidigt.
  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1
    for update;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;
  if v_round.current_track_id is null or v_round.timer_start_at is null then
    raise exception 'Ingen låt har spelats än';
  end if;
  -- Låten måste ha börjat (se huvudkommentaren) – men den behöver INTE ha
  -- spelat klart. Marginalen täcker klientklockor som går någon tiondel före.
  if now() < v_round.timer_start_at - interval '1 second' then
    raise exception 'Vänta tills låten börjat spela';
  end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    select * into v_ans from public.round_answers
      where round_id = v_round.id and team_id = v_player.team_id;
    if v_ans.id is null then
      insert into public.round_answers (room_id, round_id, team_id, user_id, answer, locked)
      values (p_room_id, v_round.id, v_player.team_id, v_uid, coalesce(p_answer, ''), true)
      returning * into v_ans;
    elsif not v_ans.locked then
      update public.round_answers set answer = coalesce(p_answer, ''), locked = true, updated_at = now()
        where id = v_ans.id returning * into v_ans;
    end if;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.teams where room_id = p_room_id;
  else
    insert into public.round_answers (room_id, round_id, player_id, user_id, answer, locked)
    values (p_room_id, v_round.id, v_player.id, v_uid, coalesce(p_answer, ''), true)
    on conflict (round_id, player_id) do update
      set answer = case when public.round_answers.locked then public.round_answers.answer
                        else excluded.answer end,
          locked = true, updated_at = now()
    returning * into v_ans;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.players where room_id = p_room_id;
  end if;

  update public.rounds
    set locked_count = v_locked,
        locked_units = coalesce((
          select jsonb_agg(u) from (
            select case when v_room.team_mode then ra.team_id else ra.player_id end as u
            from public.round_answers ra
            where ra.round_id = v_round.id and ra.locked
          ) s
        ), '[]'::jsonb),
        answers_revealed = (v_locked >= v_total)
    where id = v_round.id
    returning answers_revealed into v_revealed;

  if v_revealed then
    perform public._grade_round(v_round.id);
  end if;

  return v_ans;
end;
$function$
;

grant execute on function public.lock_answer(uuid, text) to authenticated;

notify pgrst, 'reload schema';
