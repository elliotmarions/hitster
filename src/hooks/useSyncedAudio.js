import { useCallback, useEffect, useRef, useState } from 'react'
import { TIMER_SECONDS } from '../lib/constants'
import { serverNow, syncServerTime } from '../lib/serverTime'

// Kort tyst klipp – spelas vid "Aktivera ljud"-klicket för att låsa upp
// <audio>-elementet så att senare automatiska starter (via realtidshändelsen,
// utan eget klick) får ljuda trots webbläsarens autoplay-spärr.
const SILENCE =
  'data:audio/wav;base64,UklGRnQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YVAAAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA=='

// Volymen är LOKAL per enhet (varje spelare spelar sitt eget klipp – inget
// synkas) och sparas mellan spel. 0–1.
//
// NIVÅN sparas, men inte MUTNINGEN. Noll är inte en nivå utan ett tillstånd
// för stunden ("tyst nu, någon ringer"), och sparades den vaknade appen tyst
// nästa spelkväll också. Enda signalen var en liten 🔇-ikon i scenens hörn, så
// det såg ut precis som den här buggen: allt fungerar, ingen låt hörs.
const VOLUME_KEY = 'hbo:volume'
function rememberedVolume() {
  try {
    const v = parseFloat(localStorage.getItem(VOLUME_KEY))
    // <= 0 kan bara komma från en gammal sparad mutning – börja med ljud på.
    return Number.isFinite(v) && v > 0 ? Math.min(1, v) : 1
  } catch {
    return 1
  }
}

// Hur mycket klippet får ligga fel innan vi spolar. Under detta hörs ingen
// skillnad, och en onödig sökning hackar till ljudet.
const DRIFT_TOLERANCE = 0.35

// Spola till den position alla andra är på just nu. Delas av startlogiken och
// av upplåsningen (som kan komma flera sekunder in i klippet).
function seekToLive(a, startMs) {
  const target = (serverNow() - startMs) / 1000
  if (!Number.isFinite(target) || target < DRIFT_TOLERANCE) return
  if (target >= TIMER_SECONDS - 0.5) return
  if (Math.abs(a.currentTime - target) < DRIFT_TOLERANCE) return
  try {
    a.currentTime = target
  } catch {
    /* inte sökbar än – 'playing'-korrigeringen tar det */
  }
}

/**
 * Synkad uppspelning av ett preview-klipp (ersätter Spotify Web Playback).
 * Alla klienter spelar samma publika ljud-URL (round.current_track_id) vid
 * `start_at` (= timer_start_at) och pausar efter 25s. Tidpunkten jämförs mot
 * SERVERNS klocka (se lib/serverTime.js) – inte enhetens egen, som kan gå
 * flera sekunder fel. Inget ljud skickas mellan spelare.
 *
 * Kommer man ändå igång sent (buffring, sen anslutning) spolas klippet fram
 * till den position alla andra är på, i stället för att börja om från noll –
 * annars blir en sen start permanent efter i hela klippet.
 *
 * Returnerar { ready, unlock, error }:
 *   ready  – är ljudet FAKTISKT upplåst i den här sidladdningen?
 *   unlock – anropa från ett användarklick för att låsa upp autoplay.
 *   error  – senaste uppspelningsfel (för diagnostik i UI).
 */
