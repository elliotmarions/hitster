-- =====================================================================
--  LÅTSNURRAN – Bonusgissning på årtal ger sudd i varje runda
--
--  Suddregeln gällde bara när discokulan råkade landa på en årtalskategori,
--  alltså ungefär var femte runda. Nu: är suddregeln på och rundans kategori
--  INTE handlar om årtal (artist, låttitel, årtionde, före/efter) får varje
--  enhet dessutom gissa utgivningsåret i en liten extraruta. Prickar man året
--  får man sudda ett kryss hos någon annan – oavsett hur det gick på rundans
--  egen kategori.
--
--  TRE VAL (Elliots, 2026-08-05):
--
--   1. EXAKT årtal krävs, inte ±3. Sudd tar bort kryss, så en hög träffchans
--      varje runda skulle motverka att brickorna någonsin fylls. Exakt träff
--      ligger runt tio procent – ett litet firande, inte ett grundflöde.
--
--   2. OBEROENDE av huvudsvaret. Missar du artisten men prickar året får du
--      ändå sudda. Det är hela poängen: rutan ska betyda något i just de
--      rundor där man inte kan låten. Därför får erase_cross nu TVÅ vägar in,
--      och kravet "bara rätt svar får sudda" gäller per väg, inte globalt.
--
--   3. ETT sudd per runda och enhet (round_answers.has_erased). Fanns ingen
--      sådan spärr förut – sudd var sällsynt nog att ingen märkte att
--      funktionen kunde anropas om och om igen på samma runda. Med en
--      bonusruta i nästan varje runda blir det en verklig lucka, så den täpps
--      till här. Ett tomt eller redan suddat kryss förbrukar inte suddet.
--
--  Bonusrutan visas INTE på exact_year/approx_year/approx_year_1 – där är
--  huvudsvaret redan ett årtal och 0063 gäller som vanligt.
--
--  Klienten speglar reglerna i ERASE_CATEGORIES och AnswerPanel.
--  Additiv + idempotent. Kör efter 0063.
-- =====================================================================

-- --- 1. kolumner -----------------------------------------------------
alter table public.round_answers
  add column if not exists bonus_year   text not null default '',
  add column if not exists bonus_correct boolean,
  add column if not exists has_erased    boolean not null default false;

-- --- 2. lock_answer tar emot bonusgissningen -------------------------
--  Den gamla 2-argumentsvarianten släpps INTE kvar som egen funktion – två
--  funktioner där {p_room_id, p_answer} matchar båda är precis den
--  överlagringstvetydighet 0057 varnar för.
--
--  I stället har p_bonus ett DEFAULT. Det gör bytet driftsäkert oavsett i
--  vilken ordning databasen och Vercel-bygget hinner fram: en gammal klient
--  som skickar {p_room_id, p_answer} träffar samma funktion och får tom
--  bonus, i stället för "function not found" mitt i ett pågående spel.
drop function if exists public.lock_answer(uuid, text);

create or replace function public.lock_answer(p_room_id uuid, p_answer text, p_bonus text default '')
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
  v_bonus    text;
begin
  perform public._rate_limit('answer', 30, interval '1 minute');
  if length(coalesce(p_answer, '')) > 300 then
    raise exception 'Svaret är för långt (max 300 tecken)';
  end if;
  -- Bonusen är ett årtal, inget annat. Trimmas hårt så att inget långt
  -- fritextsvar kan smugglas in i kolumnen.
  v_bonus := left(trim(coalesce(p_bonus, '')), 10);

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

    v_kapten := public._team_captain(v_player.team_id);
    if v_kapten is not null and v_kapten <> v_player.id then
      raise exception 'Bara lagkaptenen låser in lagets svar';
    end if;

    select * into v_ans from public.round_answers
      where round_id = v_round.id and team_id = v_player.team_id;
    if v_ans.id is null then
      insert into public.round_answers (room_id, round_id, team_id, user_id, answer, bonus_year, locked)
      values (p_room_id, v_round.id, v_player.team_id, v_uid, coalesce(p_answer, ''), v_bonus, true)
      returning * into v_ans;
    elsif not v_ans.locked then
      update public.round_answers
        set answer = coalesce(p_answer, ''), bonus_year = v_bonus, locked = true, updated_at = now()
        where id = v_ans.id returning * into v_ans;
    end if;
    select count(*) into v_locked from public.round_answers where round_id = v_round.id and locked;
    select count(*) into v_total from public.teams where room_id = p_room_id;
  else
    insert into public.round_answers (room_id, round_id, player_id, user_id, answer, bonus_year, locked)
    values (p_room_id, v_round.id, v_player.id, v_uid, coalesce(p_answer, ''), v_bonus, true)
    on conflict (round_id, player_id) do update
      set answer = case when public.round_answers.locked then public.round_answers.answer
                        else excluded.answer end,
          bonus_year = case when public.round_answers.locked then public.round_answers.bonus_year
                            else excluded.bonus_year end,
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

-- --- 3. rättningen dömer även bonusen --------------------------------
--  Behåller pivot-injektionen från 0032. Bonusen döms med exact_year-regeln
--  mot samma facit-meta. null (inte false) när rutan inte var i spel, så
--  "gissade fel" och "fanns ingen ruta" går att skilja åt i UI:t.
create or replace function public._grade_round(p_round_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.round_answers ra
    set auto_correct = public._judge_answer(
          r.category, ra.answer,
          coalesce(rt.meta, r.current_track_meta, '{}'::jsonb)
            || jsonb_build_object('pivot', r.pivot_year)),
        bonus_correct = case
          when not coalesce(ro.erase_rule_enabled, false) then null
          when r.category = any(array['exact_year', 'approx_year', 'approx_year_1']) then null
          else public._judge_answer(
                 'exact_year', ra.bonus_year,
                 coalesce(rt.meta, r.current_track_meta, '{}'::jsonb))
        end
    from public.rounds r
    join public.rooms ro on ro.id = r.room_id
    left join public.round_tracks rt on rt.round_id = r.id
    where ra.round_id = p_round_id and r.id = p_round_id;
$$;

-- --- 4. erase_cross: två vägar in, ett sudd per runda ----------------
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
  v_year_cats constant text[] := array['exact_year', 'approx_year', 'approx_year_1'];
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
$function$;

grant execute on function public.lock_answer(uuid, text, text) to authenticated;
grant execute on function public.erase_cross(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
