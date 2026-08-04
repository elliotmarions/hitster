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
//  Ett val bestämmer potten: en bred pott (Alla / Svenska), ett åldersspann
//  eller en genre. Man väljer exakt en av dem.
//
//  UNDANTAG – "bara svenska" är en MODIFIERARE. Den kan läggas ovanpå ett
//  åldersspann eller en genre ("20–29 år, bara svenska låtar"). Servern
//  klarade alltid det: start_random_track AND:ar sv, årsfönster och genre
//  som tre oberoende villkor. Det var bara den här listan som beskrev dem
//  som ömsesidigt uteslutande. Kombinationen kan bli tunn (svenska + 20–29
//  är 90 låtar), så lobbyn visar antalet via track_pool_selection_count().
//
//  Åldersspannen bygger på "reminiscensbågen": man känner igen och älskar
//  starkast musiken som var populär när man var ca 14–24 år, så en åldersgrupp
//  mappas till ERAN gruppen var ung – inte "låtar från de åren". Fönstren är
//  medvetet lite bredare (~15 år) så varje grupp har gott om låtar. Ref-år: 2026.
//
//  Varje kategori sätter tre fält på rummet: swedish_mode + year_min/year_max
//  (min/max = null → ingen årsgräns). Filtreras server-side i start_random_track
//  (potten är oläsbar för klienter). `pot` = vilken räknare som visas (all/sv);
//  åldersspannen är delmängder av världspotten och saknar egen räknare.
//  `group` styr bara den visuella uppdelningen i lobbyn: 'broad' (Alla/Svenska),
//  'age' (åldersspannen) och 'genre' – de är fortfarande ETT val, bara avskilda.
//
//  Genrerna filtrerar på track_pool.genre via _genre_key() server-side (0043).
//  Deezers etiketter är grova, så mappningen slår ihop det folk ändå uppfattar
//  som samma sak – "Alternativmusik" och "Metal" ligger under Rock. Antalen
//  hämtas live från track_pool_genre_counts(), inte hårdkodade, eftersom potten
//  växer.
//  MULTIVAL (0057): varje chip väljs av och på fritt.
//    union INOM en dimension  – "20–29 år" + "30–39 år" = låtar ur endera
//    snitt MELLAN dimensioner – ålder + genre = låtar som är båda
//    tom dimension            – ingen gräns alls på den dimensionen
//  Inget valt = hela potten. Svenska är numera en chip som alla andra:
//  vald = bara svenska, ovald = ingen språkgräns (inte "allt utom svenskt",
//  vilket var innebörden före 0057).
export const POOL_CATEGORIES = [
  { key: 'sv', group: 'lang', label: 'Svenska', hint: 'Bara svenska artister', swedish: true, neon: '#ffd23f' },
  { key: 'intl', group: 'lang', label: '🌍 Utländska', hint: 'Allt utom svenskt', swedish: false, neon: '#22e6e6' },
  { key: '20s', group: 'age', label: '20–29 år', hint: 'Uppväxthits ~2008–idag', min: 2008, max: null, neon: '#ff4d9d' },
  { key: '30s', group: 'age', label: '30–39 år', hint: 'Uppväxthits ~1997–2011', min: 1997, max: 2011, neon: '#b14dff' },
  { key: '40s', group: 'age', label: '40–49 år', hint: 'Uppväxthits ~1987–2001', min: 1987, max: 2001, neon: '#3ee87b' },
  { key: '50s', group: 'age', label: '50–59 år', hint: 'Uppväxthits ~1977–1991', min: 1977, max: 1991, neon: '#ff8a3c' },
  { key: '60s', group: 'age', label: '60–69 år', hint: 'Uppväxthits ~1967–1981', min: 1967, max: 1981, neon: '#33a6ff' },
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

const sammaBand = (b, cat) => (b?.min ?? null) === cat.min && (b?.max ?? null) === cat.max

// Är den här chippen vald just nu?
export function isSelected(room, cat) {
  const s = selectionFrom(room)
  if (cat.group === 'lang') return s.swedish === cat.swedish
  if (cat.group === 'age') return s.bands.some((b) => sammaBand(b, cat))
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
  if (cat.group === 'age') {
    const finns = s.bands.some((b) => sammaBand(b, cat))
    return {
      swedish_mode: s.swedish,
      year_bands: finns
        ? s.bands.filter((b) => !sammaBand(b, cat))
        : [...s.bands, { min: cat.min, max: cat.max }],
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

// En läsbar sammanfattning av valet, t.ex. "Svenska · 20–29 år, 30–39 år · Pop".
// Ersätter poolCategoryFor(), som byggde på att rummet stod på EXAKT en
// kategori – ett antagande som inte längre håller efter 0057.
export function selectionLabel(room) {
  const s = selectionFrom(room)
  if (selectionEmpty(room)) return 'Alla låtar'
  const delar = []
  if (s.swedish === true) delar.push('Svenska')
  else if (s.swedish === false) delar.push('Utländska')
  const ald = POOL_CATEGORIES.filter(
    (c) => c.group === 'age' && s.bands.some((b) => sammaBand(b, c)),
  ).map((c) => c.label)
  if (ald.length) delar.push(ald.join(', '))
  const gen = POOL_CATEGORIES.filter(
    (c) => c.group === 'genre' && s.genres.includes(c.genre),
  ).map((c) => c.label)
  if (gen.length) delar.push(gen.join(', '))
  return delar.join(' · ')
}
