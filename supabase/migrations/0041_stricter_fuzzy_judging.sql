-- ====================================================================
--  0041  Stramare rättning av artist- och titelsvar
-- --------------------------------------------------------------------
--  _fuzzy_text var för slapp och godkände uppenbart fel svar. Tre hål,
--  alla reproducerade mot live-funktionen:
--
--   1. `position(na in nt) > 0` – om SVARET var en delsträng av facit
--      blev det rätt. Alltså räckte ETT ord av fem: "dancing" mot
--      "Dancing Queen", "life" mot "You Are the Sunshine of My Life",
--      "kent" mot "Kent Andersson", till och med "a" mot "Madonna".
--
--   2. `dist <= 1` utan längdkrav – två helt olika enteckensvar ligger
--      på Levenshtein-avstånd 1. Därför dömdes svaret "9" som RÄTT när
--      facit var "X". (Det var felet som rapporterades.)
--
--   3. Delsträngen saknade ordgränser, så "sos" matchade i "Sossarna".
--
--  NY MODELL – tre vägar till rätt, i tur och ordning:
--
--   1. Facit står ordagrant i svaret, med ordgränser. Låter en spela
--      skriva "det är nog dancing queen" utan att straffas.
--
--   2. ALLA ord ur facit finns i svaret (ordföljden spelar ingen roll).
--      Undantagna är bara de ord folk faktiskt hoppar över: the, a, an,
--      of, and, en, ett, och. Per ord tillåts ett stavfel, men bara för
--      ord på minst 5 tecken; annars blir korta ord ("99" mot "9") gratis.
--      Saknas ett ord är svaret FEL – det är regeln som stänger "ett ord
--      av fem". Att listan är kort är avgörande: med en bred stoppords-
--      lista räckte "Heat" igen för "The Heat Is On".
--
--   3. Har facit inga ord kvar att kräva (t.ex. titeln "X") jämförs hela
--      strängarna. Absolut avstånd 1 tillåts först från 5 tecken, annars
--      krävs 85 % likhet.
--
--  Kvar som förut: versaler, skiljetecken, "feat."-svansar och extra ord
--  i svaret spelar ingen roll (_norm_text). Värden kan fortfarande
--  överstyra domen i båda riktningarna – auto-domen ska vara rimlig,
--  inte ofelbar.
--
--  DESSUTOM, upptäckt under testningen: _norm_text klippte bort "with"
--  OCH ALLT EFTER DET, tänkt för credit-svansar som "… with Bruno Mars".
--  Men det slog på vilket "with" som helst mitt i en titel:
--    "With Or Without You"                → ""   (helt tom!)
--    "With A Little Help From My Friends" → ""
--    "Dancing With Myself"                → "dancing"
--    "Hit Me With Your Rhythm Stick"      → "hit me"
--  Tomt facit betyder att INGET svar kunde bli rätt – inte ens den exakt
--  rätta titeln. Riktiga credit-svansar står nästan alltid i parentes och
--  städas redan av parentes-regeln, så "with" tas bort ur listan; feat/ft/
--  featuring räcker.
--
--  Testad mot 30 handplockade fall (11 ska bli rätt, 19 ska bli fel) och
--  mot hela potten på 3 102 låtar. Efter ändringen: exakt titel, exakt
--  artist och titel utan inledande "the" godkänns alla i 100 % av fallen,
--  stavfel i 95–99 %. Första ordet ur en flerordstitel gick från att alltid
--  godkännas till 6 % – och de som är kvar är befogade (parentes-underrubrik
--  som "Escape (The Pina Colada Song)" eller upprepningar som "Sing, Sing,
--  Sing"). Kvar som känd svaghet: stavfel i ord under 5 tecken godkänns inte.
-- ====================================================================

-- ====================================================================
--  Steg 1: sluta kapa titlar vid "with"
-- ====================================================================
create or replace function public._norm_text(t text)
returns text
language sql immutable
as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(coalesce(t, '')), '\(.*?\)', ' ', 'g'),
          '\y(feat|ft|featuring)\y.*$', ' ', 'gi'),
        '[-–]\s*(remaster|remastered|mono|stereo|version|mix|edit|single|original|live|radio).*$', ' ', 'gi'),
      '[^[:alnum:] ]', ' ', 'g'),
    '\s+', ' ', 'g'))
$$;

-- ====================================================================
--  Steg 2: stramare bedömning
-- ====================================================================

create or replace function public._fuzzy_text(p_answer text, p_target text)
returns boolean
language plpgsql immutable
set search_path to 'public', 'extensions'
as $$
declare
  na    text := public._norm_text(p_answer);
  nt    text := public._norm_text(p_target);
  atoks text[];
  ttoks text[];
  ttok  text;
  atok  text;
  hit   boolean;
  sig   int := 0;
  dist  int;
  -- Ord som folk faktiskt utelämnar när de skriver en titel, och som därför
  -- inte krävs i svaret. Listan hålls MEDVETET kort: tas för många ord bort
  -- räcker det snart med ett enda ord igen ("Heat" för "The Heat Is On").
  -- Allt annat i titeln måste vara med.
  stopp constant text[] := array['the', 'a', 'an', 'of', 'and', 'en', 'ett', 'och'];
begin
  if na = '' or nt = '' then return false; end if;
  if na = nt then return true; end if;

  atoks := string_to_array(na, ' ');
  ttoks := string_to_array(nt, ' ');

  -- 1. Facit ordagrant i svaret, med ordgränser.
  --    nt är normaliserad till enbart alfanumeriskt + mellanslag, så den
  --    är trygg att stoppa rakt in i ett regex-mönster.
  if length(nt) >= 3 and na ~ ('\m' || nt || '\M') then
    return true;
  end if;

  -- 2. Alla betydande facit-ord måste finnas i svaret.
  foreach ttok in array ttoks loop
    if length(ttok) < 2 or ttok = any (stopp) then
      continue;
    end if;
    sig := sig + 1;
    hit := false;
    foreach atok in array atoks loop
      if atok = ttok or (length(ttok) >= 5 and levenshtein(atok, ttok) <= 1) then
        hit := true;
        exit;
      end if;
    end loop;
    if not hit then
      return false;
    end if;
  end loop;

  if sig > 0 then
    return true;
  end if;

  -- 3. Facit saknar betydande ord – jämför hela strängarna.
  dist := levenshtein(na, nt);
  if greatest(length(na), length(nt)) >= 5 and dist <= 1 then
    return true;
  end if;
  return (1.0 - dist::numeric / greatest(length(na), length(nt))) >= 0.85;
end;
$$;
