-- =====================================================================
--  LÅTSNURRAN – radera sitt konto själv
--
--  Appen har aldrig haft någon väg ut. Man kunde skapa konto, byta namn och
--  byta lösenord, men inte försvinna – och för en tjänst som lagrar e-post
--  och matchstatistik är det inte rimligt. Klienten kan inte göra det själv:
--  anon-nyckeln har ingen åtkomst till auth.users, så det måste ske här.
--
--  ALLT PERSONLIGT HÄNGER REDAN PÅ auth.users MED `on delete cascade`.
--  Kontrollerat i migrationerna, samtliga sex referenser:
--
--    rooms.host_user_id       0001   rummen man varit värd för
--    players.user_id          0001   ens spelar-rader (och därmed brickorna)
--    bingo_cards.user_id      0002   brickorna
--    round_answers.user_id    0006   svaren
--    player_stats.user_id     0008   statistiken
--    team_messages.user_id    0026   det man skrivit i lagchatten
--
--  En rad i auth.users räcker alltså – resten följer med av sig självt.
--
--  KONSEKVENS VÄRD ATT VETA OM: rooms.host_user_id kaskaderar också, så rum
--  man varit VÄRD för raderas, inklusive ett som pågår just nu. Det är rätt
--  beteende för en radering (rummet är ens eget), men det ska stå i rutan som
--  frågar, inte upptäckas efteråt av gänget som satt och spelade. Rum man bara
--  DELTAGIT i lever vidare utan en, precis som när man lämnar ett rum.
--
--  Kvar blir en rad i public.rate_limits (den har ingen FK – tabellen är
--  unlogged och städas av pg_cron). Den innehåller ett id, en hink och en
--  räknare, inget om personen.
--
--  Taket 3 per timme är inte till för att skydda mot en angripare – man kan
--  bara radera sig själv, och lyckas det finns inget att göra en andra gång.
--  Det är en spärr mot en klient som råkar loopa.
-- =====================================================================

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Du är inte inloggad.';
  end if;

  perform public._rate_limit('delete_account', 3, interval '1 hour');

  -- Kaskaderna ovan gör resten. Efter det här är sessionens token utan
  -- användare, så klienten måste logga ut och börja om som gäst.
  delete from auth.users where id = v_uid;
end;
$$;

-- Default privileges är återkallade sedan 0023 – varje ny funktion måste ge
-- sin egen execute-rätt.
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

notify pgrst, 'reload schema';
