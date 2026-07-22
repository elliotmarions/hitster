-- =====================================================================
--  LÅTSNURRAN – Samtidighetsfixar (radlås i lock_answer och mark/unmark)
--
--  Hittat av ett 6-spelartest mot live-DB: när flera spelare gör samma sak
--  i samma ögonblick skrev de över varandra. Buggarna är äldre än 0027 –
--  rate limitingen hade inget med dem att göra – men de syns först när man
--  kör spelarna parallellt, och i verkligheten trycker alla "Lås in" ungefär
--  samtidigt (knappen aktiveras för alla när klippet tar slut).
--
--  MÖNSTRET som går fel, i alla tre fallen:
--
--      select ... into v_x from t where ...;   -- läser UTAN lås
--      ... räkna/greta på v_x ...
--      update t set ... where ...;             -- skriver
--
--  Under READ COMMITTED ser varje samtidig transaktion databasen som den såg
--  ut när dess SELECT började. Sex transaktioner kan alltså alla läsa "3 svar
--  inlåsta", och den som råkar skriva sist sätter locked_count = 3 trots att
--  det finns 6 rader. Uppdateringarna serialiseras av radlåset – men läsningen
--  gör det inte, så resultatet byggs på en föråldrad bild.
--
--  MÄTT UTFALL FÖRE FIXEN (6 spelare låser in samtidigt):
--    locked_count = 3 av 6, answers_revealed = false → ingen kan kryssa,
--    rundan står och stampar tills värden trycker "Visa svar nu".
--
--  FIXEN: ta radlåset redan vid läsningen (select ... for update). Då köar
--  transaktionerna, och var och en läser om raden efter att ha fått låset –
--  den sista ser alla sex. Låsordningen blir densamma i alla tre funktionerna
--  (rate_limits → rounds/rooms → resten), så inga deadlocks tillkommer.
--
--  Idempotent. Kör efter 0027.
-- =====================================================================

-- --- lock_answer: lås rundan ---
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
  if now() < v_round.timer_start_at + interval '24 seconds' then
    raise exception 'Vänta tills låten spelat klart innan du låser in svaret';
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

