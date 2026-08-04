-- ====================================================================
--  0054  Filmnamnet ur låttiteln
-- --------------------------------------------------------------------
--  FÖRBEREDD, INTE KÖRD. Läs igenom listorna innan du kör.
--
--  0052 och 0053 tog bort de rader där filmnamnet stod före låttiteln
--  OCH låten redan fanns i ren form. Kvar står de som bara finns med
--  filmnamnet – där radering skulle ta bort låten ur potten helt. De
--  döps om i stället.
--
--  Varför det spelar roll: "låttitel" är en av fem svarskategorier. Med
--  facit "8 Mile (Lose Yourself)" kan ingen spelare svara rätt, och den
--  automatiska rättningen har inget att matcha mot.
--
--  LISTORNA ÄR EXPLICITA. Formen "X (Y)" matchar 237 rader i potten och
--  nästan alla är korrekta titlar med undertitel – "Sweet Dreams (Are
--  Made of This)", "Blue (Da Ba Dee)", "Single Ladies (Put a Ring on
--  It)". Varje rad nedan är enskilt bedömd.
--
--  ORDNINGEN VARIERAR i källdatan: ibland står filmen först och låten i
--  parentesen ("Gladiator (Now We Are Free)"), ibland tvärtom ("Tara's
--  Theme (Gone with the Wind)"). Därför går det inte att skala bort
--  parentesen mekaniskt – nya titeln står utskriven för varje rad.
--
--  LÄMNAS ORÖRDA, ser ut som mönstret men är riktiga titlar:
--    Lil Nas X – "MONTERO (Call Me By Your Name)"
--    Lil Nas X – "STAR WALKIN' (League of Legends Worlds Anthem)"
--    Molly Sandén – "Húsavík (My Hometown)"
--    Cyndi Lauper – "Hey Now (Girls Just Want to Have Fun)"  (egen 1994-inspelning)
--
--  Idempotent: omdöpningen matchar på den gamla titeln, raderingen kräver
--  att den rena raden finns. Kör efter 0053.
-- ====================================================================

-- ====================================================================
--  Steg 1: fem rader till som visade sig vara dubbletter
-- --------------------------------------------------------------------
--  De här hittades inte av 0053 därför att den jämförde titlar
--  skiftlägeskänsligt: potten har "A thousand years" i den ena raden och
--  "A Thousand Years" i den andra. Här jämförs via dedup-nyckeln i
--  stället, som normaliserar skiftläge.
-- ====================================================================
delete from public.track_pool tp
 using (values
   ('Armageddon (I Don''t Want to Miss a Thing)',           'Aerosmith'),
   ('The Twilight Saga: Breaking Dawn (A thousand years)',  'Christina Perri'),
   ('Grease (Summer Nights)',                               'John Travolta, Olivia Newton-John'),
   ('Moulin Rouge (El Tango De Roxanne)',                   'José Feliciano,Ewan McGregor,Jacek Koman'),
   ('La La Land (City Of Stars)',                           'Ryan Gosling, Emma Stone')
 ) as v(filmtitel, artist)
 where tp.title = v.filmtitel
   and tp.artist = v.artist
   -- skyddsnät: bara om låten finns kvar under sin rena titel
   and exists (
         select 1 from public.track_pool ren
         where ren.id <> tp.id
           and ren.sv = tp.sv
           and public._track_dedup_key(ren.title, ren.artist)
             = public._track_dedup_key(substring(tp.title from '\(([^)]+)\)$'), tp.artist)
       );

-- ====================================================================
--  Steg 2: trettio titlar där filmnamnet skalas bort
-- ====================================================================
update public.track_pool tp set title = v.ny_titel
 from (values
   -- filmen först, låten i parentesen
   ('Forrest Gump (Forrest Gump Suite)',                'Forrest Gump Suite',              'Alan Silvestri'),
   ('Bram Stoker''s Dracula (Love Song for a Vampire)', 'Love Song for a Vampire',         'Annie Lennox'),
   ('Emily in Paris (Mon Soleil)',                      'Mon Soleil',                      'Ashley Park'),
   ('Top Gun (Take My Breath Away)',                    'Take My Breath Away',             'Berlin'),
   ('Rocky (Gonna Fly Now)',                            'Gonna Fly Now',                   'Bill Conti'),
   ('Chicago (Cell Block Tango)',                       'Cell Block Tango',                'Catherine Zeta-Jones'),
   ('Pinocchio (When You Wish Upon a Star)',            'When You Wish Upon a Star',       'Cliff Edwards'),
   ('8 Mile (Lose Yourself)',                           'Lose Yourself',                   'Eminem'),
   ('Encanto (We Don''t Talk About Bruno)',             'We Don''t Talk About Bruno',      'Encanto Cast'),
   ('Cheers (Where Everybody Knows Your Name)',         'Where Everybody Knows Your Name', 'Gary Portnoy'),
   ('Once (Falling Slowly)',                            'Falling Slowly',                  'Glen Hansard, Markéta Irglová'),
   ('Gladiator (Now We Are Free)',                      'Now We Are Free',                 'Hans Zimmer'),
   ('High School Musical (We''re All In This Together)','We''re All In This Together',     'High School Musical Cast'),
   ('Braveheart (For The Love Of A Princess)',          'For The Love Of A Princess',      'James Horner'),
   ('Godzilla (Deeper Underground)',                    'Deeper Underground',              'Jamiroquai'),
   ('Out of Africa (I Had a Farm in Africa)',           'I Had a Farm in Africa',          'John Barry'),
   ('Her (The Moon Song)',                              'The Moon Song',                   'Karen O, Ezra Koenig'),
   ('Greatest Showman (This Is Me)',                    'This Is Me',                      'Keala Settle'),
   ('Black Panther (All The Stars)',                    'All The Stars',                   'Kendrick Lamar, SZA'),
   ('Aladdin (A Whole New World)',                      'A Whole New World',               'Lea Salonga, Brad Kane'),
   ('Transformers (What I''ve Done)',                   'What I''ve Done',                 'Linkin Park'),
   ('Matrix (Clubbed to Death)',                        'Clubbed to Death',                'Robert D.'),
   ('Barbie (I''m Just Ken)',                           'I''m Just Ken',                   'Ryan Gosling'),

   -- låten först, filmen i parentesen – här är det parentesen som ska bort
   ('The Shire (The Lord of the Rings)',                'The Shire',                       'Howard Shore'),
   ('Calling You (Bagdad Cafe)',                        'Calling You',                     'Jevetta Steele'),
   ('Somewhere in My Memory (Home Alone)',              'Somewhere in My Memory',          'John Williams'),
   ('He''s a Pirate (Pirates of the Caribbean)',        'He''s a Pirate',                  'Klaus Badelt'),
   ('Tara''s Theme (Gone with the Wind)',               'Tara''s Theme',                   'Max Steiner'),
   ('Extreme Ways (Bourne''s Ultimatum)',               'Extreme Ways',                    'Moby'),

   -- specialfall: låtens officiella titel ÄR "Arthur's Theme (Best That
   -- You Can Do)". Bara "Arthur" är filmen, så raden får den riktiga
   -- titeln i stället för en avskalad.
   ('Arthur (Best That You Can Do)',                    'Arthur''s Theme (Best That You Can Do)', 'Christopher Cross')
 ) as v(gammal_titel, ny_titel, artist)
 where tp.title = v.gammal_titel
   and tp.artist = v.artist
   -- skyddsnät mot det unika indexet (dedup-nyckel, sv): om den nya titeln
   -- redan finns i samma pott görs ingen omdöpning i stället för att hela
   -- migrationen kraschar
   and not exists (
         select 1 from public.track_pool krock
         where krock.id <> tp.id
           and krock.sv = tp.sv
           and public._track_dedup_key(krock.title, krock.artist)
             = public._track_dedup_key(v.ny_titel, tp.artist)
       );
