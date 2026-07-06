import { useState } from 'react'
import { TEAM_COLORS } from '../lib/constants.js'
import { createTeam, deleteTeam, assignPlayer } from '../lib/game.js'
import NeonButton from './ui/NeonButton.jsx'

/**
 * Lag-indelning i lobbyn (bara värden styr). Värden skapar lag och placerar
 * varje spelare i ett lag via en dropdown. Alla ser indelningen i realtid.
 *
 * Props: room, players, teams, isHost
 */
export default function TeamSetup({ room, players, teams, isHost }) {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  async function run(fn) {
    setErr('')
    setBusy(true)
    try {
      await fn()
    } catch (e) {
      setErr(e.message || 'Något gick fel.')
    }
    setBusy(false)
  }

  const nextColor = TEAM_COLORS[teams.length % TEAM_COLORS.length]
  const onAddTeam = () => run(() => createTeam(room.id, `Lag ${teams.length + 1}`, nextColor))
  const onDeleteTeam = (id) => run(() => deleteTeam(room.id, id))
  const onAssign = (playerId, teamId) => run(() => assignPlayer(room.id, playerId, teamId || null))

  const teamColor = (t) => t.color || TEAM_COLORS[0]
  const membersOf = (teamId) => players.filter((p) => p.team_id === teamId)
  const unassigned = players.filter((p) => !p.team_id)

  return (
    <section className="panel p-6">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-display text-xl text-cream">Lagindelning</h2>
        {isHost && (
          <NeonButton variant="outline" neon={nextColor} onClick={onAddTeam} disabled={busy}>
            + Lägg till lag
          </NeonButton>
        )}
      </div>

      {teams.length === 0 ? (
        <p className="mt-3 text-sm text-muted">
          {isHost
            ? 'Skapa minst två lag och placera spelarna i dem.'
            : 'Väntar på att värden delar in lagen…'}
        </p>
      ) : (
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {teams.map((t) => {
            const members = membersOf(t.id)
            return (
              <div
                key={t.id}
                className="panel-inset p-3"
                style={{ borderColor: teamColor(t) + '66' }}
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="flex items-center gap-2 font-display text-cream">
                    <span
                      className="h-3 w-3 rounded-full"
                      style={{ background: teamColor(t), boxShadow: `0 0 8px ${teamColor(t)}` }}
                    />
                    {t.name}
                    <span className="text-xs text-muted">({members.length})</span>
                  </span>
                  {isHost && (
                    <button
                      className="text-xs text-muted hover:text-magenta"
                      onClick={() => onDeleteTeam(t.id)}
                      disabled={busy}
                      title="Ta bort lag"
                    >
                      ✕
                    </button>
                  )}
                </div>
                <ul className="mt-2 space-y-1">
                  {members.length === 0 ? (
                    <li className="text-xs text-muted">Inga spelare än</li>
                  ) : (
                    members.map((p) => (
                      <li key={p.id} className="text-sm text-cream">
                        · {p.display_name}
                        {p.is_host && <span className="ml-1 text-xs text-yellow">★</span>}
                      </li>
                    ))
                  )}
                </ul>
              </div>
            )
          })}
        </div>
      )}

      {/* Placera spelare (värden) */}
      {isHost && teams.length > 0 && (
        <div className="mt-5">
          <p className="label mb-2">Placera spelare</p>
          <div className="space-y-2">
            {players.map((p) => (
              <div key={p.id} className="panel-inset flex items-center gap-3 px-3.5 py-2">
                <span className="min-w-0 flex-1 truncate font-display text-cream">
                  {p.display_name}
                  {p.is_host && <span className="ml-1 text-xs text-yellow">★ Värd</span>}
                </span>
                <select
                  className="field max-w-[9rem] py-1.5 text-sm"
                  value={p.team_id || ''}
                  onChange={(e) => onAssign(p.id, e.target.value)}
                  disabled={busy}
                >
                  <option value="">– Inget lag –</option>
                  {teams.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              </div>
            ))}
          </div>
          {unassigned.length > 0 && (
            <p className="mt-2 text-xs text-muted">
              {unassigned.length} spelare utan lag – de blir egna lag om du startar ändå.
            </p>
          )}
        </div>
      )}

      {err && <p className="mt-3 text-sm text-magenta">{err}</p>}
    </section>
  )
}
