import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Prenumererar på ett rums spel-tillstånd i realtid (Fas 2):
 *   - round: senaste rundan (discokulans kategori + timer)
 *   - cards: alla spelares brickor (full insyn)
 *
 * Samma mönster som useRoom: vid varje Postgres-förändring hämtar vi om
 * relevant data, så allas vy hålls i synk (snurr, kryss, sudd).
 */
export function useGame(roomId) {
  const [round, setRound] = useState(null)
  const [cards, setCards] = useState([])
  const [loading, setLoading] = useState(true)

  const fetchRound = useCallback(async (rid) => {
    const { data } = await supabase
      .from('rounds')
      .select('*')
      .eq('room_id', rid)
      .order('round_number', { ascending: false })
      .limit(1)
    setRound(data?.[0] ?? null)
  }, [])

  const fetchCards = useCallback(async (rid) => {
    const { data } = await supabase
      .from('bingo_cards')
      .select('*')
      .eq('room_id', rid)
      .order('created_at', { ascending: true })
    setCards(data ?? [])
  }, [])

  useEffect(() => {
    if (!supabase || !roomId) {
      setLoading(false)
      return
    }
    let cancelled = false
    let channel = null

    ;(async () => {
      setLoading(true)
      await Promise.all([fetchRound(roomId), fetchCards(roomId)])
      if (cancelled) return
      setLoading(false)

      channel = supabase
        .channel(`game:${roomId}`)
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` },
          () => fetchRound(roomId),
        )
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'bingo_cards', filter: `room_id=eq.${roomId}` },
          () => fetchCards(roomId),
        )
        .subscribe()
    })()

    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [roomId, fetchRound, fetchCards])

  return { round, cards, loading }
}
