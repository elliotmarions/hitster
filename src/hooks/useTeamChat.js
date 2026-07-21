import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { sendTeamMessage } from '../lib/game'

const LIMIT = 200

/**
 * Lagets privata chatt i realtid.
 *
 * RLS släpper bara igenom rader vars team_id är DITT lag – både i select:en
 * nedan och i realtidskanalen (Supabase kör samma policy per prenumerant).
 * Vi filtrerar ändå på team_id i prenumerationen: rader vi inte får se skulle
 * bara tystas bort, och då hade vi prenumererat på ingenting i onödan.
 *
 * Nya meddelanden läggs på direkt från realtidshändelsen (dedup på id) i
 * stället för en refetch – chatt ska kännas omedelbar, och payloaden är
 * exakt den rad vi ändå hade hämtat.
 */
export function useTeamChat(roomId, teamId) {
  const [messages, setMessages] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  // Håller senaste team-id i en ref så append inte råkar landa i fel lag om
  // man flyttas mellan lagen medan en händelse är i luften.
  const teamRef = useRef(teamId)
  teamRef.current = teamId

  const append = useCallback((row) => {
    if (!row || row.team_id !== teamRef.current) return
    setMessages((prev) =>
      prev.some((m) => m.id === row.id)
        ? prev
        : [...prev, row].sort((a, b) => a.created_at.localeCompare(b.created_at)),
    )
  }, [])

  useEffect(() => {
    if (!supabase || !roomId || !teamId) {
      setMessages([])
      setLoading(false)
      return
    }

    let cancelled = false
    let channel = null

    ;(async () => {
      setLoading(true)
      const { data, error: fetchError } = await supabase
        .from('team_messages')
        .select('*')
        .eq('room_id', roomId)
        .eq('team_id', teamId)
        .order('created_at', { ascending: true })
        .limit(LIMIT)
      if (cancelled) return
      if (!fetchError) setMessages(data ?? [])
      setLoading(false)

      channel = supabase
        .channel(`team-chat:${teamId}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'team_messages',
            filter: `team_id=eq.${teamId}`,
          },
          (payload) => append(payload.new),
        )
        .subscribe()
    })()

    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [roomId, teamId, append])

  // Skickar via RPC:n och lägger in svaret direkt – realtidshändelsen kommer
  // strax efter och dedupas bort.
  const send = useCallback(
    async (text) => {
      setError('')
      try {
        const row = await sendTeamMessage(roomId, text)
        append(row)
        return true
      } catch (e) {
        setError(e.message || 'Kunde inte skicka meddelandet.')
        return false
      }
    },
    [roomId, append],
  )

  return { messages, loading, error, send }
}
