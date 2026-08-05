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
  const [teams, setTeams] = useState([])
  const [status, setStatus] = useState('loading')
  // Vilka user_id som just nu har en levande anslutning till rummet. Postgres
  // vet det inte – en stängd flik skriver ingenting – men Realtime gör det:
  // presence är knuten till websocket-anslutningen och släpper när den dör.
  // null = presence har inte synkat än, vilket INTE är samma sak som "ingen
  // är här"; den som rensar frånvarande måste kunna skilja de två åt.
  const [presentUserIds, setPresentUserIds] = useState(null)
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

  const fetchTeams = useCallback(async (roomId) => {
    const { data, error } = await supabase
      .from('teams')
      .select('*')
      .eq('room_id', roomId)
      .order('sort', { ascending: true })
    if (!error) setTeams(data ?? [])
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
      await Promise.all([fetchPlayers(roomRow.id), fetchTeams(roomRow.id)])
      if (cancelled) return
      setStatus('ready')

      // Presence-nyckeln är användarens id, inte en slumpad anslutnings-id:
      // öppnar någon rummet i två flikar ska de räknas som EN närvarande
      // spelare, och sista fliken som stängs ska vara den som gör dem borta.
      const { data: authData } = await supabase.auth.getUser()
      const uid = authData?.user?.id ?? null

      // Prenumerera på förändringar för just detta rum.
      channel = supabase
        .channel(`room:${roomRow.id}`, { config: { presence: { key: uid ?? 'anon' } } })
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
            event: '*',
            schema: 'public',
            table: 'teams',
            filter: `room_id=eq.${roomRow.id}`,
          },
          () => fetchTeams(roomRow.id),
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
        .on('presence', { event: 'sync' }, () => {
          if (cancelled) return
          setPresentUserIds(new Set(Object.keys(channel.presenceState())))
        })
        .subscribe((chStatus) => {
          // track() måste vänta på att kanalen är ansluten, annars tappas den.
          if (chStatus === 'SUBSCRIBED' && uid) channel.track({ user_id: uid })
        })
    }

    init()

    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [code, reloadKey, fetchPlayers, fetchTeams])

  return { room, players, teams, status, presentUserIds, refresh }
}
