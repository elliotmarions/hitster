-- =====================================================================
--  LÅTSNURRAN – Fritt slumpad bricka (bort från latinsk kvadrat)
--
--  Tidigare var brickan en 5x5 latinsk kvadrat: varje rad OCH kolumn hade
--  alla 5 kategorier exakt en gång. Den slumpades per spel men kändes lik
--  eftersom strukturen var invariant. Nu placeras kategorierna FRITT slumpat
--  över de 25 rutorna – men fortfarande EXAKT 5 av varje (balanserad bricka).
--  En rad kan alltså nu ha t.ex. två "Artist".
--
--  Vinst = fyll en hel rad eller kolumn (mark_cross kollar bara ifyllda rutor,
--  inte kategorier) → ingen annan ändring behövs. Nya brickor får detta vid
--  nästa start_game / reset_game / ensure_card; pågående brickor är oförändrade.
--
--  Additiv + idempotent. Kör efter 0013.
-- =====================================================================

create or replace function public.gen_bingo_grid()
returns jsonb
language sql
volatile
as $$
  select jsonb_agg(jsonb_build_object('category', cat, 'filled', false) order by r)
  from (
    select cat, random() as r
    from unnest(array[
      'decade', 'artist', 'exact_year', 'approx_year', 'title',
      'decade', 'artist', 'exact_year', 'approx_year', 'title',
      'decade', 'artist', 'exact_year', 'approx_year', 'title',
      'decade', 'artist', 'exact_year', 'approx_year', 'title',
      'decade', 'artist', 'exact_year', 'approx_year', 'title'
    ]) as cat
  ) s;
$$;

notify pgrst, 'reload schema';
