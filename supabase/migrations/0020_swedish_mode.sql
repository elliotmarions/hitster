-- =====================================================================
--  LÅTSNURRAN – Spelläge "Svenskt läge" (bara svenska låtar)
--
--  Ny rums-inställning swedish_mode (på/av, som suddregel/lagläge). När den är
--  PÅ använder klienten den svenska låtpotten (src/data/swedishTracks.js) i
--  stället för den vanliga. Rent klient-styrt val av pott – ingen server-logik
--  behöver ändras, bara flaggan lagras och speglas i realtid till alla.
--
--  Värden togglar den direkt (RLS rooms_update_host tillåter host att uppdatera
--  sitt rum). Additiv + idempotent. Kör efter 0019.
-- =====================================================================

alter table public.rooms
  add column if not exists swedish_mode boolean not null default false;

notify pgrst, 'reload schema';
