-- ====================================================================
--  0039  Rätta 0038: låtar som ska ligga i BÅDA potterna
-- --------------------------------------------------------------------
--  MISSTAG I 0038: dedup-nyckeln tog bara hänsyn till titel + artist,
--  inte till vilken pott raden tillhör. Men 71 låtar ligger MEDVETET
--  dubbelt – en gång i världspotten (sv = false) och en gång i den
--  svenska (sv = true). ABBA, Roxette, Avicii, Kent, Håkan Hellström …
--  svenska artister som hör hemma i båda kategorierna.
--
--  Eftersom start_random_track filtrerar hårt på `tp.sv = swedish_mode`
--  är de två raderna inte dubbletter – de är låtens biljett till var sin
--  kategori. 0038 slog ihop dem ändå, och svenska potten krympte från
--  248 till 181 låtar (−27 %).
--
--  HÄR: nyckeln kompletteras med sv i det unika indexet (dubbletter jagas
--  inom varje pott, inte tvärs över dem) och de 71 raderna återställs.
--
--  Raderna återskapas genom att KOPIERA den överlevande systerraden och
--  bara vända på sv – inte genom att läsa tillbaka originalvärdena ur
--  0025. Det är avsiktligt: 0038 valde originalutgåvans år och den renaste
--  titeln, och den sanningen ska gälla i båda potterna. Läste vi tillbaka
--  seed-raderna skulle t.ex. "747" med Kent stå som 1996 i svenska potten
--  och 1999 i världspotten igen.
-- ====================================================================

-- ====================================================================
--  Steg 1: unikt index per pott i stället för globalt
-- ====================================================================
drop index if exists public.track_pool_dedup_key_idx;

create unique index if not exists track_pool_dedup_key_sv_idx
  on public.track_pool (public._track_dedup_key(title, artist), sv);

-- ====================================================================
--  Steg 2: återställ de 71 raderna
-- --------------------------------------------------------------------
--  Listan är (dedup-nyckel, potten vars rad saknas) och är GENERERAD ur
--  seed-datan i 0025 – den enda kvarvarande källan till vilka låtar som
--  var tänkta att ligga i båda potterna. Kontrollerat före körning: alla
--  71 har en systerrad kvar att kopiera ifrån.
-- ====================================================================
with saknas (k, sv) as (values
  ('747|kent', false),
  ('jag vill ha en egen måne|ted gärdestad', false),
  ('levels|avicii', false),
  ('all that she wants|ace of base', true),
  ('beautiful life|ace of base', true),
  ('boten anna|basshunter', true),
  ('bra vibrationer|kikki danielsson', true),
  ('buffalo stance|neneh cherry', true),
  ('call on me|eric prydz', true),
  ('cotton eye joe|rednex', true),
  ('crucified|army of lovers', true),
  ('cry for you|september', true),
  ('crying at the discoteque|alcazar', true),
  ('dance with somebody|mando diao', true),
  ('dancing on my own|robyn', true),
  ('dancing queen|abba', true),
  ('det kommer aldrig va över för mig|håkan hellström', true),
  ('diggiloo diggiley|herreys', true),
  ('dom andra|kent', true),
  ('dont you worry child|swedish house mafia', true),
  ('dressed for success|roxette', true),
  ('emmylou|first aid kit', true),
  ('euphoria|loreen', true),
  ('fading like a flower|roxette', true),
  ('främling|carola', true),
  ('fångad av en stormvind|carola', true),
  ('gimme gimme gimme|abba', true),
  ('habits|tove lo', true),
  ('hate to say i told you so|hives', true),
  ('hey brother|avicii', true),
  ('hooked on a feeling|blue swede', true),
  ('how do you do|roxette', true),
  ('i love it|icona pop', true),
  ('it must have been love|roxette', true),
  ('it takes a fool to remain sane|ark', true),
  ('its my life|dr. alban', true),
  ('jag kommer|veronica maggio', true),
  ('joyride|roxette', true),
  ('just nu|tomas ledin', true),
  ('kom igen lena|håkan hellström', true),
  ('känn ingen sorg för mig göteborg|håkan hellström', true),
  ('lovefool|cardigans', true),
  ('lush life|zara larsson', true),
  ('mamma mia|abba', true),
  ('money money money|abba', true),
  ('moviestar|harpo', true),
  ('my favourite game|cardigans', true),
  ('måndagsbarn|veronica maggio', true),
  ('never forget you|zara larsson', true),
  ('no money|galantis', true),
  ('pjanoo|eric prydz', true),
  ('release me|agnes', true),
  ('runaway|galantis', true),
  ('save tonight|eagle-eye cherry', true),
  ('sing hallelujah|dr. alban', true),
  ('sol vind och vatten|ted gärdestad', true),
  ('sommartider|gyllene tider', true),
  ('sos|abba', true),
  ('sos|avicii', true),
  ('square hammer|ghost', true),
  ('the final countdown|europe', true),
  ('the look|roxette', true),
  ('the sign|ace of base', true),
  ('utan dina andetag|kent', true),
  ('vem vet|lisa ekdahl', true),
  ('voulezvous|abba', true),
  ('waiting for love|avicii', true),
  ('wake me up|avicii', true),
  ('without you|avicii', true),
  ('ängeln i rummet|eva dahlgren', true),
  ('öppna landskap|ulf lundell', true)
)
insert into public.track_pool (title, artist, year, sv)
select tp.title, tp.artist, tp.year, s.sv
  from saknas s
  join public.track_pool tp
    on public._track_dedup_key(tp.title, tp.artist) = s.k
 where not exists (
   select 1 from public.track_pool x
    where public._track_dedup_key(x.title, x.artist) = s.k
      and x.sv = s.sv
 );
