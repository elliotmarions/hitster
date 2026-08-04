-- ====================================================================
--  0048  Rättade utgivningsår i den befintliga potten
-- --------------------------------------------------------------------
--  De 250 svenska låtarna i 0025 är handkurerade, och 15 av dem har
--  årtal som inte stämmer. I ett spel där ÅRET ÄR SVARET är det inte ett
--  skönhetsfel: spelare döms fel varje gång låten dyker upp i "Exakt årtal"
--  eller "Årtal ±3".
--
--  Upptäckt när Sverigetopplistans veckoarkiv skrapades för pottutökningen
--  (0047). Listan och potten var oense om 15 låtar. MusicBrainz fick
--  avgöra som oberoende tredje part – och gav listan rätt i samtliga.
--
--  BEVISKRAV: ett år ändras bara när BÅDA de oberoende källorna säger emot
--  potten och är överens med varandra inom ±1 år. Listans år måste dessutom
--  ha en debutrun på minst 3 listveckor, annars kan det vara en streaming-
--  återkomst i stället för släppåret.
--
--  12 rader rättas här. 3 lämnas orörda för manuell koll:
--    Magnus Uggla – Kung för en dag: potten 1986, lista 1997, MB 1992
--    Roxette – It Must Have Been Love: potten 1990, lista 1987, MB 1992
--    Håkan Hellström – En midsommarnattsdröm: potten 2000, lista 2005, MB 2013
--
--  Rör bara track_pool.year. Redan spelade rundor har sitt facit sparat i
--  round_tracks.meta och påverkas inte. Idempotent. Kör efter 0046.
-- ====================================================================

update public.track_pool tp set year = v.year
from (values
  ('Ljudet av ett annat hjärta','Gyllene Tider',1981),
  ('747','Kent',1998),
  ('Here I Go Again','E-Type',1998),
  ('Calleth You, Cometh I','The Ark',2002),
  ('Måndagsbarn','Veronica Maggio',2008),
  ('Stockholm','Orup',1992),
  ('I samma bil','Bo Kaspers Orkester',2006),
  ('Logiskt','Petter',2007),
  ('Elegi','Lars Winnerbäck',2004),
  ('Nu kan du få mig så lätt','Håkan Hellström',2001),
  ('Alla som inte dansar','Maskinen',2007),
  ('17 år','Veronica Maggio',2009)
) as v(title, artist, year)
where tp.sv and tp.title = v.title and tp.artist = v.artist;
