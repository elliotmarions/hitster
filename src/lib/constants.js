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
export const POOL_CATEGORIES = [
  { key: 'all', group: 'broad', label: '🌍 Alla låtar', hint: 'Blandat från hela världen', swedish: false, min: null, max: null, neon: '#22e6e6', pot: 'all' },
  { key: 'sv', group: 'broad', label: 'Svenska', hint: 'Svenska artister, 1950–idag', swedish: true, min: null, max: null, neon: '#ffd23f', pot: 'sv' },
  { key: '20s', group: 'age', label: '20–29 år', hint: 'Uppväxthits ~2008–idag', swedish: false, min: 2008, max: null, neon: '#ff4d9d' },
  { key: '30s', group: 'age', label: '30–39 år', hint: 'Uppväxthits ~1997–2011', swedish: false, min: 1997, max: 2011, neon: '#b14dff' },
  { key: '40s', group: 'age', label: '40–49 år', hint: 'Uppväxthits ~1987–2001', swedish: false, min: 1987, max: 2001, neon: '#3ee87b' },
  { key: '50s', group: 'age', label: '50–59 år', hint: 'Uppväxthits ~1977–1991', swedish: false, min: 1977, max: 1991, neon: '#ff8a3c' },
  { key: '60s', group: 'age', label: '60–69 år', hint: 'Uppväxthits ~1967–1981', swedish: false, min: 1967, max: 1981, neon: '#33a6ff' },
  { key: 'pop', group: 'genre', label: 'Pop', swedish: false, min: null, max: null, genre: 'pop', neon: '#ff4d9d' },
  { key: 'rock', group: 'genre', label: 'Rock', swedish: false, min: null, max: null, genre: 'rock', neon: '#ff8a3c' },
  { key: 'hiphop', group: 'genre', label: 'Hiphop', swedish: false, min: null, max: null, genre: 'hiphop', neon: '#b6ff3c' },
  { key: 'dance', group: 'genre', label: 'Dance', swedish: false, min: null, max: null, genre: 'dance', neon: '#22e6e6' },
  { key: 'rnb', group: 'genre', label: 'R&B', swedish: false, min: null, max: null, genre: 'rnb', neon: '#b14dff' },
]

// Vilken pott-kategori rummet står på just nu. Ordningen spelar roll: genre
// först (den nollställer årsfönstret så ett genrerum annars hade matchat
// "Alla låtar"), sedan årsspannen, sist de breda potterna.
//
// swedish_mode läses INTE här längre – den är en modifierare som kan ligga
// ovanpå ett åldersspann eller en genre, se swedishOnly(). Läste vi den
// först skulle "20–29 år + bara svenska" visa Svenska som markerad kategori
// och åldersknappen som omarkerad, fast rummet står på båda.
export function poolCategoryFor(room) {
  if (room?.genre) {
    return POOL_CATEGORIES.find((c) => c.genre === room.genre) || POOL_CATEGORIES[0]
  }
  const min = room?.year_min ?? null
  const max = room?.year_max ?? null
  if (min !== null || max !== null) {
    return (
      POOL_CATEGORIES.find((c) => c.group === 'age' && c.min === min && c.max === max) ||
      POOL_CATEGORIES[0]
    )
  }
  if (room?.swedish_mode) return POOL_CATEGORIES.find((c) => c.key === 'sv')
  return POOL_CATEGORIES[0]
}

// Modifieraren: står rummet på bara svenska låtar? Gäller oavsett om
// kategorin är en bred pott, ett åldersspann eller en genre.
export function swedishOnly(room) {
  return !!room?.swedish_mode
}
