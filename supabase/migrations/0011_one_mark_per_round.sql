-- =====================================================================
--  HITSTER BINGO ONLINE – Bara ETT kryss per runda vid rätt svar
--
--  Tidigare kunde en spelare/lag med rätt svar kryssa FLERA rutor i samma
--  runda (upp till en per kategori-cell). Rätt svar ska bara ge ETT kryss.
--  Vi spårar det på round_answers.has_marked (per spelare/lag och runda):
--    - mark_cross vägrar om enheten redan kryssat denna runda.
--    - unmark_cross nollställer flaggan så ett felklick kan läggas om.
--
--  Additiv + idempotent. Kör efter 0010.
-- =====================================================================

alter table public.round_answers
  add column if not exists has_marked boolean not null default false;

-- --- mark_cross: validerat RÄTT svar + högst ett kryss per runda -----
create or replace function public.mark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
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
  r int; c int; line_full boolean;
begin
  select * into v_room from public.rooms where id = p_room_id;
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

  -- SPÄRR: när en låt spelats får man kryssa först efter att svaren avslöjats,
  -- bara om den egna enhetens svar var rätt (auto eller värdens override) OCH
  -- bara ETT kryss per runda.
  if v_round.current_track_id is not null then
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
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);

  for r in 0..4 loop
    line_full := true;
    for c in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;
  for c in 0..4 loop
    line_full := true;
    for r in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Krysset är lagt: markera att enheten förbrukat rundans kryss.
  if v_round.current_track_id is not null and v_myans.id is not null then
    update public.round_answers set has_marked = true where id = v_myans.id;
  end if;

  if v_won then
    if v_room.team_mode then
      select name into v_label from public.teams where id = v_player.team_id;
      update public.rooms set status = 'finished', winner_team_id = v_player.team_id, winner_player_id = null
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'HITSTER_WIN', jsonb_build_object('team_id', v_player.team_id, 'display_name', v_label));
    else
      update public.rooms set status = 'finished', winner_player_id = v_player.id
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'HITSTER_WIN', jsonb_build_object('player_id', v_player.id, 'display_name', v_player.display_name));
    end if;
  end if;

  return v_card;
end;
$$;

-- --- unmark_cross: ångra kryss + frigör rundans kryss igen ----------
create or replace function public.unmark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  r int; c int; line_full boolean;
begin
  select * into v_room from public.rooms where id = p_room_id;
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

  for r in 0..4 loop
    line_full := true;
    for c in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;
  for c in 0..4 loop
    line_full := true;
    for r in 0..4 loop
      if not ((v_grid -> (r * 5 + c) ->> 'filled')::boolean) then line_full := false; end if;
    end loop;
    if line_full then v_won := true; end if;
  end loop;

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  -- Bröts den registrerade vinstlinjen? Nollställ vinsten.
  if not v_won then
    if v_room.team_mode and v_room.winner_team_id = v_player.team_id then
      update public.rooms set status = 'playing', winner_team_id = null where id = p_room_id;
    elsif not v_room.team_mode and v_room.winner_player_id = v_player.id then
      update public.rooms set status = 'playing', winner_player_id = null where id = p_room_id;
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
$$;

notify pgrst, 'reload schema';
