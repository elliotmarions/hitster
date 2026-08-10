// ============================================================
//  Delade spelkonstanter (används i alla faser)
// ============================================================

// De fem kategorierna som discokulan kan landa på.
// Varje kategori har en fast neonfärg som återkommer konsekvent i hela UI:t.
export const CATEGORIES = {
  decade: {
    key: 'decade',
    label: 'Årtiondet',
    short: 'Årtionde',
    desc: 'Vilket decennium släpptes låten?',
    color: 'purple',
    hex: '#b14dff',
  },
  artist: {
    key: 'artist',
    label: 'Artisten',
    short: 'Artist',
    desc: 'Vem framför låten?',
    color: 'yellow',
    hex: '#ffc93c',
  },
  exact_year: {
    key: 'exact_year',
    label: 'Exakt årtal',
    short: 'Årtal',
    desc: 'Ange exakt utgivningsår.',
    color: 'pink',
    hex: '#ff4d9d',
  },
  approx_year: {
    key: 'approx_year',
    label: 'Årtal ±3 år',
    short: '±3 år',
    desc: 'Gissa utgivningsåret – rätt inom ±3 år räknas.',
    color: 'blue',
    hex: '#33a6ff',
  },
  // Tightare årtals-kategori (bara i åldersläge, där ±3 blir för lätt när
  // eran redan är smal). Delar aldrig bräde med approx_year → samma blå färg ok.
  approx_year_1: {
    key: 'approx_year_1',
    label: 'Årtal ±1 år',
    short: '±1 år',
    desc: 'Gissa utgivningsåret – rätt inom ±1 år räknas.',
    color: 'blue',
    hex: '#33a6ff',
  },
  title: {
    key: 'title',
    label: 'Låttiteln',
    short: 'Titel',
    desc: 'Vad heter låten?',
    color: 'green',
    hex: '#3ee87b',
  },
  // Bara i åldersläge: släpptes låten före eller efter ett givet år? Pivot-året
  // (rounds.pivot_year) slumpas per runda. Vattentät auto-bedömning – året är känt.
  before_after: {
    key: 'before_after',
    label: 'Före eller efter',
    short: 'Före/efter',
    desc: 'Släpptes låten före eller efter ett givet år?',
    color: 'purple',
    hex: '#b14dff',
  },
}

// Fast ordning – t.ex. discokulans segment.
export const CATEGORY_ORDER = ['decade', 'artist', 'exact_year', 'approx_year', 'title']

// Kategorier som ger sudd-rätt när suddregeln är på: de där svaret ÄR ett
// årtal. Inte 'decade' (då svarar man ett decennium) och inte 'before_after'
// (då väljer man sida – en ren gissning träffar rätt varannan gång, och sudd
// på femtio procents odds är en annan regel än den här).
// MÅSTE spegla serverns erase_cross (0063).
export const ERASE_CATEGORIES = ['exact_year', 'approx_year', 'approx_year_1']

// Åldersläge (rummet har ett årsfönster): årtionde + ±3 blir för lätt när eran
// redan är smal, så de byts mot en tightare ±1 år plus "Före eller efter" (mot
// ett slumpat pivot-år). Fem kategorier på snurran och brickan, precis som
// normalläget. MÅSTE spegla serverns _room_categories.
export const AGE_CATEGORY_ORDER = [
  'exact_year',
  'artist',
  'title',
  'approx_year_1',
  'before_after',
]

// Ett spann smalare än så här spelas i åldersläge. Gränsen är exklusiv:
// 19 år ger åldersläge, 20 ger det vanliga hjulet.
export const ALDERSLAGE_BREDD = 20

