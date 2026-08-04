-- ====================================================================
--  0051  Svenska artister ur nattens pottutökning in i svenska potten
-- --------------------------------------------------------------------
--  KÖR INTE FÖRE ÅRSREVISIONEN ÄR KLAR. Se "Ordning" längst ned.
--
--  0043 och 0044 lade in 2 802 låtar och satte sv = false på allt, med
--  flit ("den balansen rörs inte här"). Följden är att 34 låtar av
--  artister som redan finns i svenska potten aldrig syns i svenskt läge:
--  Waterloo, The Winner Takes It All, sex Avicii-låtar, tre Sabaton, tre
--  Zara Larsson, Dance Macabre …
--
--  Kriteriet är potten's eget: `sv` markerar svensk ARTIST, inte svenskt
--  språk – Roxettes "It Must Have Been Love" och ABBA:s engelskspråkiga
--  låtar ligger redan som sv = true i 0025. De 34 hör alltså hemma i
--  svenska potten på exakt samma grund.
--
--  METOD: samma som 0039 – kopiera raden och vänd på sv, så låten ligger
--  i BÅDA potterna. Det unika indexet är (dedup-nyckel, sv), så en kopia
--  per pott är tillåten och `on conflict do nothing` gör körningen
--  idempotent. Året kopieras från den befintliga raden i stället för att
--  skrivas in på nytt – potterna får aldrig gå isär i år igen (det var
--  precis felet 0050 fick städa upp efter 0048).
--
--  URVALET är deklarativt, inte en handskriven lista, men med två spärrar:
--
--  1. Artistnyckeln får bara komma från en SOLOKREDITERAD sv-rad.
--     _track_dedup_key kapar gästartister, så "Clean Bandit & Zara
--     Larsson – Symphony" (sv = true, helt riktigt) lämnar nyckeln
--     "clean bandit" efter sig. Utan spärren hade Rather Be, Rockabye
--     och Solo – brittisk grupp, ingen svensk inblandning – dragits in
--     i svenska potten på Zara Larssons gästspel.
--
--  2. "Pretty Woman (It Must Have Been Love)" är utesluten. Den är samma
--     inspelning som Roxettes "It Must Have Been Love" (1990), som redan
--     ligger i båda potterna, men med ett titelpåhäng som dedup-nyckeln
--     inte kapar. Den raden ska städas bort ur världspotten, inte
--     kopieras vidare till den svenska.
--
--  ORDNING: kör EFTER de årsrättningar som årsrevisionen av potten
--  landar. Kopian ärver årtalet från världspottsraden – rättas året
--  först slipper vi bära in ett känt fel i den pott där årtalen betyder
--  mest. Körs den ändå först är det inte farligt, men då måste
--  rättningarna sakna sv-villkor (som i 0050) för att nå båda raderna.
-- ====================================================================

insert into public.track_pool (title, artist, year, sv, genre)
select t.title, t.artist, t.year, true, t.genre
from public.track_pool t
where not t.sv
  -- artisten finns redan i svenska potten, krediterad ensam
  and split_part(public._track_dedup_key(t.title, t.artist), '|', 2) in (
        select distinct split_part(public._track_dedup_key(s.title, s.artist), '|', 2)
        from public.track_pool s
        where s.sv
          and regexp_replace(lower(trim(s.artist)), '^the\s+', '')
              = split_part(public._track_dedup_key(s.title, s.artist), '|', 2)
      )
  -- låten saknas i svenska potten
  and not exists (
        select 1 from public.track_pool x
        where x.sv
          and public._track_dedup_key(x.title, x.artist) = public._track_dedup_key(t.title, t.artist)
      )
  -- spärr 2: dubbletten med titelpåhäng följer inte med
  and t.title <> 'Pretty Woman (It Must Have Been Love)'
on conflict do nothing;
