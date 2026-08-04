-- ====================================================================
--  0053  Bort med dubbletter där filmtiteln står före låttiteln
-- --------------------------------------------------------------------
--  Samma sort som 0052. Låten ligger två gånger: en gång under sin egen
--  titel och en gång som "Filmnamn (Låttitel)". Dedup-nyckeln kapar bara
--  dekorationer EFTER titeln, aldrig ett påhäng före, så paren slapp
--  förbi både 0038 och det unika indexet.
--
--  Raden med filmnamnet är den som ska bort: i kategorin "låttitel" är
--  dess facit inte låtens titel, och ingen spelare kan gissa den.
--
--  LISTAN ÄR EXPLICIT, INTE ETT MÖNSTER. Formen "X (Y)" matchar 237
--  rader i potten och nästan alla är korrekta titlar med undertitel –
--  "Sweet Dreams (Are Made of This)", "Blue (Da Ba Dee)", "Single Ladies
--  (Put a Ring on It)". Ett regex här hade tömt potten på riktiga låtar.
--
--  UNDANTAG som ser ut som mönstret men INTE tas bort:
--    Cyndi Lauper – "Hey Now (Girls Just Want to Have Fun)" (1994) är en
--    egen nyinspelning, skild från originalet 1983. Båda ska ligga kvar.
--
--  Where-satsen kräver dessutom att den rena raden finns kvar för samma
--  artist. Skulle en av dem saknas raderas ingenting för den låten – vi
--  kan inte råka radera bort låten helt.
--
--  ETT ÅR ATT TA OM HAND: Eric Clapton – raden som försvinner har 1996,
--  den som blir kvar har 1999. "Change the World" är från Phenomenon-
--  soundtracket 1996, så det är sannolikt den ÖVERLEVANDE raden som har
--  fel år. Rättas inte här – den ligger i årsrevisionens hög och ska
--  avgöras mot två källor som allt annat.
--
--  Idempotent. Kör efter 0052.
-- ====================================================================

delete from public.track_pool tp
 using (values
   ('Bodyguard (I Will Always Love You)',            'I Will Always Love You',      'Whitney Houston'),
   ('Beverly Hills Cop (Axel F)',                    'Axel F',                      'Harold Faltermeyer'),
   ('A Star Is Born (Always Remember Us This Way)',  'Always Remember Us This Way', 'Lady Gaga'),
   ('Coyote Ugly (Can''t Fight The Moonlight)',      'Can''t Fight The Moonlight',  'LeAnn Rimes'),
   ('Notting Hill (When You Say Nothing At All)',    'When You Say Nothing At All', 'Ronan Keating'),
   ('Suicide Squad (Heathens)',                      'Heathens',                    'Twenty One Pilots'),
   ('Requiem for a Dream (Lux Aeterna)',             'Lux Aeterna',                 'Clint Mansell'),
   ('Bang A Gong (Get It On)',                       'Get It On',                   'T. Rex'),
   -- samma låt en gång till, men artisten stavad utan mellanslag ("T.Rex").
   -- Stavningsvarianten är också skälet till att dedup-nyckeln aldrig såg paret.
   ('Bang A Gong (Get It On)',                       'Get It On',                   'T.Rex'),
   ('Saturday Night Fever (Night Fever)',            'Night Fever',                 'Bee Gees'),
   ('Phenomenon (Change the World)',                 'Change the World',            'Eric Clapton')
 ) as v(filmtitel, lattitel, artist)
 where tp.title = v.filmtitel
   and tp.artist = v.artist
   -- skyddsnät: bara om den rena raden faktiskt finns kvar. Artisten jämförs
   -- utan punkter och mellanslag, annars räknas "T.Rex" och "T. Rex" som två
   -- olika artister och raden hade blivit kvar.
   and exists (
         select 1 from public.track_pool ren
         where ren.title = v.lattitel
           and replace(replace(lower(ren.artist), '.', ''), ' ', '')
             = replace(replace(lower(v.artist),   '.', ''), ' ', '')
       );
