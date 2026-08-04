-- ====================================================================
--  0052  Bort med dubbletten "Pretty Woman (It Must Have Been Love)"
-- --------------------------------------------------------------------
--  Raden är samma inspelning som Roxettes "It Must Have Been Love"
--  (1990), som redan ligger i båda potterna. Titeln har filmnamnet
--  klistrat framför sig, och _track_dedup_key kapar bara dekorationer
--  som "- Radio Edit" – inte ett påhäng före själva titeln. Därför
--  slapp den igenom 0038:s dubblettjakt och det unika indexet.
--
--  Varför den måste bort och inte bara får ligga:
--   * samma låt kan dras två gånger i samma spel
--   * i kategorin "låttitel" är facit "Pretty Woman (It Must Have Been
--     Love)" – ett svar ingen spelare kan gissa, eftersom det inte är
--     låtens titel
--   * 0050 rättade året på "It Must Have Been Love" i båda potterna men
--     kunde inte nå den här raden, så den drar isär årtalen på nytt vid
--     nästa rättning
--
--  SÄKERT ATT RADERA: round_tracks.pool_id är `on delete set null` och
--  facit för spelade rundor ligger i round_tracks.meta. Kontrollerat före
--  körning: raden har aldrig dragits i en runda (0 träffar).
--
--  Elva rader till har samma mönster (filmtitel + låttitel). De lämnas
--  orörda här – två av dem är inte dubbletter utan egna inspelningar,
--  t.ex. Cyndi Laupers "Hey Now (Girls Just Want to Have Fun)" från 1994.
--  De kräver samma individuella koll som årsrevisionens kandidater.
--
--  Idempotent. Kör efter 0051.
-- ====================================================================

delete from public.track_pool
 where title = 'Pretty Woman (It Must Have Been Love)'
   and artist = 'Roxette';
