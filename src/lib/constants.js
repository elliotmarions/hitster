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
    color: 'gold',
    hex: '#ffc93c',
  },
  artist: {
    key: 'artist',
    label: 'Artisten',
    short: 'Artist',
    desc: 'Vem framför låten?',
    color: 'magenta',
    hex: '#ff2e9a',
  },
  exact_year: {
    key: 'exact_year',
    label: 'Exakt årtal',
    short: 'Årtal',
    desc: 'Ange exakt utgivningsår.',
    color: 'cyan',
    hex: '#22e6e6',
  },
  approx_year: {
    key: 'approx_year',
    label: 'Årtal ±3 år',
    short: '±3 år',
    desc: 'Gissa utgivningsåret – rätt inom ±3 år räknas.',
    color: 'lime',
    hex: '#b6ff3c',
  },
  title: {
    key: 'title',
    label: 'Låttiteln',
    short: 'Titel',
    desc: 'Vad heter låten?',
    color: 'disco',
    hex: '#b14dff',
  },
}

// Fast ordning – används bl.a. för brickans latinska kvadrat i Fas 2.
export const CATEGORY_ORDER = ['decade', 'artist', 'exact_year', 'approx_year', 'title']

export function categoryHex(key) {
  return CATEGORIES[key]?.hex ?? '#f4efff'
}

// Rumsstatus
export const ROOM_STATUS = {
  LOBBY: 'lobby',
  PLAYING: 'playing',
  FINISHED: 'finished',
}

// Realtidshändelser (broadcastas via room_events i senare faser)
export const EVENT_TYPES = {
  SPIN_RESULT: 'SPIN_RESULT',
  PLAY_COUNTDOWN: 'PLAY_COUNTDOWN',
  CROSS_MARKED: 'CROSS_MARKED',
  CROSS_ERASED: 'CROSS_ERASED',
  HITSTER_WIN: 'HITSTER_WIN',
}

// Hur en runda får sin låt (ställs in per rum i Fas 3).
export const SONG_SOURCE = {
  PLAYLIST: 'playlist', // Läge A – värdens egen Spotify-spellista
  MANUAL: 'manual', // Läge B – QR/manuell URI per kort
}

// Fas 2 – spelplanens tajming och mått
export const TIMER_SECONDS = 25 // rundans timer
export const SPIN_MS = 4200 // discokulans snurr-animation (matchar timer_start_at i spin_wheel)
export const GRID = 5 // brickan är 5x5 (en ruta per kategori i varje rad/kolumn)
