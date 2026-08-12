-- =====================================================================
--  LÅTSNURRAN – hjulets kategorier går att välja, och det finns fler att
--  välja mellan
--
--  Kategorierna har varit två fasta uppsättningar sedan 0031: fem vanliga,
--  och fem för åldersläget när årsspannet är smalare än 20 år. Vill man inte
--  ha "Exakt årtal" har det inte funnits någon väg runt det.
--
--  NU: rooms.categories är en lista med exakt fem nycklar som värden får
--  sätta. Är den null gäller precis som förut – åldersläget när spannet är
--  smalt, annars de vanliga fem. Ingen befintlig match ändrar beteende.
--
--  FEM NYA KATEGORIER att välja bland (utöver de fem vanliga):
--
--    approx_year_1  ±1 år        fanns redan, men bara i åldersläget
--    before_after   före/efter   fanns redan, men bara i åldersläget
--    approx_year_5  ±5 år        ny – den snällaste årtalsfrågan
--    genre          vilken genre ny – pop/rock/hiphop & R&B/EDM/dansband
--    swedish        svenskt?     ny – svensk eller utländsk låt
--
--  Tio att välja fem av. Ingen av dem behövde ny data: genre och språk står
--  redan på varje rad i potten, de har bara aldrig varit frågor.
--
--  TVÅ AV DEM KAN BLI GRATISPOÄNG, och det är värdens sak att veta om:
--  'genre' i ett rum som filtrerat på en enda genre har alltid samma svar,
--  och 'swedish' i ett rum som valt Svenska likaså. Lobbyns väljare får
--  säga ifrån; servern hindrar det inte, för ett rum kan byta urval mitt i.
--
--  GENRE-RUNDOR DRAR EN LÅT SOM HAR EN GENRE. 1200 av pottens rader saknar
--  genre (Deezer/iTunes sa inget vi känner igen), och en sådan låt hade
--  gjort rundan omöjlig att svara rätt på. Villkoret sitter i pott-urvalet,
--  inte i _pool_match: det gäller BARA när rundan är en genre-runda.
--
--  FACIT-METAN BÄR NUMERA genre + sv. Utan dem finns inget att döma mot.
--  Gamla rundor har dem inte, men de kan heller aldrig ha en genre-runda.
--
--  REGELN FRÅN 0037 GÄLLER FORTFARANDE: en ny kategori kräver ändring på
--  TRE ställen – _room_categories, rounds_category_check och _judge_answer.
--  Alla tre är med här.
--
--  Funktionskropparna nedan är LIVE-DUMPAR med kirurgiska byten (samma
--  metod som 0027), just för att en handskriven omskrivning tyst tappar
--  senare tillägg – det var så 0030 fick städa upp efter 0027.
--
--  Additiv + idempotent. Kör efter 0083.
-- =====================================================================

-- --- 1. vilka nycklar som finns, och vad som är en giltig uppsättning --
--  Används både av kolumnens check-villkor och av _room_categories, så att
--  "giltig lista" betyder samma sak på båda ställena.
create or replace function public._valid_categories(p_cats jsonb)
returns boolean language sql immutable set search_path = public as $function$
  select p_cats is null or (
    jsonb_typeof(p_cats) = 'array'
    and jsonb_array_length(p_cats) = 5
    and (select count(distinct c) from jsonb_array_elements_text(p_cats) c) = 5
    and not exists (
      select 1 from jsonb_array_elements_text(p_cats) c
       where c not in ('decade', 'artist', 'exact_year', 'approx_year', 'approx_year_1',
                       'approx_year_5', 'title', 'before_after', 'genre', 'swedish'))
  );
$function$;

alter table public.rooms add column if not exists categories jsonb;
alter table public.rooms drop constraint if exists rooms_categories_check;
alter table public.rooms add constraint rooms_categories_check
  check (public._valid_categories(categories));

-- 0023 låste rooms-UPDATE till namngivna kolumner; den nya måste med.
grant update (categories) on public.rooms to authenticated;

-- Ett nytt kategorivärde kräver att constrainten känner igen det (0037).
alter table public.rounds drop constraint if exists rounds_category_check;
alter table public.rounds add constraint rounds_category_check
  check (category = any (array['decade', 'artist', 'exact_year', 'approx_year', 'title',
                              'approx_year_1', 'before_after', 'approx_year_5',
                              'genre', 'swedish']));

