-- ====================================================================
--  0045  server_now() – gemensam klocka för synkad uppspelning
-- --------------------------------------------------------------------
--  Alla klienter startar klippet vid rundans timer_start_at, men jämförde
--  den tidpunkten mot sin EGEN Date.now(). Enheters klockor går isär –
--  en surfplatta som legat i standby kan ligga flera sekunder fel – och då
--  hör den spelaren låten lika många sekunder före eller efter alla andra.
--
--  Klienten mäter nu sin klockavvikelse mot servern en gång per sidladdning
--  (src/lib/serverTime.js). Vi kan inte läsa HTTP:ns Date-header i stället:
--  den är inte CORS-safelistad och Supabase exponerar den inte.
--
--  stable + parameterlös: PostgREST exponerar den som RPC. now() ger
--  transaktionens starttid, vilket är gott och väl precist nog – felet
--  domineras ändå av halva rundturstiden.
--
--  Läcker ingenting (serverns klocka syns redan i timer_start_at). Additiv +
--  idempotent. Utan den här migrationen faller klienten tillbaka på sin egen
--  klocka = exakt det gamla beteendet.
-- ====================================================================

create or replace function public.server_now()
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select now()
$$;

grant execute on function public.server_now() to anon, authenticated;
