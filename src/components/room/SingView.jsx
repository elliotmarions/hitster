import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase.js'
import { useNavGuard } from '../../context/NavGuardContext.jsx'
import { useGame } from '../../hooks/useGame.js'
import { useSingAudio } from '../../hooks/useSingAudio.js'
import { pollTrackStart, resetGame, singJudge, singNextTurn, singReveal } from '../../lib/game.js'
import { leaveRoom } from '../../lib/rooms.js'
import { serverNow } from '../../lib/serverTime.js'
import { SING_FACIT_SECONDS, TEAM_COLORS, singTargetFor } from '../../lib/constants.js'
import Countdown from '../Countdown.jsx'
import HostLeftNotice from '../HostLeftNotice.jsx'
import VolumeControl from '../VolumeControl.jsx'
import TeamChat from '../TeamChat.jsx'
import Confetti from '../Confetti.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import ConfirmDialog from '../ui/ConfirmDialog.jsx'

/**
 * Spelvyn för "Sjung vidare" (0087).
 *
 * En tur = en runda. Värden drar låten, appen spelar början och tystnar vid
 * sing_cut_at, laget på tur sjunger fortsättningen. Värden spelar facit (låten
 * fortsätter från samma ställe och titeln visas), de andra lagen dömer
 * Rätt/Fel. Först till rooms.sing_target rätt vinner.
 *
 * Poängen lagras inte – den räknas ur rundorna, precis som servern gör.
 */
