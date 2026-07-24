-- =====================================================================
--  LÅTSNURRAN – "Före eller efter?" som femte kategori i åldersläge
--
--  En vattentät auto-kategori: släpptes låten före eller efter ett givet
--  pivot-år? Året är känt (kurerad pott) → kan aldrig dömas fel. Pivoten
--  slumpas per runda i erans mittersta halva (balanserad 50/50-gissning,
--  inte lärbar) och lagras publikt i rounds.pivot_year – till skillnad från
--  facit-året, som ligger kvar bakom reveal-spärren i round_tracks.
--
--  Åldersläget går därmed från fyra till fem kategorier:
--      exact_year · artist · title · approx_year_1 · before_after
--
--  Pivoten når bedömningen genom att _grade_round injicerar den i facit-metan
--  (ingen signaturändring på _judge_answer). MÅSTE spegla frontendens
--  AGE_CATEGORY_ORDER. Additiv + idempotent. Kör efter 0031.
-- =====================================================================

-- Publikt pivot-år (bara satt för before_after-rundor; synligt före reveal).
alter table public.rounds
  add column if not exists pivot_year int;

-- ====================================================================
--  Kategori-set: åldersläge får nu fem (lägg till before_after)
-- ====================================================================
create or replace function public._room_categories(p_year_min int, p_year_max int)
returns text[] language sql immutable set search_path = public as $$
  select case
    when p_year_min is not null or p_year_max is not null
      then array['exact_year', 'artist', 'title', 'approx_year_1', 'before_after']
    else array['decade', 'artist', 'exact_year', 'approx_year', 'title']
  end;
$$;

-- ====================================================================
--  Svarsbedömning: lägg till before_after (pivot läses ur metan)
-- ====================================================================
create or replace function public._judge_answer(p_cat text, p_answer text, p_meta jsonb)
returns boolean language plpgsql immutable set search_path = public as $$
declare
  fy int;
  y  int;
  d  int;
  dd text;
  pv int;
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
  elsif p_cat = 'before_after' then
    -- 'efter' = pivot-året eller senare; 'före' = tidigare än pivoten.
    return fy is not null and pv is not null and (
         (lower(p_answer) = 'efter' and fy >= pv)
      or (lower(p_answer) = 'före'  and fy <  pv)
    );
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
--  Rättning: injicera rundans pivot i metan så bedömningen ser den
--  (behåller fallback till gamla current_track_meta för gamla rundor)
-- ====================================================================
create or replace function public._grade_round(p_round_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.round_answers ra
    set auto_correct = public._judge_answer(
          r.category, ra.answer,
          coalesce(rt.meta, r.current_track_meta, '{}'::jsonb)
            || jsonb_build_object('pivot', r.pivot_year))
    from public.rounds r
    left join public.round_tracks rt on rt.round_id = r.id
    where ra.round_id = p_round_id and r.id = p_round_id;
$$;

-- ====================================================================
--  spin_wheel: sätt pivot_year när kategorin blir before_after
--  (kopia av 0031 + pivot-beräkning)
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
  v_lo    int;
  v_hi    int;
  v_pivot int;
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

  -- Pivot-år för "Före eller efter": slumpa i erans mittersta halva så det blir
  -- en balanserad gissning. year_min finns alltid i åldersläge; year_max kan
  -- vara null (20–29 = öppet uppåt) → övre gräns = innevarande år.
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
end $$;

grant execute on function public.spin_wheel(uuid) to authenticated;

notify pgrst, 'reload schema';