-- --- mark_cross: lås rummet ---
CREATE OR REPLACE FUNCTION public.mark_cross(p_room_id uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_myans  public.round_answers;
  v_grid   jsonb;
  v_won    boolean := false;
  v_label  text;
  v_unit   uuid;
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
  -- FOR UPDATE: vinnarlistan (winner_unit_ids) läses här och skrivs längre
  -- ned. Utan låset kan två enheter som fullbordar sin rad samtidigt läsa
  -- samma "ingen vinnare än" och den sista skriva över den första – oavgjort
  -- (0021) skulle då tappa en medvinnare.
  select * into v_room from public.rooms where id = p_room_id for update;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_player.team_id;
  else
    select * into v_card from public.bingo_cards where room_id = p_room_id and player_id = v_player.id;
  end if;
  if v_card.id is null then raise exception 'Ingen bricka'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  -- SPÄRR (ovillkorlig): kryss kräver att DENNA rundas låt spelats och
  -- avslöjats, att den egna enhetens svar var rätt (auto eller värdens
  -- override) OCH bara ETT kryss per runda. Ingen låt än = inget kryss.
  if v_round.current_track_id is null then
    raise exception 'Starta låten och gissa innan ni kryssar';
  end if;
  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan ni kryssar';
  end if;
  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;
  if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
    raise exception 'Bara rätt svar får kryssa den här rundan';
  end if;
  if coalesce(v_myans.has_marked, false) then
    raise exception 'Ni har redan kryssat en ruta den här rundan';
  end if;

  -- Efter att spelet avgjorts får man bara kryssa i den AVGÖRANDE rundan (för
  -- att hinna bli medvinnare); inte i någon annan.
  if v_room.status = 'finished' and v_room.winner_round_id is distinct from v_round.id then
    raise exception 'Spelet är avgjort';
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Krysset är lagt: markera att enheten förbrukat rundans kryss.
  if v_myans.id is not null then
    update public.round_answers set has_marked = true where id = v_myans.id;
  end if;

  if v_won then
    v_unit := case when v_room.team_mode then v_player.team_id else v_player.id end;

    if v_room.status <> 'finished' then
      -- Första vinsten avgör rundan.
      if v_room.team_mode then
        select name into v_label from public.teams where id = v_unit;
        update public.rooms
          set status = 'finished', winner_round_id = v_round.id,
              winner_unit_ids = jsonb_build_array(v_unit),
              winner_team_id = v_unit, winner_player_id = null
          where id = p_room_id;
        insert into public.room_events (room_id, type, payload)
        values (p_room_id, 'GAME_WIN', jsonb_build_object('team_id', v_unit, 'display_name', v_label));
      else
        update public.rooms
          set status = 'finished', winner_round_id = v_round.id,
              winner_unit_ids = jsonb_build_array(v_unit),
              winner_player_id = v_unit
          where id = p_room_id;
        insert into public.room_events (room_id, type, payload)
        values (p_room_id, 'GAME_WIN', jsonb_build_object('player_id', v_unit, 'display_name', v_player.display_name));
      end if;
    elsif v_room.winner_round_id = v_round.id then
      -- Oavgjort: lägg till som medvinnare (om inte redan med).
      update public.rooms
        set winner_unit_ids = case when winner_unit_ids ? v_unit::text
                                   then winner_unit_ids
                                   else winner_unit_ids || to_jsonb(v_unit) end
        where id = p_room_id;
    end if;
  end if;

  return v_card;
end;
$function$
;

-- --- unmark_cross: lås rummet ---
CREATE OR REPLACE FUNCTION public.unmark_cross(p_room_id uuid, p_cell integer)
 RETURNS bingo_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  v_unit   uuid;
  v_list   jsonb;
begin
  perform public._rate_limit('cross', 60, interval '1 minute');
  -- FOR UPDATE: vinnarlistan (winner_unit_ids) läses här och skrivs längre
  -- ned. Utan låset kan två enheter som fullbordar sin rad samtidigt läsa
  -- samma "ingen vinnare än" och den sista skriva över den första – oavgjort
  -- (0021) skulle då tappa en medvinnare.
  select * into v_room from public.rooms where id = p_room_id for update;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_player.team_id;
  else
    select * into v_card from public.bingo_cards where room_id = p_room_id and player_id = v_player.id;
  end if;
  if v_card.id is null then raise exception 'Ingen bricka'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Bröts enhetens vinstlinje? Ta bort den ur vinnarlistan. Töms listan →
  -- tillbaka till spel; annars uppdatera primär vinnarkolumn till kvarvarande.
  if not v_won then
    v_unit := case when v_room.team_mode then v_player.team_id else v_player.id end;
    v_list := coalesce((
      select jsonb_agg(x) from jsonb_array_elements(v_room.winner_unit_ids) x
      where x <> to_jsonb(v_unit)
    ), '[]'::jsonb);

    if v_list = '[]'::jsonb then
      update public.rooms
        set status = 'playing', winner_round_id = null, winner_unit_ids = '[]'::jsonb,
            winner_team_id = null, winner_player_id = null
        where id = p_room_id;
    else
      update public.rooms
        set winner_unit_ids = v_list,
            winner_team_id = case when v_room.team_mode then (v_list ->> 0)::uuid else null end,
            winner_player_id = case when v_room.team_mode then null else (v_list ->> 0)::uuid end
        where id = p_room_id;
    end if;
  end if;

  -- Frigör rundans kryss så ett felklick kan läggas om.
  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is not null then
    if v_room.team_mode then
      update public.round_answers set has_marked = false
        where round_id = v_round.id and team_id = v_player.team_id;
    else
      update public.round_answers set has_marked = false
        where round_id = v_round.id and player_id = v_player.id;
    end if;
  end if;

  return v_card;
end;
$function$
;

grant execute on function public.lock_answer(uuid, text) to authenticated;
grant execute on function public.mark_cross(uuid, integer) to authenticated;
grant execute on function public.unmark_cross(uuid, integer) to authenticated;

notify pgrst, 'reload schema';
