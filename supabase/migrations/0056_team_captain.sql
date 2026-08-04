-- ====================================================================
--  0056  Lagkapten: en utsedd svarare per lag
-- --------------------------------------------------------------------
--  PROBLEM: i lagläge fanns ingen utsedd svarare. Alla i laget såg varsin
--  skrivruta, skrev i sin egen webbläsare utan att se varandras text, och
--  den som råkade trycka "Lås in" först låste lagets svar. Raden skapas
--  direkt med locked = true, så de övrigas text kastades tyst – utan att de
--  fick veta om det. Två lagkamrater kunde alltså kapplöpa om samma svar.
--
--  LÖSNING: varje lag får en kapten (teams.captain_id) som är den enda som
--  kan låsa lagets svar. Övriga resonerar i lagchatten, som redan finns
--  just för det.
--
--  DEGRADERING: saknas kapten – eller har kaptenen lämnat laget mitt i
--  matchen – får vem som helst i laget låsa igen. Annars hade laget kunnat
--  bli helt låst ute från att svara, vilket är värre än en kapplöpning.
--  Därför "effektiv kapten": captain_id räknas bara om den spelaren
--  fortfarande står i laget.
--
--  assign_player håller kolumnen i synk: den som placeras i ett lag utan
--  kapten blir kapten, och flyttas kaptenen bort utses en kvarvarande
--  lagkamrat automatiskt.
--
--  Kryssplaceringen (mark_cross) rörs INTE – där är först-till-kvarn
--  ofarligt sedan 0049, eftersom krysset går att flytta inom samma runda.
--
--  Additiv + idempotent. Kör efter 0049.
-- ====================================================================

-- --- 1. kolumnen ---
alter table public.teams
  add column if not exists captain_id uuid references public.players (id) on delete set null;

-- --- 2. effektiv kapten: bara giltig om spelaren står kvar i laget ---
create or replace function public._team_captain(p_team_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
    from public.teams t
    join public.players p on p.id = t.captain_id and p.team_id = t.id
   where t.id = p_team_id
$$;

-- --- 3. värden utser kapten ---
create or replace function public.set_team_captain(
  p_room_id uuid, p_team_id uuid, p_player_id uuid)
returns void
language plpgsql security definer set search_path = public
as $function$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  perform public._rate_limit('team_admin', 60, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan utse lagkapten'; end if;
  if not exists (select 1 from public.teams where id = p_team_id and room_id = p_room_id) then
    raise exception 'Laget finns inte i rummet';
  end if;
  -- p_player_id null = ta bort kaptenen (laget faller tillbaka på fri turordning)
  if p_player_id is not null and not exists (
    select 1 from public.players
     where id = p_player_id and room_id = p_room_id and team_id = p_team_id
  ) then
    raise exception 'Spelaren är inte med i det laget';
  end if;

  update public.teams set captain_id = p_player_id where id = p_team_id;
end;
$function$;

-- --- 4. assign_player håller kaptenen i synk ---
create or replace function public.assign_player(
  p_room_id uuid, p_player_id uuid, p_team_id uuid)
returns void
language plpgsql security definer set search_path = public
as $function$
declare
  v_uid      uuid := auth.uid();
  v_room     public.rooms;
  v_gammalt  uuid;
begin
  perform public._rate_limit('team_admin', 60, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan dela in lag'; end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams where id = p_team_id and room_id = p_room_id
  ) then
    raise exception 'Laget finns inte i rummet';
  end if;

  select team_id into v_gammalt from public.players
    where id = p_player_id and room_id = p_room_id;

  update public.players set team_id = p_team_id
    where id = p_player_id and room_id = p_room_id;

  -- Lämnade spelaren ett lag där hen var kapten? Utse en kvarvarande.
  if v_gammalt is not null and v_gammalt is distinct from p_team_id then
    update public.teams t
       set captain_id = (
         select p.id from public.players p
          where p.team_id = t.id and p.id <> p_player_id
          order by p.joined_at, p.id limit 1)
     where t.id = v_gammalt and t.captain_id = p_player_id;
  end if;

  -- Kom spelaren till ett lag som saknar kapten? Då blir hen det.
  if p_team_id is not null then
    update public.teams set captain_id = p_player_id
      where id = p_team_id and public._team_captain(id) is null;
  end if;
end;
$function$;

-- --- 5. bara kaptenen låser lagets svar ---
create or replace function public.lock_answer(p_room_id uuid, p_answer text)
returns public.round_answers
language plpgsql security definer set search_path = public
as $function$
declare
  v_uid      uuid := auth.uid();
  v_room     public.rooms;
  v_player   public.players;
  v_round    public.rounds;
  v_ans      public.round_answers;
  v_locked   int;
  v_total    int;
  v_revealed boolean;
  v_kapten   uuid;
begin
  perform public._rate_limit('answer', 30, interval '1 minute');
  if length(coalesce(p_answer, '')) > 300 then
    raise exception 'Svaret är för långt (max 300 tecken)';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1
    for update;
  if v_round.id is null then raise exception 'Ingen runda är igång'; end if;
  if v_round.current_track_id is null or v_round.timer_start_at is null then
    raise exception 'Ingen låt har spelats än';
  end if;
  if now() < v_round.timer_start_at - interval '1 second' then
    raise exception 'Vänta tills låten börjat spela';
  end if;

  if v_room.team_mode then
    if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;

    -- NYTT: har laget en kapten som fortfarande är kvar är hen ensam om att
    -- få låsa. Saknas kapten faller laget tillbaka på fri turordning.
    v_kapten := public._team_captain(v_player.team_id);
    if v_kapten is not null and v_kapten <> v_player.id then
      raise exception 'Bara lagkaptenen låser in lagets svar';
    end if;

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
$function$;

-- --- 6. befintliga lag utan kapten får en, så inget rum står utan ---
update public.teams t
   set captain_id = (
     select p.id from public.players p
      where p.team_id = t.id
      order by p.joined_at, p.id limit 1)
 where t.captain_id is null;

grant execute on function public.set_team_captain(uuid, uuid, uuid) to authenticated;
grant execute on function public.assign_player(uuid, uuid, uuid) to authenticated;
grant execute on function public.lock_answer(uuid, text) to authenticated;
grant execute on function public._team_captain(uuid) to authenticated;

notify pgrst, 'reload schema';
