-- =====================================================================
--  LÅTSNURRAN – Åldersläget avgörs av spannets BREDD, inte av att det finns
--
--  _room_categories slog om till åldersläge så fort year_min eller year_max
--  var satt. Det höll när spannen var fem fasta chip på ~15 år: en smal era
--  gör "Årtionde" och "±3 år" triviala, så de byttes mot ±1 år och
--  före/efter.
--
--  Med tidslinjen väljer man spannet fritt. 1955–2025 är inte en smal era,
--  men fick ändå de svåra kategorierna bara för att gränserna råkade vara
--  satta. Nu är det bredden som avgör: under 20 år = åldersläge, annars
--  vanliga hjulet.
--
--  Öppna kanter måste räknas, inte avfärdas. Tidslinjen skriver null när ett
--  handtag står i skalans ände, så "2010 och framåt" ligger i year_min med
--  year_max = null – i praktiken 17 år, alltså precis ett sådant smalt spann
--  regeln handlar om. Öppen övre kant sluts därför mot innevarande år, och
--  öppen undre mot 1900 (före pottens äldsta spår, så den blir aldrig den
--  bindande gränsen).
--
--  Att sluta övre kanten mot now() gör funktionen tidsberoende: den går från
--  immutable till stable. Den anropas bara inne i plpgsql-kroppar, aldrig i
--  ett index eller en check-constraint (rounds_category_check i 0037 listar
--  kategorierna literalt), så bytet är ofarligt.
--
--  Klientens categoryOrderFor() speglar den här regeln och måste ändras i
--  takt – den ritar hjulet innan servern hunnit svara.
--
--  Additiv + idempotent. Kör efter 0060.
-- =====================================================================

create or replace function public._room_categories(p_year_min int, p_year_max int)
returns text[] language sql stable set search_path = public as $$
  select case
    when (p_year_min is not null or p_year_max is not null)
     and (coalesce(p_year_max, extract(year from now())::int)
          - coalesce(p_year_min, 1900) + 1) < 20
      then array['exact_year', 'artist', 'title', 'approx_year_1', 'before_after']
    else array['decade', 'artist', 'exact_year', 'approx_year', 'title']
  end;
$$;

notify pgrst, 'reload schema';
