-- =====================================================================
--  LÅTSNURRAN – Egna kategorier i åldersläge (4 st)
--
--  När rummet spelar mot ett årsfönster (year_min/year_max satt) blir
--  "Årtionde" och "Årtal ±3" nästan gratis – eran är ju redan smal. I
--  åldersläge byts de mot EN tightare årtals-kategori, ±1 år (approx_year_1),
--  så snurran och brickan kör fyra kategorier:
--      exact_year · artist · title · approx_year_1
--  Normalt läge (Alla/Svenska, inget årsfönster) är oförändrat med fem.
--
--  Brickan (5x5) vinns på hel rad/kolumn, inte på kategori-balans, så 25 rutor
--  behöver INTE delas jämnt – 4 kategorier fungerar (en får 7, resten 6).
--  MÅSTE spegla frontendens AGE_CATEGORY_ORDER i src/lib/constants.js.
--
--  Additiv + idempotent. Kör efter 0030.
-- =====================================================================

-- ====================================================================
--  Kategori-set per rum (åldersläge → 4, annars → 5)
-- ====================================================================
create or replace function public._room_categories(p_year_min int, p_year_max int)
returns text[] language sql immutable set search_path = public as $$
  select case
    when p_year_min is not null or p_year_max is not null
      then array['exact_year', 'artist', 'title', 'approx_year_1']
    else array['decade', 'artist', 'exact_year', 'approx_year', 'title']
  end;
$$;

-- ====================================================================
--  Bricka från ett godtyckligt kategori-set (25 rutor, ~jämnt, fritt slumpat)
-- ====================================================================
create or replace function public.gen_bingo_grid(p_cats text[])
returns jsonb language sql volatile set search_path = public as $$
  select jsonb_agg(jsonb_build_object('category', cat, 'filled', false) order by r)
  from (
    select p_cats[(i % array_length(p_cats, 1)) + 1] as cat, random() as r
    from generate_series(0, 24) as i
  ) s;
$$;

-- ====================================================================
--  Svarsbedömning: lägg till ±1 år (approx_year_1)
--  (kopia av 0010 + en gren; övriga grenar oförändrade)
-- ====================================================================
create or replace function public._judge_answer(p_cat text, p_answer text, p_meta jsonb)
returns boolean language plpgsql immutable set search_path = public as $$
declare
  fy int;
  y  int;
  d  int;
  dd text;
begin
  if p_answer is null or p_meta is null then return false; end if;
  fy := nullif(p_meta ->> 'year', '')::int;
  y  := (substring(p_answer from '((?:19|20)\d{2})'))::int;

  if p_cat = 'exact_year' then
    return y is not null and fy is not null and y = fy;
  elsif p_cat = 'approx_year' then
    return y is not null and fy is not null and abs(y - fy) <= 3;
  elsif p_cat = 'approx_year_1' then
    return y is not null and fy is not null and abs(y - fy) <= 1;
  elsif p_cat = 'decade' then
    if y is null then
      dd := substring(lower(p_answer) from '([0-9]0)\s*-?\s*tal');
      if dd is not null then
        d := dd::int;
        d := case when d >= 30 then 1900 + d else 2000 + d end;
      end if;
    else
      d := (y / 10) * 10;
    end if;
    return d is not null and fy is not null and d = (fy / 10) * 10;
  elsif p_cat = 'artist' then
    return public._fuzzy_text(p_answer, p_meta ->> 'artist');
  elsif p_cat = 'title' then
    return public._fuzzy_text(p_answer, p_meta ->> 'name');
  else
    return false;
  end if;
end;
$$;

-- ====================================================================
--  spin_wheel: välj kategori ur rummets set (4 i åldersläge)
--  (kopia av 0027 – enda ändringen: cats + slumpindex)
-- ====================================================================
create or replace function public.spin_wheel(p_room_id uuid)
returns rounds language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_prev  public.rounds;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats    text[];
begin
  perform public._rate_limit('spin', 30, interval '1 minute');
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

  cats  := public._room_categories(v_room.year_min, v_room.year_max);
  v_cat := cats[floor(random() * array_length(cats, 1))::int + 1];
  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  insert into public.rounds (room_id, round_number, category, spun_by, state, timer_start_at)
  values (p_room_id, v_num, v_cat, v_uid, 'playing', now() + interval '4.2 seconds')
  returning * into v_round;

  update public.rooms set status = 'playing'
    where id = p_room_id and status <> 'finished';
  return v_round;
