-- =====================================================================
--  HITSTER BINGO ONLINE – 5 kategorier (uppdaterar Fas 2)
--
--  Ändring: "Före/efter 2000" tas bort. In kommer "Årtal ±3 år" (approx_year)
--  och "Låttiteln" (title). Totalt 5 kategorier → brickan blir 5x5 latinsk
--  kvadrat, och discokulan får 5 segment.
--
--  Kör i Supabase SQL Editor efter 0002. Nollställer pågående test-partier.
-- =====================================================================

-- 1. Tillåtna kategorier på rounds
alter table public.rounds drop constraint if exists rounds_category_check;
alter table public.rounds add constraint rounds_category_check
  check (category in ('decade', 'artist', 'exact_year', 'approx_year', 'title'));

-- 2. Bricka-generator: 5x5 latinsk kvadrat med 5 kategorier
create or replace function public.gen_bingo_grid()
returns jsonb
language plpgsql
as $$
declare
  cats text[];
  rp   int[];
  cp   int[];
  i int;
  j int;
  v int;
  grid jsonb := '[]'::jsonb;
begin
  select array_agg(c order by random()) into cats
    from unnest(array['decade', 'artist', 'exact_year', 'approx_year', 'title']) as c;
  select array_agg(x order by random()) into rp from generate_series(0, 4) as x;
  select array_agg(x order by random()) into cp from generate_series(0, 4) as x;

  for i in 0..4 loop
    for j in 0..4 loop
      v := (rp[i + 1] + cp[j + 1]) % 5;                 -- 0..4
      grid := grid || jsonb_build_object('category', cats[v + 1], 'filled', false);
    end loop;
  end loop;
  return grid;
end;
$$;

-- 3. spin_wheel: slumpar bland 5 kategorier
create or replace function public.spin_wheel(p_room_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats constant text[] := array['decade', 'artist', 'exact_year', 'approx_year', 'title'];
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan snurra'; end if;

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

-- 4. mark_cross: vinstkoll för 5x5 + rutindex 0..24
create or replace function public.mark_cross(p_room_id uuid, p_cell int)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_player public.players;
  v_card   public.bingo_cards;
  v_round  public.rounds;
  v_grid   jsonb;
  v_won    boolean := false;
  r int;
  c int;
  line_full boolean;
begin
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is null then raise exception 'Du har ingen bricka'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if (v_card.grid -> p_cell ->> 'category') <> v_round.category then
    raise exception 'Rutan matchar inte rundans kategori';
  end if;
  if (v_card.grid -> p_cell ->> 'filled')::boolean then
    return v_card;
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'true'::jsonb);

  -- Vinst: någon hel rad ELLER hel kolumn (5 rutor) ifylld → täcker alla 5 kategorier.
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

  if v_won then
    update public.rooms set status = 'finished', winner_player_id = v_player.id
      where id = p_room_id;
    insert into public.room_events (room_id, type, payload)
    values (p_room_id, 'HITSTER_WIN',
            jsonb_build_object('player_id', v_player.id, 'display_name', v_player.display_name));
  end if;

  return v_card;
end;
$$;

-- 5. erase_cross: rutindex 0..24 (oförändrad logik i övrigt)
create or replace function public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell int)
returns public.bingo_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_card   public.bingo_cards;
  v_grid   jsonb;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if not coalesce(v_room.erase_rule_enabled, false) then
    raise exception 'Suddregeln är avstängd';
  end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null or v_round.category <> 'exact_year' then
    raise exception 'Sudd tillåts bara på kategorin Exakt årtal';
  end if;

  select * into v_card from public.bingo_cards where id = p_target_card and room_id = p_room_id;
  if v_card.id is null then raise exception 'Brickan finns inte'; end if;
  if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then
    return v_card;
  end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$$;

-- 6. Nollställ pågående test-partier (gamla 4x4-brickor + gamla kategorier)
delete from public.room_events;
delete from public.rounds;
delete from public.bingo_cards;
update public.rooms set status = 'lobby', winner_player_id = null where status <> 'lobby';