// Bredden på rummets årsspann, i antal år (inklusive båda ändarna).
// null = ingen årsgräns alls.
//
// Öppna kanter sluts, inte avfärdas: tidslinjen skriver null när ett handtag
// står i skalans ände, så "2010 och framåt" är i praktiken 17 år och ska
// räknas som det. Övre kanten sluts mot innevarande år, undre mot 1900 –
// före pottens äldsta spår, så den blir aldrig den bindande gränsen.
// MÅSTE spegla serverns _room_categories (0061).
export function yearSpanWidth(room) {
  const lo = room?.year_min ?? null
  const hi = room?.year_max ?? null
  if (lo === null && hi === null) return null
  return (hi ?? new Date().getFullYear()) - (lo ?? 1900) + 1
}

// Vilket kategori-set gäller för rummet just nu?
//
// Åldersläget finns för att en SMAL era gör "Årtionde" och "±3 år" triviala.
// Det är alltså bredden som motiverar bytet, inte att spannet existerar –
// 1955–2025 är inget smalt fönster och ska spelas med vanliga hjulet.
export function categoryOrderFor(room) {
  const bredd = yearSpanWidth(room)
  return bredd !== null && bredd < ALDERSLAGE_BREDD ? AGE_CATEGORY_ORDER : CATEGORY_ORDER
}

// Lagläge – neonfärger som tilldelas lag i tur och ordning.
export const TEAM_COLORS = ['#22e6e6', '#ff4d9d', '#b6ff3c', '#ffc93c', '#b14dff', '#ff8a3c']

// Fas 2 – spelplanens tajming och mått
export const TIMER_SECONDS = 25 // rundans timer
export const SPIN_MS = 4200 // discokulans snurr-animation (matchar timer_start_at i spin_wheel)
export const GRID = 5 // brickan är 5x5 (fritt slumpad, exakt 5 rutor per kategori)

// ============================================================
//  Låtpott-kategorier – EN väljare i lobbyn
// ============================================================
//
//  Potten avgränsas i TRE oberoende dimensioner: språk, årtal och genre.
//  Språk och genre är chip och bor i listan nedan; årtalet är ett fritt
//  eller flera spann på en tidslinje (se AR_MIN/yearSpansFrom längre ner)
//  och har därför inga chip alls.
//
//    union INOM en dimension  – Pop + Rock = låtar ur endera
//    snitt MELLAN dimensioner – årsspann + genre = låtar som är båda
//    tom dimension            – ingen gräns alls på den dimensionen
//
//  Inget valt = hela potten. Kombinationer kan bli tunna (svenska + 90-tal
//  + pop är ~300 låtar), så lobbyn visar antalet via
//  track_pool_selection_count() i stället för att gissa.
//
//  Allt filtreras server-side i _pool_match() – potten är oläsbar för
//  klienter, så antalen är det enda som lämnar databasen.
//
//  Språkchipsen har tre lägen tillsammans (0058): Svenska = bara svenska,
//  Utländska = allt utom svenskt, ingetdera = ingen språkgräns.
//
//  Genrerna filtrerar på track_pool.genre via _genre_key() server-side (0043).
//  Deezers etiketter är grova, så mappningen slår ihop det folk ändå uppfattar
//  som samma sak – "Alternativmusik" och "Metal" ligger under Rock. Antalen
//  hämtas live från track_pool_genre_counts(), inte hårdkodade, eftersom potten
//  växer.
export const POOL_CATEGORIES = [
  { key: 'sv', group: 'lang', label: 'Svenska', hint: 'Svenska låtar/artister', swedish: true, neon: '#ffd23f' },
  { key: 'intl', group: 'lang', label: '🌍 Utländska', hint: 'Internationella låtar/artister', swedish: false, neon: '#22e6e6' },
  { key: 'pop', group: 'genre', label: 'Pop', genre: 'pop', neon: '#ff4d9d' },
  { key: 'rock', group: 'genre', label: 'Rock', genre: 'rock', neon: '#ff8a3c' },
  { key: 'hiphop', group: 'genre', label: 'Hiphop', genre: 'hiphop', neon: '#b6ff3c' },
  { key: 'dance', group: 'genre', label: 'Dance', genre: 'dance', neon: '#22e6e6' },
  { key: 'rnb', group: 'genre', label: 'R&B', genre: 'rnb', neon: '#b14dff' },
]

