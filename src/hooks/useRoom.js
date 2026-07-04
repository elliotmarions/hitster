import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { normalizeCode } from '../lib/rooms'

/**
 * Prenumererar på ett rum + dess spelare i realtid.
 *
 * Realtids-idén (återkommer i alla faser): vi lyssnar på Postgres-förändringar
 * via Supabase Realtime, filtrerat på room_id. När någon går med/lämnar (eller
 * i Fas 2: sätter ett kryss) skickar databasen en händelse och alla klienter
 * uppdaterar sin vy direkt – ingen behöver säga något högt.
 *
 * Status:
 *   loading  – hämtar
 *   ready    – rummet är laddat (du är medlem)
 *   notfound – rummet kunde inte läsas (finns inte, eller så är du inte medlem än)
 *   error    – något gick fel
 */
export function useRoom(rawCode) {
  const code = normalizeCode(rawCode)
  const [room, setRoom] = useState(null)
  const [players, setPlayers] = useState([])
  const [status, setStatus] = useState('loading')
  // Bumpas av refresh() för att köra om hela effekten (t.ex. direkt efter att
  // man gått med via en delad länk) – då sätts även realtidskanalen upp på nytt.
  const [reloadKey, setReloadKey] = useState(0)

  const refresh = useCallback(() => setReloadKey((k) => k + 1), [])

  const fetchPlayers = useCallback(async (roomId) => {
    const { data, error } = await supabase
      .from('players')
      .select('*')
      .eq('room_id', roomId)
      .order('joined_at', { ascending: true })
    if (!error) setPlayers(data ?? [])
  }, [])

  useEffect(() => {
    // Klienten kan saknas (Supabase ej konfigurerat) – gör då ingenting.
    if (!supabase || !code) {
      setStatus('notfound')
      return
    }

    let cancelled = false
    let channel = null

    async function init() {
      setStatus('loading')
      const { data: roomRow, error } = await supabase
        .from('rooms')
        .select('*')
        .eq('code', code)
        .maybeSingle()
      if (cancelled) return

      if (error) {
        setStatus('error')
        return
      }
      if (!roomRow) {
        // Under RLS betyder tomt svar "finns inte" ELLER "du är inte medlem än".
        setStatus('notfound')
        return
      }

      setRoom(roomRow)
      await fetchPlayers(roomRow.id)
      if (cancelled) return
      setStatus('ready')

      // Prenumerera på förändringar för just detta rum.
      channel = supabase
        .channel(`room:${roomRow.id}`)
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'players',
            filter: `room_id=eq.${roomRow.id}`,
          },
          () => fetchPlayers(roomRow.id),
        )
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'rooms',
            filter: `id=eq.${roomRow.id}`,
          },
          (payload) => setRoom(payload.new),
        )
        .subscribe()
    }

    init()

    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [code, reloadKey, fetchPlayers])

  return { room, players, status, refresh }
}
