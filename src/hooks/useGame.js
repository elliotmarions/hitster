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
  const [answers, setAnswers] = useState([])
  const [facit, setFacit] = useState(null)
  const [loading, setLoading] = useState(true)

  const fetchRound = useCallback(async (rid) => {
    const { data } = await supabase
      .from('rounds')
      .select('*')
      .eq('room_id', rid)
      .order('round_number', { ascending: false })
      .limit(1)
    const r = data?.[0] ?? null
    setRound(r)

    // Facit ligger i round_tracks, som RLS öppnar först när rundan avslöjats –
    // före dess finns det ingenting att läsa (inte ens via devtools).
    if (r?.answers_revealed) {
      const { data: rt } = await supabase
        .from('round_tracks')
        .select('meta')
        .eq('round_id', r.id)
        .maybeSingle()
      // Fallback till gamla kolumnen för rundor startade före server-side-bytet.
      setFacit(rt?.meta ?? r.current_track_meta ?? null)
    } else {
      setFacit(null)
    }
  }, [])

  const fetchCards = useCallback(async (rid) => {
    const { data } = await supabase
      .from('bingo_cards')
      .select('*')
      .eq('room_id', rid)
      .order('created_at', { ascending: true })
    setCards(data ?? [])
  }, [])

  // Svar syns via RLS bara för det egna laget tills rundan avslöjats – då
  // hämtar vi om (triggas av rounds-ändringen answers_revealed) och får allas.
  const fetchAnswers = useCallback(async (rid) => {
    const { data } = await supabase
      .from('round_answers')
      .select('*')
      .eq('room_id', rid)
      .order('created_at', { ascending: true })
    setAnswers(data ?? [])
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
      await Promise.all([fetchRound(roomId), fetchCards(roomId), fetchAnswers(roomId)])
      if (cancelled) return
      setLoading(false)

      channel = supabase
        .channel(`game:${roomId}`)
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` },
          () => {
            // Rundan kan ha ändrat answers_revealed/locked_count → hämta även svaren.
            fetchRound(roomId)
            fetchAnswers(roomId)
          },
        )
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'bingo_cards', filter: `room_id=eq.${roomId}` },
          () => fetchCards(roomId),
        )
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'round_answers', filter: `room_id=eq.${roomId}` },
          () => fetchAnswers(roomId),
        )
        .subscribe()
    })()

    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [roomId, fetchRound, fetchCards, fetchAnswers])

  // Hämta om allt (används för att backa en optimistisk ändring vid fel).
  const refetch = useCallback(() => {
    if (!roomId) return
    fetchRound(roomId)
    fetchCards(roomId)
    fetchAnswers(roomId)
  }, [roomId, fetchRound, fetchCards, fetchAnswers])

  // Optimistiska ändringar: uppdatera lokalt DIREKT så klicket känns omedelbart.
  // Realtiden skriver sedan över med serverns sanning (eller refetch vid fel).
  const optimisticCell = useCallback((cardId, cell, filled) => {
    setCards((prev) =>
      prev.map((c) =>
        c.id === cardId
          ? { ...c, grid: c.grid.map((g, i) => (i === cell ? { ...g, filled } : g)) }
          : c,
      ),
    )
  }, [])

  const optimisticOverride = useCallback((answerId, value) => {
    setAnswers((prev) =>
      prev.map((a) => (a.id === answerId ? { ...a, override_correct: value } : a)),
    )
  }, [])

  return { round, cards, answers, facit, loading, refetch, optimisticCell, optimisticOverride }
}