// Rummets val i den form servern vill ha det. `swedish` har TRE lägen (0058):
// true = bara svenska, false = bara utländska, null = ingen språkgräns.
export function selectionFrom(room) {
  const sv = room?.swedish_mode
  return {
    swedish: sv === true || sv === false ? sv : null,
    bands: Array.isArray(room?.year_bands) ? room.year_bands : [],
    genres: Array.isArray(room?.genres) ? room.genres : [],
  }
}

// ---- Tidslinjen: årsspannet -----------------------------------------
//
// Åldersspannen var fem fasta chip byggda på reminiscensbågen ("20–29 år"
// = uppväxthits ~2008–idag). De är ersatta av ett fritt spann: samma sak
// för den som vill ha sin era, men utan att behöva översätta ålder till
// årtal, och möjligt att smalna av eller vidga precis som sällskapet vill.
//
// Formen i databasen är oförändrad. year_bands är sedan 0057 en lista av
// {min, max} som _pool_match() unionar, så ett spann är helt enkelt ETT band
// – ingen migration behövdes, varken för tidslinjen eller för att lägga till
// FLERA spann ("60-talet + 90-talet"). Servern kunde det redan; det var bara
// lobbyn som skrev ett enda band.
//
// Åldersläget (0061) läser däremot det HÄRLEDDA spannet year_min/year_max,
// alltså spannens ytterkanter. Två smala spann långt ifrån varandra ger en
// bred ytterkant och därmed vanliga hjulet – vilket är rätt: kategorin
// "Årtionde" är inte trivial när potten spänner över flera decennier.
//
// Skalans ändar är inte pottens ytterligheter. Potten har enstaka spår
// ända ner till 1908, men under ~1955 rör det sig om någon låt per år;
// en tidslinje som la två tredjedelar av sin bredd på dem hade varit
// oanvändbar. De 18 låtarna före 1950 spelas därför bara när HELA skalan
// är vald (tomt year_bands = ingen årsgräns). Ett spann som råkar ligga an
// mot vänsterkanten betyder 1950, inte "ingen undre gräns" – annars var
// nästan var femte låt i ett 1950–1960-rum äldre än vad tidslinjen visade.
// Övre änden följer klockan så skalan inte rostar.
export const AR_MIN = 1950
export const AR_MAX = Math.max(2026, new Date().getFullYear())

// Bredden på ett spann som läggs till med +. Ett decennium är brett nog att
// ge en spelbar pott och smalt nog att lämna plats för fler spann.
export const NYTT_SPANN_BREDD = 10

// Rummets spann som en lista av [från, till] på tidslinjens skala.
// Öppen kant (null) blir skalans ände. Tom lista = ingen årsgräns alls.
//
// Ordningen är den de skrevs i, INTE kronologisk. Listan är också raderna i
// lobbyn: sorterade vi här skulle en rad man just lagt till hoppa uppåt i
// samma stund servern svarade, medan handen fortfarande låg kvar på reglaget.
export function yearSpansFrom(room) {
  return selectionFrom(room)
    .bands.map((b) => [
      Math.max(AR_MIN, b?.min ?? AR_MIN),
      Math.min(AR_MAX, b?.max ?? AR_MAX),
    ])
    .filter(([lo, hi]) => hi >= lo)
}