-- --- 2. rummets uppsättning ------------------------------------------
--  Ny signatur, och den gamla släpps: en `create or replace` med nya
--  parametrar hade lagt sig BREDVID den gamla, och en kvarglömd överlagring
--  var precis det som gjorde snurren obrukbar i 0013.
drop function if exists public._room_categories(integer, integer);

create or replace function public._room_categories(
  p_cats jsonb, p_year_min integer, p_year_max integer)
returns text[] language sql stable set search_path = public as $function$
  select case
    -- Värdens eget val vinner. Ogiltigt innehåll faller tillbaka på det
    -- automatiska i stället för att stoppa spelet.
    when p_cats is not null and public._valid_categories(p_cats)
      then (select array_agg(c order by ord)
              from jsonb_array_elements_text(p_cats) with ordinality t(c, ord))
    when (p_year_min is not null or p_year_max is not null)
     and (coalesce(p_year_max, extract(year from now())::int)
          - coalesce(p_year_min, 1900) + 1) < 20
      then array['exact_year', 'artist', 'title', 'approx_year_1', 'before_after']
    else array['decade', 'artist', 'exact_year', 'approx_year', 'title']
  end;
$function$;

-- --- 3. rättningen kan de nya frågorna -------------------------------
--  Oförändrad för de sju gamla kategorierna; tre grenar tillkommer.
create or replace function public._judge_answer(p_cat text, p_answer text, p_meta jsonb)
returns boolean language plpgsql immutable set search_path to 'public' as $function$
declare
  fy int;
  y  int;
  d  int;
  dd text;
  pv int;
  sv text;
begin
  if p_answer is null or p_meta is null then return false; end if;
  fy := nullif(p_meta ->> 'year', '')::int;
  pv := nullif(p_meta ->> 'pivot', '')::int;
  y  := (substring(p_answer from '((?:19|20)\d{2})'))::int;

  if p_cat = 'exact_year' then
    return y is not null and fy is not null and y = fy;
  elsif p_cat = 'approx_year' then
    return y is not null and fy is not null and abs(y - fy) <= 3;
  elsif p_cat = 'approx_year_1' then
    return y is not null and fy is not null and abs(y - fy) <= 1;
  elsif p_cat = 'approx_year_5' then
    return y is not null and fy is not null and abs(y - fy) <= 5;
  elsif p_cat = 'before_after' then
    return fy is not null and pv is not null and (
         (lower(p_answer) = 'efter' and fy >= pv)
      or (lower(p_answer) = 'före'  and fy <  pv)
    );
  elsif p_cat = 'genre' then
    -- Svaret kommer som nyckel från knapparna, men skrivs det för hand
    -- godtas de namn folk faktiskt använder. _genre_alias tar rnb -> hiphop
    -- och dance -> edm, så de behöver inte stå här.
    if p_meta ->> 'genre' is null then return false; end if;
    return public._genre_alias(
             case lower(btrim(p_answer))
               when 'r&b' then 'hiphop'
               when 'rap' then 'hiphop'
               when 'hiphop/r&b' then 'hiphop'
               when 'elektroniskt' then 'edm'
               when 'schlager' then 'dansband'
               when 'dansband/schlager' then 'dansband'
               else lower(btrim(p_answer))
             end) = (p_meta ->> 'genre');
  elsif p_cat = 'swedish' then
    sv := p_meta ->> 'sv';
    if sv is null then return false; end if;
    return case lower(btrim(p_answer))
             when 'svensk'    then sv::boolean
             when 'svenskt'   then sv::boolean
             when 'utländsk'  then not sv::boolean
             when 'utländskt' then not sv::boolean
             else false
           end;
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
$function$;

-- --- 4. de funktioner som bara behövde veta om det nya ---------------

-- ensure_card: kategorierna kommer från rummet när värden valt dem
CREATE OR REPLACE FUNCTION public.ensure_card(p_room_id uuid)
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
  v_tid    uuid;
  v_cats   text[];
