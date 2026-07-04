-- =====================================================================
--  HITSTER BINGO ONLINE – ångra eget kryss
--
--  Låter en spelare ta bort ett kryss på SIN EGEN bricka (om man råkat
--  kryssa fel). Server-auktoritativt: bara din egen bricka, valfri kategori.
--  Räknar om vinsten (och släcker ev. registrerad vinst om linjen bryts).
--
--  Kör efter 0003.
-- =====================================================================

create or replace function public.unmark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_grid   jsonb;
  v_won    boolean := false;
  r int;
  c int;
  line_full boolean;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is null then raise exception 'Du har ingen bricka'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then
    return v_card; -- redan tom, gör inget
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);

  -- Räkna om vinst (5x5): finns fortfarande en hel rad/kolumn?
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

  -- Om jag var registrerad vinnare men linjen nu är bruten: nollställ vinsten.
  if not v_won and v_room.winner_player_id = v_player.id then
    update public.rooms set status = 'playing', winner_player_id = null where id = p_room_id;
  end if;

  return v_card;
end;
$$;

grant execute on function public.unmark_cross(uuid, int) to authenticated;
