import { useCallback, useEffect, useRef, useState } from 'react'
import { SING_FACIT_SECONDS } from '../lib/constants'
import { useVolume } from '../context/VolumeContext.jsx'
import { serverNow, syncServerTime } from '../lib/serverTime'

// Samma tysta upplåsningsklipp som useSyncedAudio – se kommentaren där.
const SILENCE =
  'data:audio/wav;base64,UklGRnQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YVAAAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA=='

/**
 * Ljudet i Sjung vidare. Två delar per tur, båda synkade mot serverns klocka:
 *
 *   Början  klippet spelas från 0 vid timer_start_at och tystnar vid
 *           sing_cut_at sekunder. Där ska laget ta över.
 *   Facit   när värden spelar facit fortsätter klippet FRÅN SAMMA STÄLLE vid
 *           sing_reveal_at, i SING_FACIT_SECONDS sekunder.
 *
 * Kommer man in sent spolas klippet fram till där de andra är, så länge det
 * finns något vettigt kvar att höra av delen.
 *
 * Returnerar { ready, unlock, error, volume, setVolume } som useSyncedAudio.
 */
export function useSingAudio(round) {
  const audioRef = useRef(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState('')
  const unlockedRef = useRef(false)
  const playedRef = useRef('') // "<rund-id>:<del>" som faktiskt kommit igång
  const { volume, setVolume } = useVolume()
  const volumeRef = useRef(volume)

  function getAudio() {
    if (!audioRef.current) {
      const a = new Audio()
      a.preload = 'auto'
      a.volume = volumeRef.current
      audioRef.current = a
    }
    return audioRef.current
  }

  useEffect(() => {
    volumeRef.current = volume
    if (audioRef.current) audioRef.current.volume = volume
  }, [volume])

  useEffect(() => {
    syncServerTime()
  }, [])

  const unlock = useCallback(async () => {
    if (unlockedRef.current) return true
    const a = getAudio()
    // Ligger en riktig låt redan i elementet ska gesten inte skriva över den.
    const hasClip = a.src && !a.src.startsWith('data:')
    try {
      if (!hasClip) a.src = SILENCE
      await a.play()
      if (!hasClip) {
        a.pause()
        a.currentTime = 0
      }
      unlockedRef.current = true
      setReady(true)
      return true
    } catch {
      return false
    }
  }, [])

  useEffect(() => {
    unlock()
  }, [unlock])

  useEffect(() => {
    if (ready) return undefined
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

  const roundId = round?.id ?? null
  const url = round?.current_track_id ?? null
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const cutAt = round?.sing_cut_at != null ? Number(round.sing_cut_at) : null
  const revealMs = round?.sing_reveal_at ? new Date(round.sing_reveal_at).getTime() : null

  // Spela en del av klippet: från `from` sekunder in i klippet, med start vid
  // `atMs` (serverklocka), i `length` sekunder.
  function schedule(key, atMs, from, length) {
    if (playedRef.current === key) return () => {}
    const a = getAudio()
    if (a.src !== url) {
      a.src = url
      a.load()
    }
    let stopId = null
    const go = () => {
      const late = Math.max(0, (serverNow() - atMs) / 1000)
      if (late > length - 1) return // för sent för att det ska vara värt det
      try {
        a.currentTime = from + late
      } catch {
        /* inte sökbar än – spelar från där den är */
      }
      setError('')
      a.play().then(
        () => {
          playedRef.current = key
          const left = atMs + length * 1000 - serverNow()
          stopId = setTimeout(() => a.pause(), Math.max(0, left))
        },
        (e) => {
          if (e?.name === 'NotAllowedError') {
            unlockedRef.current = false
            setReady(false)
          }
          setError('Kunde inte spela ljudet – klicka "Aktivera ljud" och försök igen.')
        },
      )
    }
    const startId = setTimeout(go, Math.max(0, atMs - serverNow()))
    return () => {
      clearTimeout(startId)
      if (stopId) clearTimeout(stopId)
    }
  }

  // Början: 0 → stoppunkten.
  useEffect(() => {
    if (!roundId || !url || startMs == null || cutAt == null || revealMs != null) return undefined
    return schedule(`${roundId}:start`, startMs, 0, cutAt)
    // `ready`: en upplåsning mitt i början ska dra igång klippet.
  }, [roundId, url, startMs, cutAt, revealMs, ready])

  // Facit: stoppunkten → stoppunkten + SING_FACIT_SECONDS. Början tystas först,
  // om den av någon anledning fortfarande ljuder.
  useEffect(() => {
    if (!roundId || !url || cutAt == null || revealMs == null) return undefined
    if (audioRef.current && playedRef.current === `${roundId}:start`) audioRef.current.pause()
    return schedule(`${roundId}:facit`, revealMs, cutAt, SING_FACIT_SECONDS)
  }, [roundId, url, cutAt, revealMs, ready])

  // Ny tur: tysta det som eventuellt hänger kvar från förra.
  useEffect(() => {
    if (audioRef.current) audioRef.current.pause()
  }, [roundId])

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
