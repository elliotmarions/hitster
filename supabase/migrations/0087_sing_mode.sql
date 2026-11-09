-- =====================================================================
--  LÅTSNURRAN – nytt spelläge "Sjung vidare"
--
--  Lagen turas om. Appen spelar början av en låt och tystnar mitt i; laget
--  som står på tur ska sjunga fortsättningen. Sedan spelar appen vidare
--  från samma ställe – det är facit, så inga låttexter behövs. De andra
--  lagen dömer Rätt/Fel (värden kan alltid döma). Först till N rätt vinner.
--
--  En tur är en vanlig rad i rounds (category = 'sing'), så låtvalet,
--  iTunes-uppslaget och facit-spärren i round_tracks återanvänds rakt av:
--  sing_next_turn skapar rundan och anropar start_random_track.
--
--  Poängen lagras INTE. Ett lags poäng = antalet rundor där laget stod på
--  tur och domen blev rätt. reset_game raderar rundorna, så "Spela igen"
--  nollar poängen utan att något annat behöver ändras.
--
--  Idempotent.
-- =====================================================================

-- ---------------------------------------------------------------- rooms
alter table public.rooms
  add column if not exists game_mode text not null default 'bingo';
alter table public.rooms drop constraint if exists rooms_game_mode_check;
alter table public.rooms
  add constraint rooms_game_mode_check check (game_mode in ('bingo', 'sing'));

alter table public.rooms
  add column if not exists sing_target smallint not null default 10;
alter table public.rooms drop constraint if exists rooms_sing_target_check;
alter table public.rooms
  add constraint rooms_sing_target_check check (sing_target in (5, 10, 15));

-- Lobbyns reglage skrivs direkt av värden (rooms_update_host). Kolumnlistan
-- i granten är hela skyddet, så nya kolumner måste läggas till uttryckligen.
grant update (game_mode, sing_target) on public.rooms to authenticated;

-- ---------------------------------------------------------------- rounds
alter table public.rounds
  add column if not exists sing_team_id uuid references public.teams (id) on delete set null,
  add column if not exists sing_cut_at numeric(4, 1),
  add column if not exists sing_reveal_at timestamptz,
  add column if not exists sing_verdict boolean;

alter table public.rounds drop constraint if exists rounds_category_check;
alter table public.rounds
  add constraint rounds_category_check check (category = any (array[
    'decade', 'artist', 'exact_year', 'approx_year', 'title', 'approx_year_1',
    'before_after', 'approx_year_5', 'genre', 'swedish', 'solo_group', 'sing'
  ]));

-- ---------------------------------------------------------------- hjälp
-- Lagen som deltar, i turordning. Ett lag utan spelare (alla lämnade) hoppas
-- över, annars skulle turen fastna hos ett tomt lag som ingen kan svara för.
create or replace function public._sing_teams(p_room_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(t.id order by t.sort, t.created_at, t.id), '{}')
    from public.teams t
   where t.room_id = p_room_id
     and exists (select 1 from public.players p where p.team_id = t.id);
