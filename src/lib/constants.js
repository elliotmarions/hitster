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

// Lagläge – neonfärger som tilldelas lag i tur och ordning.
export const TEAM_COLORS = ['#22e6e6', '#ff4d9d', '#b6ff3c', '#ffc93c', '#b14dff', '#ff8a3c']

// Fas 2 – spelplanens tajming och mått
export const TIMER_SECONDS = 25 // rundans timer
export const SPIN_MS = 4200 // discokulans snurr-animation (matchar timer_start_at i spin_wheel)
export const GRID = 5 // brickan är 5x5 (fritt slumpad, exakt 5 rutor per kategori)

// ============================================================
//  Åldersgrupper – riktar låtpotten mot ett årsfönster
// ============================================================
//
//  Bygger på "reminiscensbågen": man känner igen och älskar starkast den
//  musik som var populär när man var ca 14–24 år. Så en åldersgrupp mappas
//  INTE till "låtar från de åren" utan till ERAN då gruppen var ung.
//  Fönstren är medvetet lite bredare (~15 år) så varje grupp har gott om
//  låtar och slipper repriser. Referensår: 2026.
//
//  min/max = null → ingen gräns (t.ex. "Blandat" = hela potten, 20–29 = allt
//  från 2008 och framåt inkl. dagens hits). Lagras som rooms.year_min/max och
//  filtreras server-side i start_random_track (potten är oläsbar för klienter).
export const AGE_GROUPS = [
  { key: 'all', label: 'Blandat', hint: 'Alla åldrar · hela potten', min: null, max: null },
  { key: '20s', label: '20–29 år', hint: 'Uppväxthits ~2008–idag', min: 2008, max: null },
  { key: '30s', label: '30–39 år', hint: 'Uppväxthits ~1997–2011', min: 1997, max: 2011 },
  { key: '40s', label: '40–49 år', hint: 'Uppväxthits ~1987–2001', min: 1987, max: 2001 },
  { key: '50s', label: '50–59 år', hint: 'Uppväxthits ~1977–1991', min: 1977, max: 1991 },
  { key: '60s', label: '60–69 år', hint: 'Uppväxthits ~1967–1981', min: 1967, max: 1981 },
]

// Hittar vald åldersgrupp utifrån rummets sparade årsfönster.
export function ageGroupFor(room) {
  const min = room?.year_min ?? null
  const max = room?.year_max ?? null
  return AGE_GROUPS.find((g) => g.min === min && g.max === max) || AGE_GROUPS[0]
}