export default function SingView({ room, players, teams, me, isHost }) {
  const navigate = useNavigate()
  const { round, facit } = useGame(room.id)
  const audio = useSingAudio(round)

  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [now, setNow] = useState(() => serverNow())
  const [confirmLeave, setConfirmLeave] = useState(false)
  const [leaving, setLeaving] = useState(false)
  const [searchStale, setSearchStale] = useState(false)
  const [scores, setScores] = useState({})

  const target = singTargetFor(room)
  const finished = room.status === 'finished'
  const hostLeft = finished && room.ended_reason === 'host_left'

  const askLeave = useCallback(() => setConfirmLeave(true), [])
  useNavGuard(!hostLeft, askLeave)

  // Lagen som spelar: de som har spelare, i samma ordning som servern turar.
  // Samma sortering som _sing_teams() på servern: sort, sedan skapad, sedan id.
  const playing = teams
    .filter((t) => players.some((p) => p.team_id === t.id))
    .sort(
      (a, b) =>
        (a.sort ?? 0) - (b.sort ?? 0) ||
        String(a.created_at).localeCompare(String(b.created_at)) ||
        String(a.id).localeCompare(String(b.id)),
    )
    .map((t, i) => ({ ...t, color: t.color || TEAM_COLORS[i % TEAM_COLORS.length] }))
  const teamById = (id) => playing.find((t) => t.id === id) || teams.find((t) => t.id === id)
  const turnTeam = round ? teamById(round.sing_team_id) : null
  const turnColor = turnTeam?.color || '#22e6e6'
  const myTeamOnTurn = Boolean(me?.team_id) && me.team_id === round?.sing_team_id
  const canJudge = isHost || (Boolean(me) && !myTeamOnTurn)

  // Poängen: antal rätt per lag. Hämtas om när en dom faller eller rummet byter
  // status (Spela igen raderar rundorna och därmed poängen).
  useEffect(() => {
    let active = true
    supabase
      .from('rounds')
      .select('sing_team_id')
      .eq('room_id', room.id)
      .eq('category', 'sing')
      .eq('sing_verdict', true)
      .then(({ data }) => {
        if (!active) return
        const s = {}
        for (const r of data ?? []) s[r.sing_team_id] = (s[r.sing_team_id] ?? 0) + 1
        setScores(s)
      })
    return () => {
      active = false
    }
  }, [room.id, room.status, round?.id, round?.sing_verdict])

  // Turens faser, räknade på serverns klocka.
  const hasTrack = Boolean(round?.current_track_id)
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const cutAt = round?.sing_cut_at != null ? Number(round.sing_cut_at) : 0
  const cutMs = startMs != null ? startMs + cutAt * 1000 : null
  const revealed = Boolean(round?.answers_revealed)
  const revealMs = round?.sing_reveal_at ? new Date(round.sing_reveal_at).getTime() : null
  const verdict = round?.sing_verdict ?? null

  const searching = Boolean(round) && !hasTrack && round.state === 'loading'
  const beforeStart = hasTrack && startMs != null && now < startMs
  const listening = hasTrack && !revealed && startMs != null && now >= startMs && now < cutMs
  const singing = hasTrack && !revealed && cutMs != null && now >= cutMs
  const facitPlaying = revealed && revealMs != null && now < revealMs + SING_FACIT_SECONDS * 1000

  // Klockan tickar bara medan något på skärmen beror på den.
  const clockUntil = revealMs
    ? revealMs + SING_FACIT_SECONDS * 1000 + 500
    : cutMs
      ? cutMs + 500
      : null
  useEffect(() => {
    if (clockUntil == null) return undefined
    setNow(serverNow())
    const t = setInterval(() => {
      const n = serverNow()
      setNow(n)
      if (n >= clockUntil) clearInterval(t)
    }, 200)
    return () => clearInterval(t)
  }, [clockUntil])

  // Uppslaget hos iTunes drivs av att någon frågar servern. Värden gör det i
  // singNextTurn; övriga hoppar in efter en stund om värdens flik tystnat.
  useEffect(() => {
    setSearchStale(false)
    if (!searching) return undefined
    const t = setTimeout(() => setSearchStale(true), 45_000)
    return () => clearTimeout(t)
  }, [searching, round?.id])
  useEffect(() => {
    if (isHost || !searching) return undefined
    let stopped = false
    const t = setTimeout(() => {
      pollTrackStart(room.id, { intervalMs: 1500, shouldStop: () => stopped }).catch(() => {})
    }, 6000)
    return () => {
      stopped = true
      clearTimeout(t)
    }
  }, [isHost, searching, room.id, round?.id])

  async function run(fn) {
    setErr('')
    setBusy(true)
    try {
      await fn()
    } catch (e) {
      setErr(e.message || 'Något gick fel.')
    } finally {
      setBusy(false)
    }
  }

  const onNext = () => run(() => singNextTurn(room.id))
  const onReveal = () => run(() => singReveal(room.id))
  const onJudge = (correct) => run(() => singJudge(room.id, correct))
  const onPlayAgain = () => run(() => resetGame(room.id, false))
  const onBackToLobby = () => run(() => resetGame(room.id, true))
  async function handleLeave() {
    setLeaving(true)
    try {
      await leaveRoom(room.id)
    } catch {
      /* navigera bort ändå */
    }
    navigate('/')
  }

  const winner = finished && !hostLeft ? teamById(room.winner_team_id) : null
  const iWon = Boolean(winner) && me?.team_id === winner.id

  return (
    <div className="space-y-6">
      {beforeStart && <Countdown secondsToStart={(startMs - now) / 1000} />}
      {(busy || (searching && !searchStale)) && !hasTrack && !finished && <Countdown preparing />}

      <ConfirmDialog
        open={confirmLeave}
        busy={leaving}
        title={isHost ? 'Avsluta matchen?' : 'Lämna matchen?'}
        message={
          isHost
            ? 'Du är värd – lämnar du avslutas matchen för alla. Det går inte att ångra.'
            : 'Du tas bort ur rummet. Du kan gå med igen med rumskoden.'
        }
        confirmLabel={isHost ? 'Avsluta för alla' : 'Lämna'}
        cancelLabel="Stanna kvar"
        onConfirm={handleLeave}
        onCancel={() => setConfirmLeave(false)}
      />

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="label">Sjung vidare · först till {target}</p>
          <h1 className="mt-1 truncate font-display text-2xl text-cream">
            {room.name || 'Namnlöst rum'}
          </h1>
        </div>
        <NeonButton variant="ghost" onClick={() => setConfirmLeave(true)}>
          Lämna
        </NeonButton>
      </div>

      {!audio.ready && (
        <div
          className="panel flex flex-wrap items-center justify-between gap-3 p-4"
          style={{ '--neon': '#1ed760', borderColor: 'rgba(30,215,96,0.5)' }}
        >
          <p className="text-sm text-cream">
            🔊 <b>Aktivera ljudet</b> – annars hör du inte låten (webbläsaren kräver ett klick).
          </p>
          <NeonButton variant="outline" neon="#1ed760" onClick={() => audio.unlock()}>
            Aktivera ljud
          </NeonButton>
        </div>
      )}

      {hostLeft && <HostLeftNotice onBack={() => navigate('/')} />}

      {/* Poängtavlan */}
      <section className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
        {playing.map((t) => {
          const s = scores[t.id] ?? 0
          const onTurn = !finished && round?.sing_team_id === t.id
          return (
            <div
              key={t.id}
              className="panel-inset p-3.5"
              style={{
                borderColor: onTurn ? t.color : undefined,
                boxShadow: onTurn ? `0 0 22px -8px ${t.color}` : undefined,
              }}
            >
              <div className="flex items-baseline justify-between gap-2">
                <span className="truncate font-display text-cream">{t.name}</span>
                <span className="font-display text-2xl leading-none" style={{ color: t.color }}>
                  {s}
                </span>
              </div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full transition-all"
                  style={{ width: `${Math.min(100, (s / target) * 100)}%`, background: t.color }}
                />
              </div>
              <p className="mt-1.5 text-xs text-muted">
                {onTurn ? 'På tur' : `${Math.max(0, target - s)} kvar`}
                {me?.team_id === t.id ? ' · ert lag' : ''}
              </p>
            </div>
          )
        })}
      </section>

      {/* Vinst */}
      {winner && (
        <section
          className="panel relative overflow-hidden p-6 text-center"
          style={{ borderColor: '#ffc93c', boxShadow: '0 0 44px -10px #ffc93c' }}
        >
          <Confetti />
          <div className="relative z-10">
            <p className="label" style={{ color: '#ffc93c' }}>Vinst</p>
            <h2 className="mt-2 font-display text-3xl text-cream sm:text-4xl">
              {iWon ? `Ni vann, ${winner.name}!` : `${winner.name} vann!`}
            </h2>
            <p className="mt-2 text-sm text-muted">Först till {target} rätt.</p>
            <div className="mt-5 flex flex-wrap justify-center gap-3">
              {isHost ? (
                <>
                  <NeonButton onClick={onPlayAgain} disabled={busy}>🔁 Spela igen</NeonButton>
                  <NeonButton variant="outline" neon="#22e6e6" onClick={onBackToLobby} disabled={busy}>
                    Till lobbyn
                  </NeonButton>
                </>
              ) : (
                <p className="text-sm text-muted">Väntar på att värden startar om…</p>
              )}
            </div>
          </div>
        </section>
      )}

      {/* Scenen */}
      {!finished && (
        <section className="panel relative p-5 text-center sm:p-8">
          <div className="absolute right-3 top-3 z-20">
            <VolumeControl volume={audio.volume} setVolume={audio.setVolume} />
          </div>

          {!round && (
            <div className="py-6">
              <p className="font-display text-2xl text-cream">Redo att sjunga?</p>
              <p className="mx-auto mt-2 max-w-md text-sm text-muted">
                Appen spelar början av en låt och tystnar mitt i. Laget på tur sjunger
                fortsättningen – sedan spelar appen vidare så alla hör om det stämde.
              </p>
              <div className="mt-6">
                {isHost ? (
                  <NeonButton onClick={onNext} disabled={busy}>Dra första låten</NeonButton>
                ) : (
                  <p className="text-sm text-muted">Väntar på att värden drar första låten…</p>
                )}
              </div>
            </div>
          )}

          {round && !hasTrack && (
            <div className="py-6">
              <p className="font-display text-xl text-cream">
                {searchStale ? 'Låten hittades inte' : 'Letar upp låten…'}
              </p>
              {searchStale && isHost && (
                <div className="mt-4">
                  <NeonButton onClick={onNext} disabled={busy}>Försök igen</NeonButton>
                </div>
              )}
            </div>
          )}

          {hasTrack && !revealed && (
            <div className="py-4">
              <p className="label" style={{ color: turnColor }}>
                {myTeamOnTurn ? 'Ert lag är på tur' : `${turnTeam?.name || 'Laget'} är på tur`}
              </p>
              {(beforeStart || listening) && (
                <>
                  <p className="mt-3 font-display text-3xl text-cream">🎧 Lyssna…</p>
                  <p className="mt-2 text-sm text-muted">
                    Låten tystnar snart. {myTeamOnTurn ? 'Var redo att ta över!' : 'Sedan är det deras tur.'}
                  </p>
                  {listening && (
                    <div className="mx-auto mt-5 h-2 max-w-sm overflow-hidden rounded-full bg-white/10">
                      <div
                        className="h-full rounded-full"
                        style={{
                          width: `${Math.min(100, ((now - startMs) / (cutAt * 1000)) * 100)}%`,
                          background: turnColor,
                        }}
                      />
                    </div>
                  )}
                </>
              )}
              {singing && (
                <>
                  <h2
                    className="neon-text mt-3 text-4xl sm:text-5xl"
                    style={{ '--neon': turnColor }}
                  >
                    Sjung vidare!
                  </h2>
                  <p className="mt-2 text-sm text-muted">
                    {myTeamOnTurn
                      ? 'Fortsätt låten där den tystnade. Ta den tid ni behöver.'
                      : `${turnTeam?.name || 'Laget'} sjunger fortsättningen – ingen tidsgräns.`}
                  </p>
                  <div className="mt-5">
                    {isHost ? (
                      <NeonButton onClick={onReveal} disabled={busy}>Spela facit</NeonButton>
                    ) : (
                      <p className="text-sm text-muted">Värden spelar facit när laget sjungit klart.</p>
                    )}
                  </div>
                </>
              )}
            </div>
          )}

          {revealed && (
            <div className="py-4">
              <p className="label">{facitPlaying ? '🎶 Så här gick den' : 'Facit'}</p>
              <p className="mt-3 font-display text-3xl text-cream">{facit?.name || '…'}</p>
              <p className="mt-1 text-muted">
                {facit?.artist}
                {facit?.year ? ` · ${facit.year}` : ''}
              </p>

              <div className="mx-auto mt-6 max-w-md">
                <p className="text-sm text-cream">
                  Sjöng {myTeamOnTurn ? 'ni' : turnTeam?.name || 'laget'} rätt?
                </p>
                {canJudge ? (
                  <div className="mt-3 grid grid-cols-2 gap-3">
                    <NeonButton
                      variant={verdict === true ? 'primary' : 'outline'}
                      neon="#3ee87b"
                      onClick={() => onJudge(true)}
                      disabled={busy}
                    >
                      ✓ Rätt
                    </NeonButton>
                    <NeonButton
                      variant={verdict === false ? 'primary' : 'outline'}
                      neon="#ff4d9d"
                      onClick={() => onJudge(false)}
                      disabled={busy}
                    >
                      ✗ Fel
                    </NeonButton>
                  </div>
                ) : (
                  <p className="mt-2 text-sm text-muted">De andra lagen dömer.</p>
                )}
                {verdict !== null && (
                  <p className="mt-3 font-display text-lg" style={{ color: verdict ? '#3ee87b' : '#ff4d9d' }}>
                    {verdict ? `Rätt! +1 till ${turnTeam?.name || 'laget'}` : 'Fel – ingen poäng'}
                  </p>
                )}
              </div>

              <div className="mt-6">
                {isHost ? (
                  <NeonButton onClick={onNext} disabled={busy || verdict === null}>
                    Nästa låt →
                  </NeonButton>
                ) : (
                  verdict !== null && <p className="text-sm text-muted">Väntar på nästa låt…</p>
                )}
              </div>
            </div>
          )}
        </section>
      )}

      {(err || audio.error) && <p className="text-center text-sm text-magenta">{err || audio.error}</p>}

      <TeamChat room={room} me={me} teams={teams} />
    </div>
  )
}
