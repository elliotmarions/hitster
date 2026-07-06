import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { useRoom } from '../hooks/useRoom.js'
import { normalizeCode } from '../lib/rooms.js'
import DiscoBall from '../components/DiscoBall.jsx'
import SetupNotice from '../components/SetupNotice.jsx'
import JoinGate from '../components/room/JoinGate.jsx'
import LobbyView from '../components/room/LobbyView.jsx'
import GameView from '../components/room/GameView.jsx'

// Container för /rum/:code – väljer vy utifrån rummets status (lobby/playing/finished).
export default function RoomPage() {
  const { code } = useParams()
  const { isConfigured, user } = useAuth()
  const { room, players, teams, status, refresh } = useRoom(code)

  if (!isConfigured) return <SetupNotice />

  if (status === 'loading') {
    return (
      <div className="flex flex-col items-center gap-4 py-20 text-muted">
        <DiscoBall size={72} className="anim-spin-slow" />
        <p>Laddar rummet…</p>
      </div>
    )
  }

  if (status === 'error') {
    return (
      <div className="panel mx-auto max-w-md p-6 text-center">
        <h2 className="text-2xl text-magenta">Något gick fel</h2>
        <p className="mt-2 text-muted">Kunde inte ladda rummet. Försök igen.</p>
        <Link to="/" className="mt-4 inline-block text-cyan underline">
          Till startsidan
        </Link>
      </div>
    )
  }

  if (status === 'notfound') {
    return <JoinGate code={normalizeCode(code)} onJoined={refresh} />
  }

  const me = players.find((p) => p.user_id === user?.id)
  const isHost = Boolean(me?.is_host)

  if (room.status === 'lobby') {
    return (
      <LobbyView
        room={room}
        players={players}
        teams={teams}
        isHost={isHost}
        currentUserId={user?.id}
      />
    )
  }
  return <GameView room={room} players={players} teams={teams} me={me} isHost={isHost} />
}
