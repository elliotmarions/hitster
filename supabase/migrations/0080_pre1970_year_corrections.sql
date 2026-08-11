-- ====================================================================
--  LÅTSNURRAN – tre årtal ur 0079 rättade mot MusicBrainz
--
--  0079:s årtal var listår ur en enda källa: min egen sammanställning.
--  Alla 415 har nu prövats mot MusicBrainz, och då mot RÄTT ingång:
--  release-group av typen Single. First-release-date på INSPELNING duger
--  inte för eran – den pekar på tidigaste utgåva MB känner till för just
--  den inspelningsentiteten, alltså nästan alltid en samling ("Mona Lisa"
--  blir 1986). Singel-ingången provkördes först mot tio låtar med känt
--  facit: 8 exakt, 1 ett år ifrån, 1 utan data.
--
--  UTFALL: 296 exakt samma år, 24 där MB ligger ett år före (väntat –
--  vårt år är liståret och en decembersingel blir hit året efter). 320 av
--  415 är alltså bekräftade av två oberoende källor. 67 saknar singeldata
--  i MB och står kvar på en källa.
--
--  28 avvek med två år eller mer. Var och en har granskats mot vad MB
--  FAKTISKT har, inte bara mot årtalet, och 25 av dem är samma sak: MB
--  känner ingen originalsingel, bara en återutgåva. "Come Together" som
--  singel 2019, "La Bamba" 1987, "White Room" 1989. Där står vårt år kvar.
--  Tre av dem bekräftade tvärtom vårt år när hela listan syntes: MB har
--  både 1951 och 1958 för "It's All in the Game" (hiten var
--  nyinspelningen 1958), 1963 års EP för "Twist and Shout", och 1964 års
--  album för "Oh, Pretty Woman".
--
--  KVAR BLIR TRE, alla svenska och alla där mitt årtal var det svagaste i
--  hela satsen. MB har singeln, och ingenting från året jag angav:
--
--    Tunna skivor            1959 -> 1960   MB: 1960 singel + 1960 EP
--    Mamma är lik sin mamma  1965 -> 1968   MB: 1968 singel
--    Gabrielle               1969 -> 1964   MB: 1964 singel + 1965 singel
--
--  EN STÅR KVAR MED FRÅGETECKEN. MB daterar Desmond Dekkers "Israelites"
--  till en singel 1966. Låten spelades in 1968 och blev etta i
--  Storbritannien i april 1969, vilket är vårt år; MB:s 1966 rimmar illa
--  med att Dekker slog igenom med "007 (Shanty Town)" 1967. Jag ändrar
--  inte på en källa som motsäger sig själv – raden lämnas på 1969.
--
--  Rör bara track_pool.year. Redan spelade rundor har sitt facit i
--  round_tracks.meta och påverkas inte. Idempotent. Kör efter 0079.
-- ====================================================================

update public.track_pool tp set year = v.year
from (values
  ('Tunna skivor', 'Siw Malmkvist', 1960),
  ('Mamma är lik sin mamma', 'Siw Malmkvist', 1968),
  ('Gabrielle', 'Hootenanny Singers', 1964)
) as v(title, artist, year)
where tp.title = v.title and tp.artist = v.artist and tp.year is distinct from v.year;

notify pgrst, 'reload schema';
