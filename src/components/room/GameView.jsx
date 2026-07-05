import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CATEGORIES, TIMER_SECONDS } from '../../lib/constants.js'
import { useGame } from '../../hooks/useGame.js'
import { ensureCard, spinWheel, markCross, unmarkCross, eraseCross, resetGame } from '../../lib/game.js'
import { leaveRoom } from '../../lib/rooms.js'
import DiscoWheel from '../DiscoWheel.jsx'
import CategoryBanner from '../CategoryBanner.jsx'
import RoundTimer from '../RoundTimer.jsx'
import BingoCard from '../BingoCard.jsx'
import WinBanner from '../WinBanner.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import SpotifyPanel from '../SpotifyPanel.jsx'

export default function GameView({ room, players, me, isHost }) {
  const navigate = useNavigate()
  const { round, cards } = useGame(room.id)
  const [now, setNow] = useState(() => Date.now())
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const ensured = useRef(false)

  // Säkerställ att jag har en bricka (täcker sena joins).
  useEffect(() => {
    if (ensured.current) return
    ensured.current = true
    ensureCard(room.id).catch(() => {})
  }, [room.id])

  // Tickande klocka så snurr-status och timer hålls i synk mot serverns timer_start_at.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 200)
    return () => clearInterval(t)
  }, [])

  const ts = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const spinning = ts != null && now < ts
  const remaining = ts != null ? TIMER_SECONDS - (now - ts) / 1000 : 0
  const finished = room.status === 'finished'

  const myCard = cards.find((c) => c.player_id === me?.id)
  const otherCards = cards.filter((c) => c.player_id !== me?.id)
  const playerName = (pid) => players.find((p) => p.id === pid)?.display_name || 'Spelare'

  // Efter att snurret landat gäller rundans kategori tills nästa snurr.
  const currentCategory = round && !spinning ? round.category : null
  const canMark = !finished && !!currentCategory && !myCard?.has_won
  const canUnmark = !finished // egna kryss kan alltid ångras under spelets gång
  const canErase = !finished && room.erase_rule_enabled && currentCategory === 'exact_year'

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

  const onSpin = () => run(() => spinWheel(room.id))
  const onMark = (i) => run(() => markCross(room.id, i))
  const onUnmark = (i) => run(() => unmarkCross(room.id, i))
  const onErase = (cardId, i) => run(() => eraseCross(room.id, cardId, i))
  const onPlayAgain = () => run(() => resetGame(room.id, false))
  const onBackToLobby = () => run(() => resetGame(room.id, true))
  async function handleLeave() {
    try {
      await leaveRoom(room.id)
    } catch {
      /* navigera bort ändå */
    }
    navigate('/')
  }

  const timerColor = round ? CATEGORIES[round.category]?.hex : '#22e6e6'

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="label">Spelar nu</p>
          <h1 className="font-display text-2xl text-cream">{room.name || 'Namnlöst rum'}</h1>
        </div>
        <div className="flex items-center gap-2">
          <span className="chip" style={{ '--neon': '#22e6e6' }}>
            {players.length} spelare
          </span>
          <NeonButton variant="ghost" onClick={handleLeave}>
            Lämna
          </NeonButton>
        </div>
      </div>

      {finished && (
        <WinBanner
          winnerName={playerName(room.winner_player_id)}
          isMe={Boolean(myCard?.has_won)}
          isHost={isHost}
          busy={busy}
          onPlayAgain={onPlayAgain}
          onBackToLobby={onBackToLobby}
        />
      )}

      {/* Scen: discokula + kategori + timer */}
      <section className="panel p-6">
        <div className="flex flex-col items-center gap-4">
          <CategoryBanner round={round} spinning={spinning} />
          <div className="flex items-center gap-5">
            <DiscoWheel round={round} size={260} />
            {ts != null && !spinning && remaining > 0 && (
              <RoundTimer remaining={remaining} total={TIMER_SECONDS} color={timerColor} />
            )}
          </div>
          {isHost ? (
            <NeonButton onClick={onSpin} disabled={busy || spinning || finished}>
              {spinning ? 'Snurrar…' : round ? 'Snurra igen' : 'Snurra discokulan'}
            </NeonButton>
          ) : (
            <p className="text-sm text-muted">
              {spinning ? 'Discokulan snurrar…' : 'Värden snurrar discokulan.'}
            </p>
          )}
          {err && <p className="text-sm text-magenta">{err}</p>}
        </div>
      </section>

      {/* Egen bricka */}
      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">Din bricka</h2>
          {currentCategory && CATEGORIES[currentCategory] && !myCard?.has_won && (
            <span className="text-xs text-muted">
              Kryssa en{' '}
              <b style={{ color: CATEGORIES[currentCategory].hex }}>
                {CATEGORIES[currentCategory].short}
              </b>
              -ruta
            </span>
          )}
        </div>
        {myCard ? (
          <div className="mx-auto max-w-[380px] space-y-2">
            <BingoCard
              card={myCard}
              playerName={me?.display_name}
              isOwn
              currentCategory={currentCategory}
              canMark={canMark}
              canUnmark={canUnmark}
              onMark={onMark}
              onUnmark={onUnmark}
              variant="lg"
            />
            {canUnmark && myCard.grid?.some((cell) => cell.filled) && (
              <p className="text-center text-xs text-muted">
                Klickade du fel? Klicka på ett kryss för att ta bort det.
              </p>
            )}
          </div>
        ) : (
          <p className="panel p-6 text-center text-muted">Delar ut din bricka…</p>
        )}
      </section>

      {/* Medspelares brickor – full insyn */}
      {otherCards.length > 0 && (
        <section>
          <h2 className="mb-2 font-display text-xl text-cream">Medspelare</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
            {otherCards.map((c) => (
              <BingoCard
                key={c.id}
                card={c}
                playerName={playerName(c.player_id)}
                currentCategory={currentCategory}
                canErase={canErase}
                onErase={(i) => onErase(c.id, i)}
                variant="sm"
              />
            ))}
          </div>
          {canErase && (
            <p className="mt-2 text-xs text-muted">
              Suddregel aktiv: klicka ett kryss på en medspelares bricka för att sudda.
            </p>
          )}
        </section>
      )}

      <SpotifyPanel playerId={me?.id} />
    </div>
  )
}
