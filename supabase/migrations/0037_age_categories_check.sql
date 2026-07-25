-- ====================================================================
--  0037  Tillåt ålderslägets kategorier på rounds
-- --------------------------------------------------------------------
--  BUGG: rounds_category_check har stått oförändrad sedan 0003 och listar
--  bara de fem ursprungliga kategorierna. 0031 införde approx_year_1 och
--  0032 införde before_after i _room_categories – men constrainten fick
--  aldrig veta det.
--
--  Följd: i åldersläge (year_min/year_max satt) väljer spin_wheel kategori
--  ur ett 5-set där TVÅ värden är förbjudna av constrainten → ungefär var
--  femte snurr slog i taket och kastade
--    new row for relation "rounds" violates check constraint
--    "rounds_category_check"
--  rakt upp i värdens ansikte. Bekräftat mot live-DB: noll rundor har
--  någonsin skapats med approx_year_1 eller before_after, dvs. de två
--  kategorierna har aldrig fungerat sedan de infördes.
--
--  Här utökas constrainten till alla sju giltiga kategorier. Rent additivt
--  (ingen befintlig rad kan bryta mot den bredare listan) och idempotent.
--  Sanningen om vilka kategorier ett visst rum använder ligger kvar i
--  _room_categories – constrainten är bara ett yttre skyddsnät.
--
--  LÄRDOM för framtida kategoritillägg: en ny kategori kräver ändring på
--  TRE ställen – _room_categories, denna constraint och _judge_answer.
-- ====================================================================

alter table public.rounds drop constraint if exists rounds_category_check;
alter table public.rounds add constraint rounds_category_check
  check (category in (
    'decade',        -- årtionde
    'artist',        -- artist
    'exact_year',    -- exakt årtal
    'approx_year',   -- årtal ±3 år
    'title',         -- låttitel
    'approx_year_1', -- årtal ±1 år (åldersläge, 0031)
    'before_after'   -- före/efter pivotåret (åldersläge, 0032)
  ));
