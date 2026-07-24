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
}

// Fast ordning – t.ex. discokulans segment.
export const CATEGORY_ORDER = ['decade', 'artist', 'exact_year', 'approx_year', 'title']

// Åldersläge (rummet har ett årsfönster): årtionde + ±3 blir för lätt när eran
// redan är smal, så de byts mot en enda tightare årtals-kategori (±1). Fyra
// kategorier på snurran och brickan. MÅSTE spegla serverns _room_categories.
export const AGE_CATEGORY_ORDER = ['exact_year', 'artist', 'title', 'approx_year_1']

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
//  Ett enda val bestämmer hela potten. Antingen en bred pott (Alla / Svenska)
//  eller ett åldersspann som riktar världspotten mot en era. De är sidoordnade
//  val – man väljer exakt ett, inte "musik först och sedan ålder".
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
//  `group` styr bara den visuella uppdelningen i lobbyn: 'broad' (Alla/Svenska)
//  och 'age' (åldersspannen) – de är fortfarande ETT val, bara avskilda.
export const POOL_CATEGORIES = [
  { key: 'all', group: 'broad', label: '🌍 Alla låtar', hint: 'Blandat från hela världen', swedish: false, min: null, max: null, neon: '#22e6e6', pot: 'all' },
  { key: 'sv', group: 'broad', label: 'Svenska', hint: 'Svenska artister, 1950–idag', swedish: true, min: null, max: null, neon: '#ffd23f', pot: 'sv' },
  { key: '20s', group: 'age', label: '20–29 år', hint: 'Uppväxthits ~2008–idag', swedish: false, min: 2008, max: null, neon: '#ff4d9d' },
  { key: '30s', group: 'age', label: '30–39 år', hint: 'Uppväxthits ~1997–2011', swedish: false, min: 1997, max: 2011, neon: '#b14dff' },
  { key: '40s', group: 'age', label: '40–49 år', hint: 'Uppväxthits ~1987–2001', swedish: false, min: 1987, max: 2001, neon: '#3ee87b' },
  { key: '50s', group: 'age', label: '50–59 år', hint: 'Uppväxthits ~1977–1991', swedish: false, min: 1977, max: 1991, neon: '#ff8a3c' },
  { key: '60s', group: 'age', label: '60–69 år', hint: 'Uppväxthits ~1967–1981', swedish: false, min: 1967, max: 1981, neon: '#33a6ff' },
]

// Vilken pott-kategori rummet står på just nu. Svenska är sin egen kategori
// (årsfönstret ignoreras då); annars matchas årsfönstret mot ett åldersspann.
export function poolCategoryFor(room) {
  if (room?.swedish_mode) return POOL_CATEGORIES.find((c) => c.key === 'sv')
  const min = room?.year_min ?? null
  const max = room?.year_max ?? null
  return (
    POOL_CATEGORIES.find((c) => !c.swedish && c.min === min && c.max === max) ||
    POOL_CATEGORIES[0]
  )
}
