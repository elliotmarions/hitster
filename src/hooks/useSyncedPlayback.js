import { useEffect, useRef } from 'react'
import { TIMER_SECONDS } from '../lib/constants'

/**
 * Synkad uppspelning (Fas 4). Alla klienter startar samma låt vid `start_at`
 * (= rundans timer_start_at, en server-tidsstämpel) och pausar efter 25s-klippet.
 *
 * Synken bygger på att varje klient jämför start_at mot sin egen Date.now().
 * Klockor är normalt NTP-synkade inom några tiondelar → gott och väl inom den
 * ~0,5s tolerans som Hitster Bingo behöver. (Ingen musik skickas mellan klienter –
 * var och en spelar från sin EGEN Spotify. Se kärnprincipen i README.)
 *
 * Endast sidoeffekter (play/pause vid rätt tidpunkt); UI-fasen räknar GameView
 * ut från sin egen klocka.
 */
export function useSyncedPlayback(round, deviceReady, playTrack, pause) {
  const playedRef = useRef(0)
  const pausedRef = useRef(0)

  const roundNo = round?.round_number
  const trackUri = round?.current_track_id
  const hasTrack = Boolean(trackUri)
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null

  // Starta låten exakt vid start_at.
  useEffect(() => {
    if (!hasTrack || startMs == null || !deviceReady) return
    if (playedRef.current === roundNo) return
    const delay = startMs - Date.now()
    if (delay < -1500) return // för sent (t.ex. sen anslutning) – hoppa denna runda
    const id = setTimeout(() => {
      playedRef.current = roundNo
      playTrack(trackUri).catch(() => {})
    }, Math.max(0, delay))
    return () => clearTimeout(id)
  }, [roundNo, hasTrack, startMs, deviceReady, trackUri, playTrack])

  // Pausa när 25s-klippet är slut.
  useEffect(() => {
    if (!hasTrack || startMs == null) return
    if (pausedRef.current === roundNo) return
    const delay = startMs + TIMER_SECONDS * 1000 - Date.now()
    if (delay < 0) return
    const id = setTimeout(() => {
      pausedRef.current = roundNo
      pause?.()
    }, delay)
    return () => clearTimeout(id)
  }, [roundNo, hasTrack, startMs, pause])
}