// Spann som överlappar eller ligger kant i kant är samma spann. Servern
// unionar dem ändå i _pool_match(), så att slå ihop dem här ändrar ingen
// pott – det håller bara listan sann mot vad man faktiskt valt.
//
// Ordningen bevaras, och det ihopslagna spannet ärver platsen från det
// tidigaste det rörde vid: drar man ihop två rader ska resultatet ligga kvar
// där den översta låg, inte kastas ned i listan.
export function mergeSpans(spans) {
  const ihop = []
  for (const [lo, hi] of spans) {
    let nytt = [lo, hi]
    let plats = ihop.length
    for (let i = ihop.length - 1; i >= 0; i--) {
      const [a, b] = ihop[i]
      if (nytt[0] <= b + 1 && a <= nytt[1] + 1) {
        nytt = [Math.min(a, nytt[0]), Math.max(b, nytt[1])]
        ihop.splice(i, 1)
        plats = i
      }
    }
    ihop.splice(plats, 0, nytt)
  }
  return ihop
}

// year_bands för de valda spannen. ÖVRE kanten i skalans ände skrivs som null
// (= öppen) i stället för årtalet: "1990 och uppåt" ska fortsätta betyda det
// även när nästa års låtar kommer in i potten. (I sammanfattningen skrivs den
// ändå ut som ett årtal, se bandLabel.)
//
// UNDRE kanten skrivs alltid ut. Den var också öppen förut, men där finns
// låtar bortom skalan – och de kom med utan att synas någonstans på
// tidslinjen. Ett sidoresultat av samma null: åldersläget (0061) läser det
// härledda year_min, och med null räknades även ett elvaårigt spann som
// 1900–1960, alltså brett nog för vanliga hjulet med "Årtionde" som
// gratisruta. Båda försvinner när kanten är ett årtal.
//
// Täcker något spann hela skalan finns ingen gräns kvar att skriva.
export function yearBandsFor(spans) {
  const ihop = mergeSpans(spans)
  if (!ihop.length) return []
  if (ihop.some(([lo, hi]) => lo <= AR_MIN && hi >= AR_MAX)) return []
  return ihop.map(([lo, hi]) => ({
    min: Math.max(AR_MIN, lo),
    max: hi >= AR_MAX ? null : hi,
  }))
}

// Var hamnar nästa spann? I den bredaste luckan mellan de redan valda, så
// att + aldrig lägger ett spann ovanpå ett annat (två spann som överlappar
// är ju ett spann). Utan valda spann är hela skalan lucka och det första
// spannet hamnar mitt på tidslinjen. null = det finns ingen lucka kvar.
export function nextSpanFor(spans) {
  // Luckorna räknas fram vänster till höger och kräver därför kronologi –
  // till skillnad från listan i lobbyn, som ligger i den ordning man valt.
  const ihop = mergeSpans(spans).sort((a, b) => a[0] - b[0])

  // Ett års marginal mot grannarna. mergeSpans slår ihop spann som ligger
  // KANT I KANT, så ett nytt spann som fyller en lucka helt skulle svälja
  // både sig självt och sina grannar: + hade då inte lagt till en rad utan
  // slagit ihop de befintliga till ett bredare spann. Skalans ändar har
  // ingen granne och behöver ingen marginal.
  const luckor = []
  const lagg = (fran, till) => {
    const a = fran > AR_MIN ? fran + 1 : fran
    const b = till < AR_MAX ? till - 1 : till
    if (a <= b) luckor.push([a, b])
  }
  let kant = AR_MIN
  for (const [lo, hi] of ihop) {
    if (lo - 1 >= kant) lagg(kant, lo - 1)
    kant = Math.max(kant, hi + 1)
  }
  if (kant <= AR_MAX) lagg(kant, AR_MAX)
  // Ingen lucka rymmer ett spann som inte klistrar ihop sig med en granne –
  // då finns det inget att lägga till, och + släcks.
  if (!luckor.length) return null

  const [lo, hi] = luckor.reduce((bast, l) => (l[1] - l[0] > bast[1] - bast[0] ? l : bast))
  if (hi - lo + 1 <= NYTT_SPANN_BREDD) return [lo, hi]
  const mitt = Math.round((lo + hi) / 2)
  const halva = Math.floor(NYTT_SPANN_BREDD / 2)
  return [mitt - halva, mitt - halva + NYTT_SPANN_BREDD - 1]
}

