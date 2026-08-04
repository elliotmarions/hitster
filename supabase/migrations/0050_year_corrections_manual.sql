-- ====================================================================
--  0050  De tre årtal som 0048 lämnade för manuell koll
-- --------------------------------------------------------------------
--  0048 rättade 12 av 15 tvistiga årtal och parkerade tre där
--  Sverigetopplistan och MusicBrainz inte var överens med varandra.
--  Här avgörs de tre – med iTunes (samma katalog som appen spelar
--  klippen ur) som tredje oberoende källa.
--
--  1) Magnus Uggla – Kung för en dag    1986 → 1997   RÄTTAS
--     Låten ligger på albumet "Karaoke". MusicBrainz release-group för
--     "Karaoke" har first-release 1997, och tre av fyra MB-inspelningar
--     av låten pekar på 1997 – samma år som listan. Potten 1986 saknar
--     stöd i varje källa; 1986 är året för "Den döende dandyn", ett
--     annat Uggla-album. MB:s enstaka 1992 är en avvikare mot tre 1997.
--
--  2) Håkan Hellström – En midsommarnattsdröm   2000 → 2005   RÄTTAS
--     iTunes: albumet "Ett kolikbarns bekännelser" (2005) och singeln
--     "En midsommarnatts dröm" (2005). MB: tidigaste konkreta release
--     2005-01-14. Listan sa också 2005 – tre källor, samma år.
--     0048:s "MB 2013" var en senare utgåva, inte debuten. Potten 2000
--     är debutalbumets år ("Känn ingen sorg för mig Göteborg"), inte
--     den här låtens.
--
--  3) Roxette – It Must Have Been Love   1990   ORÖRD (medvetet)
--     Här är källorna inte oense om ETT år – de beskriver två olika
--     inspelningar. 1987 är julversionen "It Must Have Been Love
--     (Christmas for the Broken-Hearted)" (MB har den som 1986/1988);
--     1990 är nyinspelningen till Pretty Woman, den som alla känner
--     igen och den som står på Hitster-kortet. Potten spelar den
--     senare, alltså stannar 1990. Ingen ändring.
--
--  Samma beviskrav som 0048: ett år ändras bara när minst två oberoende
--  källor säger emot potten och är överens med varandra.
--
--  Rör bara track_pool.year. Redan spelade rundor har sitt facit i
--  round_tracks.meta och påverkas inte. Idempotent. Kör efter 0048.
-- ====================================================================

update public.track_pool tp set year = v.year
from (values
  ('Kung för en dag','Magnus Uggla',1997),
  ('En midsommarnattsdröm','Håkan Hellström',2005)
) as v(title, artist, year)
where tp.sv and tp.title = v.title and tp.artist = v.artist;
