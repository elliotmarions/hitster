-- ====================================================================
--  0038  Rensa dubbletter ur låtpotten + spärr mot nya
-- --------------------------------------------------------------------
--  PROBLEM: potten innehöll 177 dubblettrader (~5 %). Tre konsekvenser:
--    1. Dubblerade låtar drogs 2–3× oftare än andra.
--    2. Anti-repeat-spärren går på pool_id, så SAMMA låt kunde komma två
--       gånger i samma parti via en annan rad.
--    3. VÄRST: 16 grupper hade olika år på samma låt ("Pump Up The Jam"
--       1989 och 2011, "Hello Mary Lou" 1961 och 2008). Samma låt dömdes
--       alltså olika i exact_year beroende på vilken rad som råkade dras.
--
--  NYCKEL: rensad titel + huvudartist. Titeln körs genom _clean_title
--  (tar bort " - Remix", "(Radio Edit)" …) och skalas till a-z0-9åäö.
--  Artisten skalas till huvudnamnet: allt efter feat./ft./with/vs/x samt
--  efter komma, &, / och " och " faller bort, liksom inledande "The".
--  Det fångar "Elton John" = "Elton John, Dua Lipa & PNAU" och
--  "Ace of Base" = "Ace Of Base".
--
--  KONTROLLERAT: 18 grupper slås ihop trots att de fullständiga artist-
--  strängarna skiljer sig – alla granskade manuellt, samtliga är samma
--  låt med olika creditering (feat-artister utskrivna, "et"/"and", versaler).
--  Noll felaktiga sammanslagningar.
--
--  ÖVERLEVANDE RAD, i tur och ordning:
--    1. odekorerad titel (title = _clean_title(title))
--    2. kortast titel        → "Mr. Saxobeat" slår "Mr. Saxobeat - Radio Edit"
--    3. tidigast år          → originalutgåvan slår återutgivningen
--    4. lägst id
--  Regeln gav rätt rad i alla 16 årskonflikter vid torrkörning.
--
--  Historiken skyddas: round_tracks/pending_tracks pekas om till den
--  överlevande raden INNAN dubbletterna tas bort (round_tracks.pool_id är
--  ON DELETE SET NULL – utan ompekning hade anti-repeat tappat minnet).
-- ====================================================================

-- ====================================================================
--  Steg 1: nyckeln som avgör vad som är samma låt
-- ====================================================================
create or replace function public._track_dedup_key(p_title text, p_artist text)
returns text
language sql immutable
set search_path = public
as $$
  select
    -- titeln: avdekorerad, gemener, bara bokstäver/siffror/mellanslag
    regexp_replace(lower(trim(public._clean_title(p_title))), '[^a-z0-9åäö ]', '', 'g')
    || '|' ||
    -- artisten: huvudnamnet, utan gästartister och utan inledande "the".
    -- OBS \s+ och inte \s* före gästartist-orden: med \s* matchade det korta
    -- alternativet "x" (som finns för "220 KID x Billen Ted") bokstaven x mitt
    -- inne i ord, så "Max Steiner" kapades till "ma".
    regexp_replace(
      regexp_replace(
        split_part(
          regexp_replace(lower(p_artist), '\s+(feat\.?|ft\.?|featuring|with|vs\.?|x)\s.*$', ''),
          ',', 1),
        '\s*(&|/| och ).*$', ''),
      '^the\s+', '');
$$;

-- ====================================================================
--  Steg 2: peka om historiken till den rad som ska överleva
-- ====================================================================
create temporary table _dedup_map on commit drop as
with rankad as (
  select
    id,
    public._track_dedup_key(title, artist) as k,
    row_number() over (
      partition by public._track_dedup_key(title, artist)
      order by
        (case when title = public._clean_title(title) then 0 else 1 end),
        length(title),
        year,
        id
    ) as rn
  from public.track_pool
)
select r.id as gammal_id, b.id as behall_id
from rankad r
join rankad b on b.k = r.k and b.rn = 1
where r.rn > 1;

update public.round_tracks rt
   set pool_id = m.behall_id
  from _dedup_map m
 where rt.pool_id = m.gammal_id;

update public.pending_tracks pt
   set pool_id = m.behall_id
  from _dedup_map m
 where pt.pool_id = m.gammal_id;

-- ====================================================================
--  Steg 3: bort med dubbletterna
-- ====================================================================
delete from public.track_pool tp
 using _dedup_map m
 where tp.id = m.gammal_id;

-- ====================================================================
--  Steg 4: spärr mot att nya dubbletter smyger in
-- --------------------------------------------------------------------
--  Unikt index på nyckeln. Ett framtida insert av samma låt (oavsett
--  creditering eller " - Radio Edit"-svans) avvisas nu direkt i stället
--  för att tyst hamna i potten. OBS: ändras _track_dedup_key eller
--  _clean_title måste indexet byggas om (reindex).
-- ====================================================================
create unique index if not exists track_pool_dedup_key_idx
  on public.track_pool (public._track_dedup_key(title, artist));