$$;
revoke all on function public._sing_teams(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- RPC:er

-- Värden drar nästa låt. Turen går till nästa lag i ordningen. Föll förra
-- låtstarten (ingen låt hittades) görs ett nytt försök i SAMMA tur.
create or replace function public.sing_next_turn(p_room_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_prev  public.rounds;
  v_round public.rounds;
  v_teams uuid[];
  v_idx   int;
  v_team  uuid;
  v_num   int;
begin
  perform public._rate_limit('spin', 30, interval '1 minute');
  -- for update: två snabba klick får inte skapa två turer.
  select * into v_room from public.rooms where id = p_room_id for update;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan dra nästa låt'; end if;
  if v_room.game_mode <> 'sing' then raise exception 'Rummet spelar inte Sjung vidare'; end if;
  if v_room.status <> 'playing' then raise exception 'Spelet är inte igång'; end if;

  v_teams := public._sing_teams(p_room_id);
  if coalesce(array_length(v_teams, 1), 0) < 2 then
    raise exception 'Sjung vidare kräver minst två lag med spelare';
  end if;

  select * into v_prev from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  if v_prev.id is not null and v_prev.current_track_id is null then
    perform public.start_random_track(p_room_id);
    select * into v_round from public.rounds where id = v_prev.id;
    return v_round;
  end if;

  if v_prev.id is not null and v_prev.sing_verdict is null then
    raise exception 'Döm förra låten innan ni drar nästa';
  end if;

  if v_prev.id is null then
    v_team := v_teams[1];
  else
    v_idx := array_position(v_teams, v_prev.sing_team_id);
    v_team := v_teams[coalesce(v_idx, 0) % array_length(v_teams, 1) + 1];
  end if;

  select coalesce(max(round_number), 0) + 1 into v_num
    from public.rounds where room_id = p_room_id;

  -- Tystnaden slumpas mellan 9 och 15 sekunder in i klippet: tidigt nog för
  -- att lämna fortsättning att jämföra med, sent nog för att låten ska gå
  -- att känna igen.
  insert into public.rounds (room_id, round_number, category, spun_by, state, sing_team_id, sing_cut_at)
  values (p_room_id, v_num, 'sing', v_uid, 'loading', v_team, round((9 + random() * 6)::numeric, 1))
  returning * into v_round;

  perform public.start_random_track(p_room_id);
  select * into v_round from public.rounds where id = v_round.id;
  return v_round;
end $$;

-- Värden spelar facit: låten fortsätter där den tystnade och titeln visas
-- (answers_revealed öppnar round_tracks). Startar 1,5 s fram så att alla
-- enheter hinner få händelsen och börjar samtidigt.
create or replace function public.sing_reveal(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
begin
  perform public._rate_limit('answer_reveal', 30, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan spela facit'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1 for update;
  if v_round.id is null or v_round.category <> 'sing' then raise exception 'Ingen tur är igång'; end if;
  if v_round.current_track_id is null then raise exception 'Låten har inte startat än'; end if;
  if v_round.answers_revealed then return; end if;
  if now() < v_round.timer_start_at + make_interval(secs => v_round.sing_cut_at::double precision) then
    raise exception 'Vänta tills låten tystnat';
  end if;

  update public.rounds
    set answers_revealed = true,
        state = 'revealed',
        sing_reveal_at = now() + interval '1.5 seconds'
    where id = v_round.id;
end $$;

-- Domen. Får sättas av värden eller av någon i ett ANNAT lag än det som
-- sjöng – laget självt dömer inte sig självt. Domen kan ändras fram till att
-- matchen är avgjord; poängen räknas ur rundorna, så en ändring kan inte
-- dubbelräknas.
create or replace function public.sing_judge(p_room_id uuid, p_correct boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_me    public.players;
  v_score int;
begin
  perform public._rate_limit('answer_override', 60, interval '1 minute');
  if p_correct is null then raise exception 'Välj rätt eller fel'; end if;
  -- Låsordning som överallt annars: rooms före rounds.
  select * into v_room from public.rooms where id = p_room_id for update;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.game_mode <> 'sing' then raise exception 'Rummet spelar inte Sjung vidare'; end if;
  if v_room.status = 'finished' then raise exception 'Matchen är redan avgjord'; end if;

  select * into v_me from public.players where room_id = p_room_id and user_id = v_uid;
  if v_me.id is null then raise exception 'Du är inte med i rummet'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1 for update;
  if v_round.id is null or v_round.category <> 'sing' then raise exception 'Ingen tur är igång'; end if;
  if not v_round.answers_revealed then raise exception 'Spela facit innan ni dömer'; end if;

  if v_room.host_user_id <> v_uid and v_me.team_id is not distinct from v_round.sing_team_id then
    raise exception 'Ert eget lag sjöng – låt de andra döma';
  end if;

  update public.rounds set sing_verdict = p_correct where id = v_round.id;

  if p_correct then
    select count(*) into v_score from public.rounds
      where room_id = p_room_id and sing_team_id = v_round.sing_team_id and sing_verdict;
    if v_score >= v_room.sing_target then
      update public.rooms
        set status = 'finished',
            winner_team_id = v_round.sing_team_id,
            winner_unit_ids = jsonb_build_array(v_round.sing_team_id::text),
            winner_round_id = v_round.id
        where id = p_room_id;
    end if;
  end if;
end $$;

revoke all on function public.sing_next_turn(uuid) from public, anon;
revoke all on function public.sing_reveal(uuid) from public, anon;
revoke all on function public.sing_judge(uuid, boolean) from public, anon;
grant execute on function public.sing_next_turn(uuid) to authenticated;
grant execute on function public.sing_reveal(uuid) to authenticated;
grant execute on function public.sing_judge(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
