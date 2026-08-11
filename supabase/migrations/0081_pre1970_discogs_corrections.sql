-- ====================================================================
--  LÅTSNURRAN – sju årtal till, rättade mot Discogs
--
--  Efter 0080 stod 67 av 0079:s låtar kvar på en enda källa: MusicBrainz
--  saknade singelutgåva för dem. Discogs har pressningarna – med land,
--  etikett och format – och har nu fått pröva alla 67.
--
--  METOD. Först utgåvor med rätt artist och rätt utgåvetitel, filtrerade
--  till 7"/singel; tidigaste året är då singelsläppet. Fanns ingen singel
--  (albumspår som "A Day in the Life") söktes spåret i stället. Vårt år är
--  liståret, så Discogs ett år före är väntat och ingen invändning.
--
--  UTFALL: 35 exakt samma år, 16 ett år före, alltså 51 bekräftade. 14 avvek
--  och 2 gav inget svar.
--
--  DE 14 GRANSKADES MOT PRESSNINGARNA, inte mot årtalet – samma sak som
--  avgjorde "Israelites" i 0080. Sju av dem är återutgåvor eller albumspår
--  där vårt år står sig: Big Joe Turners "Shake, Rattle and Roll" har bara
--  en Coral-pressning från 1964 i Discogs, men originalet på Atlantic är
--  från 1954; Beatles "A Day in the Life" och "Lucy in the Sky" är spår på
--  Sgt. Pepper (juni 1967) och de utländska singlarna kom efteråt; Cornelis
--  "Turistens klagan" har bara en DB-singel från 1978.
--
--  SJU ÄNDRAS. Discogs har en konkret pressning och vårt år hade inget alls
--  bakom sig – flera av dem var min egen uppskattning från början:
--
--    Leva livet              1966 -> 1963   4 pressningar, Karusell SE/DK/NO
--    So Many Girls           1965 -> 1966   7 pressningar, HMV UK + Platina
--    Calle Schewens vals     1960 -> 1956   2 pressningar, Columbia Sverige
--    Var är tvålen           1954 -> 1956   2 pressningar, Knäppupp
--    Så skimrande var...     1965 -> 1967   1 pressning, His Master's Voice
--    Naturbarn               1959 -> 1957   1 pressning, Knäppupp
--    Varm korv boogie        1957 -> 1959   1 pressning, Metronome
--
--  De fyra sista vilar på en eller två pressningar. Det är tunt, men det är
--  mer än det år de ersätter, som inte hade någon källa alls.
--
--  KVAR PÅ EN KÄLLA blir sex låtar: Sven-Ingvars "Två mörka ögon" och Evert
--  Taubes "Så länge skutan kan gå" (Discogs har inga daterade singlar alls),
--  Hep Stars "Speedy Gonzales" (bara en Olga-singel från 1969, men låten
--  ligger på debutalbumet 1965), samt "Aquarius / Let the Sunshine In" och
--  "Chris Craft No. 9" som sökningen inte fick svar på.
--
--  Rör bara track_pool.year. Redan spelade rundor har sitt facit i
--  round_tracks.meta och påverkas inte. Idempotent. Kör efter 0080.
-- ====================================================================

update public.track_pool tp set year = v.year
from (values
  ('Leva livet', 'Lill-Babs', 1963),
  ('So Many Girls', 'Tages', 1966),
  ('Calle Schewens vals', 'Evert Taube', 1956),
  ('Var är tvålen', 'Povel Ramel', 1956),
  ('Så skimrande var aldrig havet', 'Sven-Bertil Taube', 1967),
  ('Naturbarn', 'Povel Ramel', 1957),
  ('Varm korv boogie', 'Owe Thörnqvist', 1959)
) as v(title, artist, year)
where tp.title = v.title and tp.artist = v.artist and tp.year is distinct from v.year;

notify pgrst, 'reload schema';
