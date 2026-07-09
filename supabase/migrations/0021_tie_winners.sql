-- =====================================================================
--  LÅTSNURRAN – Oavgjort när flera vinner i samma runda
--
--  Tidigare avgjorde FÖRSTA krysset spelet (status=finished, winner_*_id) och
--  klienten låste då ute alla andra → om två lag hade 4 i rad och samma
--  kategori kvar, och båda svarade rätt, hann bara ETT lag kryssa. Nu blir det
--  OAVGJORT: alla enheter som fullbordar en rad i den AVGÖRANDE rundan räknas
--  som medvinnare.
--
--  Nya kolumner på rooms:
--    winner_round_id  – rundan där spelet avgjordes (tie-fönstret)
--    winner_unit_ids  – jsonb-array av vinnande enhets-id (team_id/player_id)
--
--  mark_cross: första vinsten sätter finished + winner_round_id + listan; fler
--  vinster i SAMMA runda läggs till i listan. unmark_cross tar bort enheten ur
--  listan igen (töms den → tillbaka till spel). Klienten låter kvarvarande
--  rätt-svarande i den avgörande rundan kryssa klart innan vinsten visas.
--
--  Additiv + idempotent. Kör efter 0020.
-- =====================================================================

alter table public.rooms
  add column if not exists winner_round_id uuid;
alter table public.rooms
  add column if not exists winner_unit_ids jsonb not null default '[]'::jsonb;

-- --- mark_cross: ackumulera medvinnare i den avgörande rundan --------
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
  v_unit   uuid;
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
$$;

-- --- unmark_cross: ta bort enheten ur vinnarlistan vid ångrat kryss --
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
  v_unit   uuid;
  v_list   jsonb;
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
$$;

notify pgrst, 'reload schema';
