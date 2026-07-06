import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase.js'
import { leaveRoom } from '../../lib/rooms.js'
import { startGame } from '../../lib/game.js'
import PlayerList from '../PlayerList.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import CopyButton from '../ui/CopyButton.jsx'

export default function LobbyView({ room, players, isHost, currentUserId }) {
  const navigate = useNavigate()
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const roomLink = `${window.location.origin}/rum/${room.code}`

  async function handleStart() {
    setErr('')
    setBusy(true)
    try {
      await startGame(room.id)
      // rooms.status blir 'playing' → RoomPage byter till spelvyn automatiskt (via realtid)
    } catch (e) {
      setErr(e.message || 'Kunde inte starta spelet.')
      setBusy(false)
    }
  }

  async function handleLeave() {
    try {
      await leaveRoom(room.id)
    } catch {
      /* navigera bort ändå */
    }
    navigate('/')
  }

  async function toggleErase(e) {
    // Värdens direkta uppdatering tillåts av RLS (rooms_update_host). Realtid speglar till alla.
    await supabase.from('rooms').update({ erase_rule_enabled: e.target.checked }).eq('id', room.id)
  }

  return (
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-[1.15fr_0.85fr]">
      <section className="panel p-6 sm:p-8">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="label">Lobby</p>
            <h1 className="mt-1 font-display text-3xl text-cream">{room.name || 'Namnlöst rum'}</h1>
          </div>
          <span className="chip" style={{ '--neon': '#b6ff3c' }}>
            Väntar
          </span>
        </div>

        <div className="mt-6">
          <p className="label mb-2">Rumskod – dela med gänget</p>
          <div className="flex flex-wrap items-center gap-3">
            <div className="code-badge px-5 py-3 text-3xl">{room.code}</div>
            <CopyButton value={room.code} label="Kopiera kod" />
            <CopyButton value={roomLink} label="Kopiera länk" neon="#b14dff" />
          </div>
        </div>

        {/* Suddregel */}
        <label className="panel-inset mt-6 flex items-center justify-between gap-4 p-3.5">
          <span>
            <span className="font-display text-cream">Suddregel</span>
            <span className="mt-0.5 block text-xs text-muted">
              På "Exakt årtal": rätt gissning låter dig sudda ett kryss hos en medspelare.
            </span>
          </span>
          <input
            type="checkbox"
            className="h-5 w-5 accent-magenta disabled:opacity-50"
            checked={room.erase_rule_enabled}
            onChange={toggleErase}
            disabled={!isHost}
          />
        </label>

        {err && <p className="mt-4 text-sm text-magenta">{err}</p>}

        <div className="mt-6 flex flex-wrap items-center gap-3">
          {isHost ? (
            <NeonButton onClick={handleStart} disabled={busy}>
              {busy ? 'Startar…' : 'Starta spel'}
            </NeonButton>
          ) : (
            <span className="text-sm text-muted">Väntar på att värden startar spelet…</span>
          )}
          <NeonButton variant="ghost" onClick={handleLeave}>
            Lämna rummet
          </NeonButton>
        </div>
      </section>

      <section className="panel p-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">Spelare</h2>
          <span className="chip" style={{ '--neon': '#22e6e6' }}>
            {players.length} i rummet
          </span>
        </div>
        <div className="mt-4">
          <PlayerList players={players} currentUserId={currentUserId} />
        </div>
      </section>
      </div>
    </div>
  )
}
