-- =====================================================================
--  LÅTSNURRAN – Hela laget ser lagets eget svar före avslöjandet
--
--  answers_select (0006) släppte igenom på user_id = auth.uid(), alltså den
--  som LÅSTE. I lagläge är det bara kaptenen. Övriga i laget fick ingen rad
--  alls, och AnswerPanel tolkar en saknad rad som "inget svar": lagkompisen
--  läste "LÅST – inget svar —" medan kaptenen såg sitt "1985" i samma ruta.
--
--  Svaret är lagets, inte kaptenens. De har dessutom just resonerat sig fram
--  till det i lagchatten, så det finns inget att skydda dem från. Policyn
--  släpper nu igenom hela laget på lagets egen rad.
--
--  Motståndarnas rader är orörda: villkoret kräver att MIN spelar-rad i
--  samma rum har samma team_id som svarsraden. Solo-rader har team_id null
--  och faller inte in under det nya villkoret alls.
--
--  Additiv + idempotent. Kör efter 0059.
-- =====================================================================

-- Mitt lag i ett givet rum. SECURITY DEFINER av samma skäl som
-- is_room_member (0001): funktionen används inne i en RLS-policy och ska
-- inte själv behöva passera RLS på players för att svara.
create or replace function public._my_team(p_room uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select team_id
    from public.players
   where room_id = p_room and user_id = auth.uid()
$$;

drop policy if exists answers_select on public.round_answers;
create policy answers_select on public.round_answers
  for select to authenticated using (
    public.is_room_member(room_id)
    and (
      -- Mitt eget svar (solo, och kaptenens egen rad).
      user_id = auth.uid()
      -- Mitt lags svar – oavsett vem i laget som råkade låsa in det.
      or (team_id is not null and team_id = public._my_team(room_id))
      -- Allas svar, när rundan väl är avslöjad.
      or exists (
        select 1 from public.rounds r
        where r.id = round_id and r.answers_revealed
      )
    )
  );

grant execute on function public._my_team(uuid) to authenticated;

notify pgrst, 'reload schema';