export function useSyncedAudio(round) {
  const audioRef = useRef(null)
  const playedRef = useRef(0)
  const pausedRef = useRef(0)
  const unlockedRef = useRef(false)
  // OBS: speglar det verkliga tillståndet för DEN HÄR sidladdningen. Tidigare
  // initierades detta från localStorage ("du har aktiverat ljud förr"), vilket
  // gömde bannern trots att <audio>-elementet var låst – spelaren trodde att
  // allt var klart och hörde sedan ingenting första rundan. Upplåsningen gäller
  // per sidladdning och kan inte sparas, så den får inte heller låtsas sparas.
  const [ready, setReady] = useState(false)
  const [error, setError] = useState('')
  const [volume, setVolumeState] = useState(rememberedVolume)
  const volumeRef = useRef(volume) // senaste volymen åt lazily skapade element

  function getAudio() {
    if (!audioRef.current) {
      const a = new Audio()
      a.preload = 'auto'
      a.volume = volumeRef.current
      audioRef.current = a
    }
    return audioRef.current
  }

  // Justera volymen (0–1): applicera live, spara per enhet, minns för nya element.
  const setVolume = useCallback((v) => {
    const clamped = Math.min(1, Math.max(0, Number(v) || 0))
    volumeRef.current = clamped
    setVolumeState(clamped)
    if (audioRef.current) audioRef.current.volume = clamped
    try {
      // Bara riktiga nivåer sparas – en mutning gäller den här sidladdningen.
      if (clamped > 0) localStorage.setItem(VOLUME_KEY, String(clamped))
    } catch {
      /* privat läge e.d. – strunt samma */
    }
  }, [])

  // Mät klockskillnaden mot servern en gång per sidladdning.
  useEffect(() => {
    syncServerTime()
  }, [])

  // Rundans klipp, läsbart från upplåsningen (som inte får se bara det som
  // gällde när den skapades).
  const liveRef = useRef({ url: null, startMs: null, revealed: false })

  // Lås upp <audio> (spela tyst klipp → pausa). Anropas från ett användarklick,
  // men provas också direkt vid montering: har webbläsaren redan gett appen
  // autoplay-rätt slipper spelaren bannern helt.
  //
  // Upplåsningen och musiken MÅSTE dela element – iOS låser upp per element,
  // inte per sida. Därför får den heller aldrig skriva över ett laddat klipp
  // med tystnaden: gesten kommer typiskt EFTER att rundans låt nekats, och
  // spelade vi tystnaden då försvann låt-URL:en ur elementet och ingenting
  // startade om den. Ligger rundans klipp redan i elementet spelar vi det i
  // stället – då blir gesten det "försök igen" som felmeddelandet lovar.
  const unlock = useCallback(async () => {
    if (unlockedRef.current) return true
    const a = getAudio()
    const live = liveRef.current
    const inClip =
      Boolean(live.url) &&
      live.startMs != null &&
      !live.revealed &&
      a.src === live.url &&
      serverNow() < live.startMs + TIMER_SECONDS * 1000
    try {
      if (inClip) {
        seekToLive(a, live.startMs)
      } else {
        a.src = SILENCE
      }
      await a.play()
      // Bara städa om ingen riktig låt hunnit ta över elementet under tiden.
      if (!inClip && a.src === SILENCE) {
        a.pause()
        a.currentTime = 0
      }
      unlockedRef.current = true
      setReady(true)
      if (inClip) setError('')
      return true
    } catch {
      // Blockerat – bannern får stå kvar tills en riktig användargest kommer.
      return false
    }
  }, [])

  // Tyst försök vid montering (ingen banner blinkar till i onödan om det går).
  useEffect(() => {
    unlock()
  }, [unlock])

  // Första användargesten var som helst i appen låser upp ljudet, så man
  // slipper träffa just "Aktivera ljud"-knappen. Effekten armas om varje gång
  // `ready` faller tillbaka till false (t.ex. om en uppspelning ändå nekas).
  useEffect(() => {
    if (ready) return
    const onGesture = () => unlock()
    const opts = { once: true, capture: true }
    window.addEventListener('pointerdown', onGesture, opts)
    window.addEventListener('keydown', onGesture, opts)
    window.addEventListener('touchstart', onGesture, opts)
    return () => {
      window.removeEventListener('pointerdown', onGesture, opts)
      window.removeEventListener('keydown', onGesture, opts)
      window.removeEventListener('touchstart', onGesture, opts)
    }
  }, [ready, unlock])

  const url = round?.current_track_id
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const roundNo = round?.round_number
  // Rundan är avgjord i förtid: alla har låst in sina svar (eller värden tryckte
  // "Visa svar nu") innan de 25 sekunderna gått. Då ska musiken tystna direkt –
  // annars ligger klippet och spelar över facit.
  const revealed = Boolean(round?.answers_revealed)

  // Håll upplåsningen underrättad om vilken låt som gäller just nu.
  liveRef.current = { url: url ?? null, startMs, revealed }

  // Starta klippet exakt vid start_at.
  useEffect(() => {
    if (!url || startMs == null) return
    // Avslöjad runda → starta inte alls, och cleanup avbryter en redan schemalagd
    // start (t.ex. om alla hann låsa in under nedräkningen).
    if (revealed) return
    if (playedRef.current === roundNo) return
    const delay = startMs - serverNow()
    // Kommer vi in mitt i klippet spolar vi fram i stället för att hoppa över
    // rundan – men bara om det är någon vettig stund kvar att lyssna på.
    if (-delay / 1000 > TIMER_SECONDS - 3) return
    const a = getAudio()
    if (a.src !== url) {
      a.src = url
      a.load() // börja buffra nu, inte först vid play()
    }

    // En sökning innan play() fastnar inte alltid (klippet kan sakna metadata
    // än), så vi korrigerar en gång till så fort ljudet faktiskt rullar.
    const onPlaying = () => seekToLive(a, startMs)
    a.addEventListener('playing', onPlaying, { once: true })

    const id = setTimeout(() => {
      // Bara från noll om inget redan rullar – upplåsningen kan ha dragit
      // igång klippet mitt i, och då ska vi inte rycka tillbaka det.
      if (a.paused) a.currentTime = 0
      seekToLive(a, startMs)
      setError('')
      a.play().then(
        () => {
          // Rundan räknas som spelad först när den FAKTISKT rullar. Stämplades
          // den redan vid försöket var en nekad uppspelning slutgiltig: spelaren
          // klickade "Aktivera ljud" som appen bad om, och ingenting hände –
          // hela rundan gick i tystnad och fick blindgissas.
          playedRef.current = roundNo
        },
        (e) => {
          // Nekad uppspelning = ljudet var aldrig upplåst. Ta tillbaka bannern
          // i stället för att bara visa en felrad.
          if (e?.name === 'NotAllowedError') {
            unlockedRef.current = false
            setReady(false)
          }
          setError(
            'Kunde inte spela ljudet (' + (e?.name || 'fel') + ') – klicka "Aktivera ljud" och försök igen.',
          )
        },
      )
    }, Math.max(0, delay))

    return () => {
      clearTimeout(id)
      a.removeEventListener('playing', onPlaying)
    }
    // `ready` är med för att en lyckad upplåsning MITT i en runda ska starta
    // klippet (från rätt position) i stället för att rundan är förlorad.
  }, [roundNo, url, startMs, revealed, ready])

  // Tysta klippet i samma ögonblick rundan avslöjas (alla låste in i förtid).
  // pausedRef/playedRef sätts till rundan så varken 25s-pausen eller en ny
  // start-effekt gör något mer med den här rundan.
  useEffect(() => {
    if (!revealed || roundNo == null) return
    playedRef.current = roundNo
    pausedRef.current = roundNo
    if (audioRef.current) audioRef.current.pause()
  }, [revealed, roundNo])

  // Pausa när 25s-klippet är slut.
  useEffect(() => {
    if (!url || startMs == null) return
    if (pausedRef.current === roundNo) return
    const delay = startMs + TIMER_SECONDS * 1000 - serverNow()
    if (delay < 0) return
    const id = setTimeout(() => {
      pausedRef.current = roundNo
      getAudio().pause()
    }, delay)
    return () => clearTimeout(id)
  }, [roundNo, url, startMs])

  // Städa upp ljudet när hooken avmonteras.
  useEffect(() => {
    return () => {
      if (audioRef.current) {
        audioRef.current.pause()
        audioRef.current = null
      }
    }
  }, [])

  return { ready, unlock, error, volume, setVolume }
}
