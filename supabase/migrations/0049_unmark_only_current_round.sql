-- ====================================================================
--  0049  Bara den aktuella rundans kryss får tas bort
-- --------------------------------------------------------------------
--  BUGG: unmark_cross tog bort VILKET kryss som helst, oavsett vilken runda
--  det lades i. Två konsekvenser, båda allvarliga:
--
--   1. Fällan. Ett kryss från en tidigare runda gick att råka ta bort, och
--      det gick sedan inte att få tillbaka – att kryssa kräver att man svarat
--      rätt PÅ DEN AKTUELLA rundan och att rutans kategori matchar snurran.
--      Spelaren förstörde alltså sin egen bricka utan väg tillbaka.
--
--   2. Exploiten. unmark_cross nollställer rundans has_marked ("frigör
--      rundans kryss så ett felklick kan läggas om"). Kombinerat med punkt 1
--      gick det att: svara rätt → kryssa → ta bort ett GAMMALT kryss ur en
--      annan kategori → kryssa igen i den aktuella. Antalet kryss var
--      oförändrat, men man flyttade successivt över gamla kryss till den
--      kategori snurran råkade visa och kunde bygga ihop en rad man aldrig
--      spelat ihop.
--
--  Avsedd regel: ångerknappen finns för att byta PLACERING av krysset man
--  just fick. Inget mer.
--
--  LÖSNING: mark_cross stämplar rundans id på rutan (grid[i].round), och
--  unmark_cross vägrar rutor som inte bär den pågående rundans id. Rutor
--  som kryssades före den här migrationen saknar stämpel och blir därmed
--  också ovägerliga – vilket är exakt rätt beteende, de är från tidigare
--  rundor.
--
--  Suddregeln (erase_cross) rörs INTE: att sudda hos en medspelare är en
--  avsiktlig mekanik som ska gälla över rundgränser.
--
--  Additiv + idempotent. Kör efter 0028.
-- ====================================================================

-- --- mark_cross: stämpla rundan på rutan ---
create or replace function public.mark_cross(p_room_id uuid, p_cell integer)
returns public.bingo_cards
language plpgsql security definer set search_path to 'public'
as $function$
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

  if v_room.status = 'finished' and v_room.winner_round_id is distinct from v_round.id then
    raise exception 'Spelet är avgjort';
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then return v_card; end if;

  -- ÄNDRAT: stämpla rundan på rutan, så unmark_cross kan skilja "krysset jag
  -- just fick" från "kryss jag spelat ihop tidigare".
  v_grid := jsonb_set(
              jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb),
              array[p_cell::text, 'round'], to_jsonb(v_round.id));
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

  if v_myans.id is not null then
    update public.round_answers set has_marked = true where id = v_myans.id;
  end if;

  if v_won then
    v_unit := case when v_room.team_mode then v_player.team_id else v_player.id end;

    if v_room.status <> 'finished' then
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
      update public.rooms
        set winner_unit_ids = case when winner_unit_ids ? v_unit::text
                                   then winner_unit_ids
                                   else winner_unit_ids || to_jsonb(v_unit) end
        where id = p_room_id;
    end if;
  end if;

  return v_card;
end;
$function$;

-- --- unmark_cross: vägra rutor från tidigare rundor ---
create or replace function public.unmark_cross(p_room_id uuid, p_cell integer)
returns public.bingo_cards
language plpgsql security definer set search_path to 'public'
as $function$
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

  -- NYTT: ångerknappen gäller bara krysset från den PÅGÅENDE rundan. Rutor
  -- utan stämpel (kryssade före 0049) räknas som tidigare rundor.
  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null
     or (v_card.grid -> p_cell ->> 'round') is distinct from v_round.id::text then
    raise exception 'Kryss från tidigare rundor kan inte tas bort';
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  v_won := public._grid_has_line(v_grid);

  update public.bingo_cards set grid = v_grid, has_won = v_won
    where id = v_card.id returning * into v_card;

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

  -- Frigör rundans kryss så felklicket kan läggas om. Säkert nu: vi kom bara
  -- hit om rutan faktiskt tillhörde den pågående rundan.
  if v_room.team_mode then
    update public.round_answers set has_marked = false
      where round_id = v_round.id and team_id = v_player.team_id;
  else
    update public.round_answers set has_marked = false
      where round_id = v_round.id and player_id = v_player.id;
  end if;

  return v_card;
end;
$function$;

grant execute on function public.mark_cross(uuid, integer) to authenticated;
grant execute on function public.unmark_cross(uuid, integer) to authenticated;

notify pgrst, 'reload schema';
