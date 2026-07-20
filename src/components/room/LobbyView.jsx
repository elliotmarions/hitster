import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase.js'
import { leaveRoom } from '../../lib/rooms.js'
import { startGame, trackPoolCounts } from '../../lib/game.js'
import PlayerList from '../PlayerList.jsx'
import TeamSetup from '../TeamSetup.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import ConfirmDialog from '../ui/ConfirmDialog.jsx'
import CopyButton from '../ui/CopyButton.jsx'
import SwedishFlag from '../ui/SwedishFlag.jsx'

export default function LobbyView({ room, players, teams, isHost, currentUserId }) {
  const navigate = useNavigate()
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [confirmLeave, setConfirmLeave] = useState(false)
  const [leaving, setLeaving] = useState(false)
  // Antal låtar per pott – potten bor i databasen (oläsbar för klienter),
  // bara räknarna exponeras via en RPC.
  const [potCounts, setPotCounts] = useState(null)
  const roomLink = `${window.location.origin}/rum/${room.code}`

  useEffect(() => {
    let active = true
    trackPoolCounts()
      .then((c) => active && setPotCounts(c))
      .catch(() => {})
    return () => {
      active = false
    }
  }, [])

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
    setLeaving(true)
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

  async function toggleTeamMode(e) {
    await supabase.from('rooms').update({ team_mode: e.target.checked }).eq('id', room.id)
  }

  async function setSwedishMode(value) {
    await supabase.from('rooms').update({ swedish_mode: value }).eq('id', room.id)
  }

  return (
    <div className="space-y-6">
      <ConfirmDialog
        open={confirmLeave}
        busy={leaving}
        title={isHost ? 'Stäng rummet?' : 'Lämna rummet?'}
        message={
          isHost
            ? 'Du är värd – lämnar du stängs rummet för alla som väntar. Det går inte att ångra.'
            : 'Du tas bort ur rummet. Du kan gå med igen med rumskoden.'
        }
        confirmLabel={isHost ? 'Stäng för alla' : 'Lämna'}
        cancelLabel="Stanna kvar"
        onConfirm={handleLeave}
        onCancel={() => setConfirmLeave(false)}
      />

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

        {/* Musik – vilken låtpott spelet använder (egen väljare, inte en av/på-regel) */}
        <div className="mt-6">
          <p className="label mb-2">🎵 Musik</p>
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              disabled={!isHost}
              onClick={() => setSwedishMode(false)}
              aria-pressed={!room.swedish_mode}
              className="panel-inset flex cursor-pointer flex-col gap-1 p-3.5 text-left transition disabled:cursor-default disabled:opacity-60"
              style={{
                borderColor: !room.swedish_mode ? '#22e6e6' : undefined,
                boxShadow: !room.swedish_mode ? '0 0 22px -8px #22e6e6' : undefined,
              }}
            >
              <span className="font-display text-cream">🌍 Alla låtar</span>
              <span className="text-xs text-muted">
                Blandat från hela världen
                {potCounts ? ` · ${potCounts.all.toLocaleString('sv-SE')} låtar` : ''}
              </span>
            </button>
            <button
              type="button"
              disabled={!isHost}
              onClick={() => setSwedishMode(true)}
              aria-pressed={room.swedish_mode}
              className="panel-inset flex cursor-pointer flex-col gap-1 p-3.5 text-left transition disabled:cursor-default disabled:opacity-60"
              style={{
                borderColor: room.swedish_mode ? '#ffd23f' : undefined,
                boxShadow: room.swedish_mode ? '0 0 22px -8px #ffd23f' : undefined,
              }}
            >
              <span className="inline-flex items-center gap-2 font-display text-cream">
                <SwedishFlag size={20} /> Svenska
              </span>
              <span className="text-xs text-muted">
                Svenska artister, 1950–idag
                {potCounts ? ` · ${potCounts.sv} låtar` : ''}
              </span>
            </button>
          </div>
        </div>

        {/* Regler – av/på */}
        <div className="mt-6">
          <p className="label mb-2">Regler</p>

          {/* Suddregel */}
          <label className="panel-inset flex items-center justify-between gap-4 p-3.5">
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

          {/* Lagläge */}
          <label className="panel-inset mt-3 flex items-center justify-between gap-4 p-3.5">
            <span>
              <span className="font-display text-cream">Lagläge</span>
              <span className="mt-0.5 block text-xs text-muted">
                Spela i lag med gemensam bricka och gemensamt svar. Värden delar in lagen nedan.
              </span>
            </span>
            <input
              type="checkbox"
              className="h-5 w-5 accent-cyan disabled:opacity-50"
              checked={room.team_mode}
              onChange={toggleTeamMode}
              disabled={!isHost}
            />
          </label>
        </div>

        {err && <p className="mt-4 text-sm text-magenta">{err}</p>}

        <div className="mt-6 flex flex-wrap items-center gap-3">
          {isHost ? (
            <NeonButton onClick={handleStart} disabled={busy}>
              {busy ? 'Startar…' : 'Starta spel'}
            </NeonButton>
          ) : (
            <span className="text-sm text-muted">Väntar på att värden startar spelet…</span>
          )}
          <NeonButton variant="ghost" onClick={() => setConfirmLeave(true)}>
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

      {room.team_mode && (
        <TeamSetup room={room} players={players} teams={teams} isHost={isHost} />
      )}
    </div>
  )
}