end $$;

-- ====================================================================
--  Kort-skaparna: bygg brickan ur rummets kategori-set
--  (kopior av 0027 – enda ändringen: gen_bingo_grid() → med kategori-set)
-- ====================================================================
create or replace function public.ensure_card(p_room_id uuid)
returns bingo_cards language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_card   public.bingo_cards;
  v_tid    uuid;
  v_cats   text[];
begin
  perform public._rate_limit('card', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;
  v_cats := public._room_categories(v_room.year_min, v_room.year_max);

  if v_room.team_mode then
    v_tid := v_player.team_id;
    if v_tid is null then
      insert into public.teams (room_id, name, sort)
      values (p_room_id, v_player.display_name, 900) returning id into v_tid;
      update public.players set team_id = v_tid where id = v_player.id;
    end if;
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_tid;
    if v_card.id is not null then return v_card; end if;
    insert into public.bingo_cards (room_id, team_id, grid)
    select p_room_id, v_tid, public.gen_bingo_grid(v_cats)
    where not exists (select 1 from public.bingo_cards where room_id = p_room_id and team_id = v_tid);
    select * into v_card from public.bingo_cards where room_id = p_room_id and team_id = v_tid;
    return v_card;
  end if;

  -- Solo-läge
  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is not null then return v_card; end if;
  insert into public.bingo_cards (room_id, player_id, user_id, grid)
  values (p_room_id, v_player.id, v_uid, public.gen_bingo_grid(v_cats))
  on conflict (room_id, player_id) do update set grid = public.bingo_cards.grid
  returning * into v_card;
  return v_card;
end $$;

create or replace function public.start_game(p_room_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_p    public.players;
  v_tid  uuid;
  v_cats text[];
begin
  perform public._rate_limit('game_control', 20, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta spelet'; end if;
  v_cats := public._room_categories(v_room.year_min, v_room.year_max);

  -- Färsk giv: rensa gamla brickor (byter läge/omstart från lobbyn).
  delete from public.bingo_cards where room_id = p_room_id;

  if v_room.team_mode then
    -- Spelare utan lag → eget lag (uppkallat efter spelaren).
    for v_p in select * from public.players where room_id = p_room_id and team_id is null loop
      insert into public.teams (room_id, name, sort)
      values (p_room_id, v_p.display_name, 900)
      returning id into v_tid;
      update public.players set team_id = v_tid where id = v_p.id;
    end loop;

    -- En bricka per lag.
    insert into public.bingo_cards (room_id, team_id, grid)
    select p_room_id, t.id, public.gen_bingo_grid(v_cats)
      from public.teams t where t.room_id = p_room_id;
  else
    -- En bricka per spelare.
    insert into public.bingo_cards (room_id, player_id, user_id, grid)
    select p_room_id, p.id, p.user_id, public.gen_bingo_grid(v_cats)
      from public.players p where p.room_id = p_room_id;
  end if;

  update public.rooms
    set status = 'playing', winner_player_id = null, winner_team_id = null
    where id = p_room_id;
end $$;

create or replace function public.reset_game(p_room_id uuid, p_back_to_lobby boolean default false)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('game_control', 20, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan återställa'; end if;

  delete from public.rounds where room_id = p_room_id;
  delete from public.room_events where room_id = p_room_id;
  update public.bingo_cards
    set grid = public.gen_bingo_grid(public._room_categories(v_room.year_min, v_room.year_max)),
        has_won = false
    where room_id = p_room_id;
  update public.rooms
    set winner_player_id = null, winner_team_id = null,
        status = case when p_back_to_lobby then 'lobby' else 'playing' end
    where id = p_room_id;
end $$;

-- Behörigheter (create or replace behåller grants, men explicit sedan 0023).
grant execute on function public.spin_wheel(uuid) to authenticated;
grant execute on function public.ensure_card(uuid) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;
grant execute on function public.reset_game(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
