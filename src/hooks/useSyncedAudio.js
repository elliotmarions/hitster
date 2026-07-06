import { useCallback, useEffect, useRef, useState } from 'react'
import { TIMER_SECONDS } from '../lib/constants'

// Kort tyst klipp – spelas vid "Aktivera ljud"-klicket för att låsa upp
// <audio>-elementet så att senare automatiska starter (via realtidshändelsen,
// utan eget klick) får ljuda trots webbläsarens autoplay-spärr.
const SILENCE =
  'data:audio/wav;base64,UklGRnQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YVAAAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA=='

/**
 * Synkad uppspelning av ett preview-klipp (ersätter Spotify Web Playback).
 * Alla klienter spelar samma publika ljud-URL (round.current_track_id) vid
 * `start_at` (= timer_start_at) och pausar efter 25s. Klockan jämförs mot
 * egen Date.now() – klienter är NTP-synkade inom tiondelar, gott och väl inom
 * spelets tolerans. Inget ljud skickas mellan spelare.
 *
 * Returnerar { ready, unlock, error }:
 *   ready  – har användaren låst upp ljudet (klickat "Aktivera ljud")?
 *   unlock – anropa från ett användarklick för att låsa upp autoplay.
 *   error  – senaste uppspelningsfel (för diagnostik i UI).
 */
export function useSyncedAudio(round) {
  const audioRef = useRef(null)
  const playedRef = useRef(0)
  const pausedRef = useRef(0)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState('')

  function getAudio() {
    if (!audioRef.current) {
      const a = new Audio()
      a.preload = 'auto'
      audioRef.current = a
    }
    return audioRef.current
  }

  // Lås upp <audio> inifrån ett användarklick (spela tyst klipp → pausa).
  const unlock = useCallback(async () => {
    const a = getAudio()
    try {
      a.src = SILENCE
      await a.play()
      a.pause()
      a.currentTime = 0
    } catch {
      // Även om detta kastar räknas klicket som användargest på de flesta
      // webbläsare → markera som upplåst ändå.
    }
    setReady(true)
  }, [])

  const url = round?.current_track_id
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const roundNo = round?.round_number

  // Starta klippet exakt vid start_at.
  useEffect(() => {
    if (!url || startMs == null) return
    if (playedRef.current === roundNo) return
    const delay = startMs - Date.now()
    if (delay < -1500) return // för sent (sen anslutning) – hoppa denna runda
    const a = getAudio()
    if (a.src !== url) a.src = url
    const id = setTimeout(() => {
      playedRef.current = roundNo
      a.currentTime = 0
      setError('')
      a.play().catch((e) => {
        setError(
          'Kunde inte spela ljudet (' + (e?.name || 'fel') + ') – klicka "Aktivera ljud" och försök igen.',
        )
      })
    }, Math.max(0, delay))
    return () => clearTimeout(id)
  }, [roundNo, url, startMs])

  // Pausa när 25s-klippet är slut.
  useEffect(() => {
    if (!url || startMs == null) return
    if (pausedRef.current === roundNo) return
    const delay = startMs + TIMER_SECONDS * 1000 - Date.now()
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

  return { ready, unlock, error }
}
