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

// Vilket kategori-set gäller för rummet just nu?
export function categoryOrderFor(room) {
  const ageMode = room?.year_min != null || room?.year_max != null
  return ageMode ? AGE_CATEGORY_ORDER : CATEGORY_ORDER
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
//  spann på en tidslinje (se AR_MIN/yearRangeFrom längre ner) och har
//  därför inga chip alls.
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
  { key: 'sv', group: 'lang', label: 'Svenska', hint: 'Bara svenska artister', swedish: true, neon: '#ffd23f' },
  { key: 'intl', group: 'lang', label: '🌍 Utländska', hint: 'Allt utom svenskt', swedish: false, neon: '#22e6e6' },
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
// {min, max} och _pool_match() filtrerar på godtyckliga värden, så ett
// spann är helt enkelt ETT band – ingen migration behövdes.
//
// Skalans ändar är inte pottens ytterligheter. Potten har enstaka spår
// ända ner till 1908, men under ~1955 rör det sig om någon låt per år;
// en tidslinje som la två tredjedelar av sin bredd på dem hade varit
// oanvändbar. Ändarna betyder därför "ingen gräns åt det hållet", inte
// "1950": dras reglaget ut helt skrivs ett tomt year_bands och de gamla
// låtarna är med. Övre änden följer klockan så skalan inte rostar.
export const AR_MIN = 1950
export const AR_MAX = Math.max(2026, new Date().getFullYear())

// Rummets spann som [från, till] på tidslinjens skala. Öppen kant (null)
// blir skalans ände. Flera band kan inte ritas som ETT spann – gamla rum
// från chip-tiden kan ha det – så då visas ytterkanterna, precis som
// serverns _sync_year_envelope() räknar ut year_min/year_max.
export function yearRangeFrom(room) {
  const bands = selectionFrom(room).bands
  if (!bands.length) return [AR_MIN, AR_MAX]
  const mins = bands.map((b) => b?.min ?? null)
  const maxs = bands.map((b) => b?.max ?? null)
  const lo = mins.some((m) => m === null) ? AR_MIN : Math.min(...mins)
  const hi = maxs.some((m) => m === null) ? AR_MAX : Math.max(...maxs)
  return [Math.max(AR_MIN, lo), Math.min(AR_MAX, hi)]
}

// year_bands för ett valt spann. En kant som ligger i skalans ände skrivs
// som null (= öppen) i stället för årtalet: "1990 och framåt" ska fortsätta
// betyda det även när nästa års låtar kommer in i potten.
export function yearBandsFor([lo, hi]) {
  if (lo <= AR_MIN && hi >= AR_MAX) return []
  return [{ min: lo <= AR_MIN ? null : lo, max: hi >= AR_MAX ? null : hi }]
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

// Spannet i klartext. Öppen kant skrivs ut som "och framåt" / "till och med"
// i stället för skalans ändår – annars hade sammanfattningen påstått en gräns
// som inte finns, och gömt undan låtarna före 1950.
export function yearSpanLabel(room) {
  const bands = selectionFrom(room).bands
  if (!bands.length) return null
  const mins = bands.map((b) => b?.min ?? null)
  const maxs = bands.map((b) => b?.max ?? null)
  const lo = mins.some((m) => m === null) ? null : Math.min(...mins)
  const hi = maxs.some((m) => m === null) ? null : Math.max(...maxs)
  if (lo === null && hi === null) return null
  if (lo !== null && hi !== null) return `${lo}–${hi}`
  if (lo !== null) return `${lo} och framåt`
  return `till och med ${hi}`
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
