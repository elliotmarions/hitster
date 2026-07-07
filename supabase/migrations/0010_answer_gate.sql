-- =====================================================================
--  LÅTSNURRAN – Kryssa bara efter validerat (rätt) svar
--
--  Tidigare räknades ✓/✗ bara på klienten. Nu bedöms varje svar SERVER-SIDE
--  vid avslöjandet och lagras i round_answers.auto_correct → en enda sanning
--  för både visning och spärr. mark_cross/erase_cross tillåts bara om den egna
--  enhetens svar för rundan är validerat som rätt (override ?? auto).
--
--  Kräver fuzzystrmatch (levenshtein) för tolerant stavning. Additiv +
--  idempotent. Kör efter 0009.
-- =====================================================================

create extension if not exists fuzzystrmatch;

alter table public.round_answers
  add column if not exists auto_correct boolean;

-- --- Textnormalisering (speglar src/lib/validateAnswer.js) -----------
create or replace function public._norm_text(t text)
returns text language sql immutable as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(coalesce(t, '')), '\(.*?\)', ' ', 'g'),
          '\y(feat|ft|featuring|with)\y.*$', ' ', 'gi'),
        '[-–]\s*(remaster|remastered|mono|stereo|version|mix|edit|single|original|live|radio).*$', ' ', 'gi'),
      '[^[:alnum:] ]', ' ', 'g'),
    '\s+', ' ', 'g'))
$$;

-- --- Tolerant textmatch för artist/titel ----------------------------
create or replace function public._fuzzy_text(p_answer text, p_target text)
returns boolean language plpgsql immutable
set search_path = public, extensions as $$
declare
  na text := public._norm_text(p_answer);
  nt text := public._norm_text(p_target);
  atoks text[];
  ttoks text[];
  dist int;
begin
  if na = '' or nt = '' then return false; end if;
  if na = nt then return true; end if;
  if position(nt in na) > 0 or position(na in nt) > 0 then return true; end if;

  atoks := string_to_array(na, ' ');
  ttoks := string_to_array(nt, ' ');
  -- Alla betydande ord i facit finns i svaret (ordföljd spelar ingen roll).
  if (select bool_and(tok = any (atoks)) from unnest(ttoks) tok where length(tok) >= 2) then
    return true;
  end if;

  dist := levenshtein(na, nt);
  if dist <= 1 then return true; end if;
  return (1.0 - dist::numeric / greatest(length(na), length(nt))) >= 0.8;
end;
$$;

-- --- Bedöm ett svar mot facit för en kategori -----------------------
create or replace function public._judge_answer(p_cat text, p_answer text, p_meta jsonb)
returns boolean language plpgsql immutable as $$
declare
  fy int;
  y  int;
  d  int;
  dd text;
begin
  if p_answer is null or p_meta is null then return false; end if;
  fy := nullif(p_meta ->> 'year', '')::int;
  -- Icke-fångande grupp så hela året returneras (Postgres substring med
  -- parenteser returnerar annars bara första gruppen).
  y  := (substring(p_answer from '((?:19|20)\d{2})'))::int;

  if p_cat = 'exact_year' then
    return y is not null and fy is not null and y = fy;
  elsif p_cat = 'approx_year' then
    return y is not null and fy is not null and abs(y - fy) <= 3;
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

-- --- Bedöm alla svar i en runda (körs vid avslöjandet) --------------
create or replace function public._grade_round(p_round_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.round_answers ra
    set auto_correct = public._judge_answer(r.category, ra.answer, r.current_track_meta)
    from public.rounds r
    where ra.round_id = p_round_id and r.id = p_round_id;
$$;

-- --- lock_answer: betygsätt rundan när den avslöjas -----------------
create or replace function public.lock_answer(p_room_id uuid, p_answer text)
returns public.round_answers
language plpgsql security definer set search_path = public
as $$
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
  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
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
    set locked_count = v_locked, answers_revealed = (v_locked >= v_total)
    where id = v_round.id
    returning answers_revealed into v_revealed;

  if v_revealed then
    perform public._grade_round(v_round.id);
  end if;

  return v_ans;
end;
$$;

-- --- reveal_answers: betygsätt rundan vid tvångsavslöjande ----------
create or replace function public.reveal_answers(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan avslöja svaren'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;

  update public.rounds set answers_revealed = true where id = v_round.id;
  perform public._grade_round(v_round.id);
end;
$$;

-- --- mark_cross: nu bara efter validerat RÄTT svar ------------------
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

  -- SPÄRR: när en låt spelats får man kryssa först efter att svaren avslöjats
  -- OCH bara om den egna enhetens svar var rätt (auto eller värdens override).
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

  if v_won then
    if v_room.team_mode then
      select name into v_label from public.teams where id = v_player.team_id;
      update public.rooms set status = 'finished', winner_team_id = v_player.team_id, winner_player_id = null
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'GAME_WIN', jsonb_build_object('team_id', v_player.team_id, 'display_name', v_label));
    else
      update public.rooms set status = 'finished', winner_player_id = v_player.id
        where id = p_room_id;
      insert into public.room_events (room_id, type, payload)
      values (p_room_id, 'GAME_WIN', jsonb_build_object('player_id', v_player.id, 'display_name', v_player.display_name));
    end if;
  end if;

  return v_card;
end;
$$;

-- --- erase_cross: suddregeln kräver nu också validerat RÄTT svar ----
create or replace function public.erase_cross(p_room_id uuid, p_target_card uuid, p_cell int)
returns public.bingo_cards
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_round  public.rounds;
  v_card   public.bingo_cards;
  v_myans  public.round_answers;
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

  -- SPÄRR: sudd kräver att din egen enhet gissat rätt (avslöjat + rätt).
  if not v_round.answers_revealed then
    raise exception 'Vänta tills svaren avslöjats innan du suddar';
  end if;
  if v_room.team_mode then
    select * into v_myans from public.round_answers where round_id = v_round.id and team_id = v_player.team_id;
  else
    select * into v_myans from public.round_answers where round_id = v_round.id and player_id = v_player.id;
  end if;
  if coalesce(v_myans.override_correct, v_myans.auto_correct) is not true then
    raise exception 'Bara rätt svar får sudda';
  end if;

  select * into v_card from public.bingo_cards where id = p_target_card and room_id = p_room_id;
  if v_card.id is null then raise exception 'Brickan finns inte'; end if;
  if v_room.team_mode then
    if v_card.team_id = v_player.team_id then raise exception 'Du kan inte sudda på ditt eget lags bricka'; end if;
  else
    if v_card.player_id = v_player.id then raise exception 'Du kan inte sudda på din egen bricka'; end if;
  end if;

  if p_cell < 0 or p_cell > 24 then raise exception 'Ogiltig ruta'; end if;
  if not ((v_card.grid -> p_cell ->> 'filled')::boolean) then return v_card; end if;

  v_grid := jsonb_set(v_card.grid, array[p_cell::text, 'filled'], 'false'::jsonb);
  update public.bingo_cards set grid = v_grid, has_won = false
    where id = v_card.id returning * into v_card;

  insert into public.room_events (room_id, type, payload)
  values (p_room_id, 'CROSS_ERASED',
          jsonb_build_object('by', v_player.display_name, 'target_card', p_target_card, 'cell', p_cell));
  return v_card;
end;
$$;

notify pgrst, 'reload schema';