// Är den här chippen vald just nu?
export function isSelected(room, cat) {
  const s = selectionFrom(room)
  if (cat.group === 'lang') return s.swedish === cat.swedish
  if (cat.group === 'genre') return s.genres.includes(cat.genre)
  return false
}

// Valet efter att chippen slagits av/på. Returnerar de tre rums-fälten.
export function toggleSelection(room, cat) {
  const s = selectionFrom(room)
  if (cat.group === 'lang') {
    // Språkchipsen utesluter varandra: "svenska OCH utländska" är samma sak
    // som ingen gräns alls, så att låta båda lysa vore bara förvirrande.
    // Klick på den redan valda släcker den → ingen språkgräns.
    return {
      swedish_mode: s.swedish === cat.swedish ? null : cat.swedish,
      year_bands: s.bands,
      genres: s.genres,
    }
  }
  const finns = s.genres.includes(cat.genre)
  return {
    swedish_mode: s.swedish,
    year_bands: s.bands,
    genres: finns ? s.genres.filter((g) => g !== cat.genre) : [...s.genres, cat.genre],
  }
}

// Inget valt alls = hela potten.
export function selectionEmpty(room) {
  const s = selectionFrom(room)
  return s.swedish === null && s.bands.length === 0 && s.genres.length === 0
}

export const TOMT_VAL = { swedish_mode: null, year_bands: [], genres: [] }

// Ett band i klartext.
//
// Övre kanten lagras som null när handtaget står i skalans ände, så att nästa
// års låtar följer med av sig själva. I TEXT är den ändå ett årtal: skalan
// slutar vid innevarande år och det finns inga låtar bortom den, så "1990–2026"
// säger samma sak som "1990 och framåt" – fast med det årtal man just drog till.
//
// Undre kanten är ett årtal sedan yearBandsFor slutade skriva den öppen.
// "till och med"-formen står kvar för rum som valdes före det: deras band
// ligger kvar i databasen och betyder fortfarande vad de betydde då.
function bandLabel(b) {
  const lo = b?.min ?? null
  const hi = b?.max ?? null
  if (lo === null && hi === null) return null
  if (lo === null) return `till och med ${hi}`
  const till = hi ?? AR_MAX
  return lo === till ? `${lo}` : `${lo}–${till}`
}

// Årsvalet i klartext. Flera spann skrivs ut var för sig – "1965–1974 +
// 1990–1999" – eftersom de är en union: att bara visa ytterkanterna hade
// påstått att allt däremellan också var med. Ordningen är bandens egen, samma
// som lobbyns rader, så texten går att läsa uppifrån och ned mot tidslinjerna.
export function yearSpanLabel(room) {
  const bands = selectionFrom(room).bands
  if (!bands.length) return null
  // Ett band utan gränser släpper in varje år, och då finns ingen gräns kvar.
  if (bands.some((b) => (b?.min ?? null) === null && (b?.max ?? null) === null)) return null
  return bands.map(bandLabel).join(' + ')
}

// En läsbar sammanfattning av valet, t.ex. "Svenska · 1985–2004 · Pop".
// Ersätter poolCategoryFor(), som byggde på att rummet stod på EXAKT en
// kategori – ett antagande som inte längre håller efter 0057.
export function selectionLabel(room) {
  const s = selectionFrom(room)
  if (selectionEmpty(room)) return 'Alla låtar'
  const delar = []
  if (s.swedish === true) delar.push('Svenska')
  else if (s.swedish === false) delar.push('Utländska')
  const ar = yearSpanLabel(room)
  if (ar) delar.push(ar)
  const gen = POOL_CATEGORIES.filter(
    (c) => c.group === 'genre' && s.genres.includes(c.genre),
  ).map((c) => c.label)
  if (gen.length) delar.push(gen.join(', '))
  return delar.join(' · ')
}