begin
  perform public._rate_limit('card', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;
  v_cats := public._room_categories(v_room.categories, v_room.year_min, v_room.year_max);

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

  select * into v_card from public.bingo_cards
    where room_id = p_room_id and player_id = v_player.id;
  if v_card.id is not null then return v_card; end if;
  insert into public.bingo_cards (room_id, player_id, user_id, grid)
  values (p_room_id, v_player.id, v_uid, public.gen_bingo_grid(v_cats))
  on conflict (room_id, player_id) do update set grid = public.bingo_cards.grid
  returning * into v_card;
  return v_card;
end $function$
;

-- start_game: kategorierna kommer från rummet när värden valt dem
CREATE OR REPLACE FUNCTION public.start_game(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_cats := public._room_categories(v_room.categories, v_room.year_min, v_room.year_max);

  delete from public.bingo_cards where room_id = p_room_id;

  if v_room.team_mode then
    for v_p in select * from public.players where room_id = p_room_id and team_id is null loop
      insert into public.teams (room_id, name, sort)
      values (p_room_id, v_p.display_name, 900)
      returning id into v_tid;
      update public.players set team_id = v_tid where id = v_p.id;
    end loop;

    insert into public.bingo_cards (room_id, team_id, grid)
    select p_room_id, t.id, public.gen_bingo_grid(v_cats)
      from public.teams t where t.room_id = p_room_id;
  else
    insert into public.bingo_cards (room_id, player_id, user_id, grid)
    select p_room_id, p.id, p.user_id, public.gen_bingo_grid(v_cats)
      from public.players p where p.room_id = p_room_id;
  end if;

  update public.rooms
    set status = 'playing', winner_player_id = null, winner_team_id = null
    where id = p_room_id;
end $function$
;

-- reset_game: kategorierna kommer från rummet när värden valt dem
CREATE OR REPLACE FUNCTION public.reset_game(p_room_id uuid, p_back_to_lobby boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    set grid = public.gen_bingo_grid(public._room_categories(v_room.categories, v_room.year_min, v_room.year_max)),
        has_won = false
    where room_id = p_room_id;
  update public.rooms
    set winner_player_id = null, winner_team_id = null,
        winner_unit_ids = '[]'::jsonb, winner_round_id = null,
        status = case when p_back_to_lobby then 'lobby' else 'playing' end
    where id = p_room_id;
end $function$
;

-- spin_wheel: kategorierna kommer från rummet när värden valt dem
CREATE OR REPLACE FUNCTION public.spin_wheel(p_room_id uuid)
 RETURNS rounds
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_prev  public.rounds;
  v_cat   text;
  v_num   int;
  v_round public.rounds;
  cats    text[];
  v_lo    int;
  v_hi    int;
  v_pivot int;
begin
  perform public._rate_limit('spin', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan snurra'; end if;

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

  cats  := public._room_categories(v_room.categories, v_room.year_min, v_room.year_max);
  v_cat := cats[floor(random() * array_length(cats, 1))::int + 1];

  v_pivot := null;
  if v_cat = 'before_after' then
    v_lo := coalesce(v_room.year_min, 1950);
    v_hi := coalesce(v_room.year_max, extract(year from now())::int);
    if v_hi <= v_lo + 1 then
      v_pivot := v_lo + 1;
    else
      v_pivot := v_lo + round((v_hi - v_lo) * (0.25 + random() * 0.5))::int;
      v_pivot := greatest(v_lo + 1, least(v_hi, v_pivot));
    end if;
  end if;

  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  insert into public.rounds (room_id, round_number, category, spun_by, state, timer_start_at, pivot_year)
  values (p_room_id, v_num, v_cat, v_uid, 'playing', now() + interval '4.2 seconds', v_pivot)
  returning * into v_round;

  update public.rooms set status = 'playing'
    where id = p_room_id and status <> 'finished';
  return v_round;
end $function$
;

-- erase_cross: ±5 år räknas som årtalskategori
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
  v_year_cat boolean;
  v_year_cats constant text[] := array['exact_year', 'approx_year', 'approx_year_1', 'approx_year_5'];
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
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan du suddar';
  end if;

  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;

  -- Två vägar till sudd, en per kategorityp:
  --   årtalskategori  → rundans egna svar måste vara rätt (0063)
  --   övriga          → bonusgissningen måste vara rätt (oberoende av svaret)
  v_year_cat := v_round.category = any(v_year_cats);
  if v_year_cat then
    if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
      raise exception 'Bara rätt svar får sudda';
    end if;
  else
    if v_myans.bonus_correct is not true then
      raise exception 'Sudd kräver att du prickat årtalet i bonusrutan';
    end if;
  end if;

  if coalesce(v_myans.has_erased, false) then
    raise exception 'Du har redan suddat den här rundan';
  end if;

  select * into v_card from public.bingo_cards where id = p_target_card and room_id = p_room_id;
  if v_card.id is null then raise exception 'Brickan finns inte'; end if;
  if v_room.team_mode then
    if v_card.team_id = v_player.team_id then raise exception 'Du kan inte sudda på ditt eget lags bricka'; end if;
  else
    if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  -- Tom ruta: ingen ändring och suddet är kvar att använda.
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  update public.round_answers set has_erased = true where id = v_myans.id;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$function$
;

-- _grade_round: bonusrutan hör inte hemma på ±5 heller
CREATE OR REPLACE FUNCTION public._grade_round(p_round_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.round_answers ra
    set auto_correct = public._judge_answer(
          r.category, ra.answer,
          coalesce(rt.meta, r.current_track_meta, '{}'::jsonb)
            || jsonb_build_object('pivot', r.pivot_year)),
        bonus_correct = case
          when not coalesce(ro.erase_rule_enabled, false) then null
          when r.category = any(array['exact_year', 'approx_year', 'approx_year_1', 'approx_year_5']) then null
          else public._judge_answer(
                 'exact_year', ra.bonus_year,
                 coalesce(rt.meta, r.current_track_meta, '{}'::jsonb))
        end
    from public.rounds r
    join public.rooms ro on ro.id = r.room_id
    left join public.round_tracks rt on rt.round_id = r.id
    where ra.round_id = p_round_id and r.id = p_round_id;
$function$
;

-- start_random_track: metan bär genre + språk, och genre-rundor drar en låt med genre
CREATE OR REPLACE FUNCTION public.start_random_track(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_track public.track_pool;
  v_bands jsonb;
  v_req   bigint;
begin
  perform public._rate_limit('track_start', 20, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;
  if v_round.current_track_id is not null then raise exception 'Rundan har redan en låt'; end if;

  delete from public.pending_tracks where room_id = p_room_id;

  -- Samma band gäller alla tre stegen: faller steg 1 ska steg 2 leta i det
  -- urval rundan redan bestämt sig för, inte i ett annat.
  v_bands := public._pool_bands(v_room.swedish_mode, v_room.year_bands, v_room.genres);

  -- Steg 1: ospelad i rummet OCH inte känd som ohittbar.
  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
        and (v_round.category is distinct from 'genre'
             or public._genre_key(tp.genre) is not null)
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;

  -- Steg 2: släpp kravet på ospelad, behåll bortsorteringen av ohittbara.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
        and (v_round.category is distinct from 'genre'
             or public._genre_key(tp.genre) is not null)
        and (tp.preview_url is not null
             or tp.preview_checked_at is null
             or tp.preview_checked_at < now() - interval '7 days')
      order by random() limit 1;
  end if;

  -- Steg 3: smal pott där allt är markerat – hellre en osäker låt än inget.
  if v_track.id is null then
    select tp.* into v_track from public.track_pool tp
      where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
        and (v_round.category is distinct from 'genre'
             or public._genre_key(tp.genre) is not null)
      order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  -- Cacheträff: starta direkt, utan att fråga iTunes. Katalograder har ingen
  -- hållbarhetsgräns – de är inte hittade via sökningen och kan inte
  -- verifieras om den vägen.
  if v_track.preview_url is not null
     and (v_track.preview_source = 'catalog'
          or v_track.preview_checked_at > now() - interval '30 days') then
    update public.rounds
      set current_track_id = v_track.preview_url,
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text,
                               'genre', public._genre_key(v_track.genre),
                               'sv', v_track.sv))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;
    return;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 4, 1);

  -- Säg till ALLA att en låt är på väg. Utan det här visste bara värden
  -- (som tryckte på knappen) att något hände, och övriga satt i tystnad.
  update public.rounds set state = 'loading' where id = v_round.id;
end $function$
;

-- poll_track_start: samma två saker för omvalet efter en miss
CREATE OR REPLACE FUNCTION public.poll_track_start(p_room_id uuid)
 RETURNS rounds
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_p     public.pending_tracks;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_track  public.track_pool;
  v_bands  jsonb;
  v_url    text;
  v_req    bigint;
  v_bad_net boolean;
begin
  perform public._rate_limit('track_poll', 200, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  -- Medlemskap räcker (0077). Förut krävdes värd, vilket band hela
  -- tillståndsmaskinen till en enda flik: backgroundade värden den strypte
  -- mobilen timers och rundan stod still för alla andra.
  if not exists (
    select 1 from public.players p where p.room_id = p_room_id and p.user_id = v_uid
  ) then
    raise exception 'Du är inte med i rummet';
  end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  -- for update: två pollare får inte skicka var sin sökning för samma rad.
  select * into v_p from public.pending_tracks where room_id = p_room_id for update;
  if v_p.room_id is null then
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  if v_round.id is null or v_p.round_id <> v_round.id or v_round.current_track_id is not null then
    delete from public.pending_tracks where room_id = p_room_id;
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  select status_code, timed_out, content into v_status, v_timed, v_body
    from net._http_response where id = v_p.request_id;
  if not found then
    return null;
  end if;

  select * into v_track from public.track_pool where id = v_p.pool_id;

  v_bad_net := coalesce(v_status, 0) <> 200 or coalesce(v_timed, false);
  v_url := null;
  if not v_bad_net then
    v_url := public._itunes_pick(v_body, v_track.title, v_track.artist);
  end if;

  if v_url is not null then
    update public.rounds
      set current_track_id = v_url,
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id
      returning * into v_round;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text,
                               'genre', public._genre_key(v_track.genre),
                               'sv', v_track.sv))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;

    update public.track_pool
      set preview_url = v_url, preview_checked_at = now()
      where id = v_track.id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  if v_bad_net then
    if v_p.net_retries >= 1 then
      delete from public.pending_tracks where room_id = p_room_id;
      raise exception 'Kunde inte nå musiktjänsten just nu (%) – vänta en stund och försök igen.',
        case when coalesce(v_timed, false) then 'timeout' else 'svar ' || coalesce(v_status, 0)::text end;
    end if;
    v_req := net.http_get(
      url := case when v_p.search_stage = 1
                  then public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist)
                  else public._itunes_search_url(v_track.title || ' ' || v_track.artist) end,
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, net_retries = v_p.net_retries + 1 where room_id = p_room_id;
    return null;
  end if;

  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2, net_retries = 0 where room_id = p_room_id;
    return null;
  end if;

  -- Katalograder får ALDRIG nollställas här: de hittades inte via sökningen
  -- och kan inte verifieras den vägen, så en miss betyder ingenting om dem.
  -- _mark_unfindable() bär spärren (0071) – tidigare skrevs raden rakt av.
  perform public._mark_unfindable(v_p.pool_id);

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  -- Ersättaren hämtas på samma villkor som den första låten. Ett nytt anrop,
  -- inte det gamla värdet: den låt som föll bort kan ha varit den sista
  -- spelbara i sitt band, och då ska ersättaren komma från ett band som
  -- fortfarande har något att ge.
  v_bands := public._pool_bands(v_room.swedish_mode, v_room.year_bands, v_room.genres);

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_bands, v_room.genres)
        and (v_round.category is distinct from 'genre'
             or public._genre_key(tp.genre) is not null)
      and tp.id <> v_p.pool_id
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;
  if v_track.id is null then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  -- Samma undantag som start_random_track fick i 0071: katalograder har ingen
  -- hållbarhetsgräns. Utan det skickades de till sökningen efter 30 dagar.
  if v_track.preview_url is not null
     and (v_track.preview_source = 'catalog'
          or v_track.preview_checked_at > now() - interval '30 days') then
    update public.rounds
      set current_track_id = v_track.preview_url,
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id
      returning * into v_round;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text,
                               'genre', public._genre_key(v_track.genre),
                               'sv', v_track.sv))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1, net_retries = 0
    where room_id = p_room_id;
  return null;
end $function$
;
