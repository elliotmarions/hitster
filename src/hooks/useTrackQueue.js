import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchPlaylistTracks, shuffle } from '../lib/spotifyApi'

/**
 * Värdens spellist-kö (Läge A): hämtar spellistan via Spotify, blandar den och
 * delar ut EN låt per snurr. Kön ligger i värdens klient (host är auktoritativ
 * för rummet). Vid host-refresh hämtas/blandas listan på nytt.
 */
export function useTrackQueue(room, isHost, connected) {
  const [count, setCount] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const tracksRef = useRef([])
  const idxRef = useRef(0)
  const loadedFor = useRef(null)

  useEffect(() => {
    if (!isHost || !connected || !room?.playlist_uri) return
    if (loadedFor.current === room.playlist_uri) return
    loadedFor.current = room.playlist_uri
    setLoading(true)
    setError('')
    fetchPlaylistTracks(room.playlist_uri)
      .then((list) => {
        tracksRef.current = shuffle(list)
        idxRef.current = 0
        setCount(list.length)
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false))
  }, [isHost, connected, room?.playlist_uri])

  // Nästa låt ur kön (går runt om man snurrat fler gånger än det finns låtar).
  const nextTrack = useCallback(() => {
    const list = tracksRef.current
    if (!list.length) return null
    const track = list[idxRef.current % list.length]
    idxRef.current += 1
    return track
  }, [])

  return { count, loading, error, nextTrack }
}
