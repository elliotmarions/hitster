import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CATEGORIES, TIMER_SECONDS, SPIN_MS } from '../../lib/constants.js'
import { useGame } from '../../hooks/useGame.js'
import {
  ensureCard,
  spinWheel,
  startTrack,
  markCross,
  unmarkCross,
  eraseCross,
  lockAnswer,
  revealAnswers,
  resetGame,
} from '../../lib/game.js'
import { leaveRoom } from '../../lib/rooms.js'
import { useSpotify } from '../../context/SpotifyContext.jsx'
import { useSyncedPlayback } from '../../hooks/useSyncedPlayback.js'
import { TRACKS } from '../../data/hitsterTracks.js'
import { searchTrackUri } from '../../lib/spotifyApi.js'
import DiscoWheel from '../DiscoWheel.jsx'
import CategoryBanner from '../CategoryBanner.jsx'
import RoundTimer from '../RoundTimer.jsx'
import BingoCard from '../BingoCard.jsx'
import WinBanner from '../WinBanner.jsx'
import Countdown from '../Countdown.jsx'
import AnswerPanel from '../AnswerPanel.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import SpotifyPanel from '../SpotifyPanel.jsx'

export default function GameView({ room, players, me, isHost }) {
  const navigate = useNavigate()
  const { round, cards, answers } = useGame(room.id)
  const spotify = useSpotify()
  // Startar/pausar låten synkat vid start_at (= rundans timer_start_at) hos alla.
  useSyncedPlayback(round, spotify.deviceReady, spotify.playTrack, spotify.pause)

  const [now, setNow] = useState(() => Date.now())
  const [wheelSpinning, setWheelSpinning] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const ensured = useRef(false)
  const spunRef = useRef(0)
  const recentRef = useRef([]) // nyligen spelade pott-index (undvik direkta repriser)

  // Säkerställ att jag har en bricka (täcker sena joins).
  useEffect(() => {
    if (ensured.current) return
    ensured.current = true
    ensureCard(room.id).catch(() => {})
  }, [room.id])

  // Tickande klocka.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 200)
    return () => clearInterval(t)
  }, [])

  // Snurr-animation: bara när en NY runda (utan låt) kommer – inte när start_track
  // uppdaterar samma runda med en låt.
  useEffect(() => {
    if (!round?.round_number || round.current_track_id) return
    if (spunRef.current === round.round_number) return
    spunRef.current = round.round_number
    setWheelSpinning(true)
    const t = setTimeout(() => setWheelSpinning(false), SPIN_MS)
    return () => clearTimeout(t)
  }, [round?.round_number, round?.current_track_id])

  const finished = room.status === 'finished'
  // timer_start_at sätts först när värden trycker "Starta låt" (= start_at).
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const hasTrack = Boolean(round?.current_track_id)
  const remaining = startMs != null ? TIMER_SECONDS - (now - startMs) / 1000 : 0

  // Uppspelningsfaser (efter "Starta låt").
  const beforeStart = hasTrack && startMs != null && now < startMs
  const clipPlaying = hasTrack && startMs != null && now >= startMs && now < startMs + TIMER_SECONDS * 1000
  const revealed = hasTrack && startMs != null && now >= startMs + TIMER_SECONDS * 1000
  const timerRunning = clipPlaying && remaining > 0

  const needsManual = hasTrack && !spotify.deviceReady // mobil / ej redo → starta själv
  const trackOpenUrl = round?.current_track_id?.replace(
    'spotify:track:',
    'https://open.spotify.com/track/',
  )

  const myCard = cards.find((c) => c.player_id === me?.id)
  const otherCards = cards.filter((c) => c.player_id !== me?.id)
  const playerName = (pid) => players.find((p) => p.id === pid)?.display_name || 'Spelare'

  // Kategorin gäller så fort hjulet landat.
  const currentCategory = round && !wheelSpinning ? round.category : null
  const canMark = !finished && !!currentCategory && !myCard?.has_won
  const canUnmark = !finished
  const canErase = !finished && room.erase_rule_enabled && currentCategory === 'exact_year'

  // Värdens kontroller
  const canSpin = isHost && !finished && !wheelSpinning && !beforeStart && !clipPlaying
  const canStartTrack = isHost && !finished && !!round && !wheelSpinning && !hasTrack

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
  // Slumpar en låt ur den inbyggda potten, slår upp URI:n mot Spotify (sök) och
  // startar den synkat. (Spotifys spellist-läsning är blockerad i dev-läge; sök funkar.)
  async function pickAndStart() {
    for (let attempt = 0; attempt < 12; attempt++) {
      const idx = Math.floor(Math.random() * TRACKS.length)
      if (recentRef.current.includes(idx)) continue
      const t = TRACKS[idx]
      let uri = null
      try {
        uri = await searchTrackUri(t.title, t.artist)
      } catch {
        continue // sökfel – prova en annan låt
      }
      if (uri) {
        recentRef.current = [idx, ...recentRef.current].slice(0, 50)
        await startTrack(room.id, uri, { name: t.title, artist: t.artist, year: String(t.year) })
        return
      }
    }
    throw new Error('Hittade ingen spelbar låt just nu – försök igen.')
  }
  const onStartTrack = () => run(pickAndStart)
  const onMark = (i) => run(() => markCross(room.id, i))
  const onUnmark = (i) => run(() => unmarkCross(room.id, i))
  const onErase = (cardId, i) => run(() => eraseCross(room.id, cardId, i))
  const onLockAnswer = (t) => run(() => lockAnswer(room.id, t))
  const onRevealAnswers = () => run(() => revealAnswers(room.id))
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
      {beforeStart && <Countdown secondsToStart={(startMs - now) / 1000} />}

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

      {/* Autoplay-upplåsning: gäster startar låten via en realtidshändelse (inget
          eget klick) → webbläsaren blockerar ljudet tills detta klick skett. */}
      {spotify.connected && spotify.deviceReady && !spotify.audioActivated && !spotify.isMobile && (
        <div
          className="panel flex flex-wrap items-center justify-between gap-3 p-4"
          style={{ '--neon': '#1ed760', borderColor: 'rgba(30,215,96,0.5)' }}
        >
          <p className="text-sm text-cream">
            🔊 <b>Aktivera ljudet</b> innan spelet börjar – annars hör du inte låten
            (webbläsaren kräver ett klick).
          </p>
          <NeonButton variant="outline" neon="#1ed760" onClick={() => spotify.activateAudio()}>
            Aktivera ljud
          </NeonButton>
        </div>
      )}

      {/* Diagnostik: visar var uppspelningen brister för DENNA spelare (så en
          gäst som inte hör låten kan se/rapportera exakt vad som saknas). */}
      {spotify.connected && !spotify.isMobile && (
        <div className="panel-inset px-4 py-2 text-xs">
          <span className="text-muted">Ljudstatus: </span>
          <span className={spotify.deviceReady ? 'text-lime' : 'text-magenta'}>
            enhet {spotify.deviceReady ? 'redo ✓' : 'ansluter… ✗'}
          </span>
          <span className="text-muted"> · </span>
          <span className={spotify.audioActivated ? 'text-lime' : 'text-magenta'}>
            ljud {spotify.audioActivated ? 'aktiverat ✓' : 'ej aktiverat ✗'}
          </span>
          <span className="text-muted"> · </span>
          <span className={spotify.isPremium ? 'text-lime' : 'text-magenta'}>
            {spotify.isPremium ? 'Premium ✓' : 'ej Premium ✗'}
          </span>
          {hasTrack && (
            <>
              <span className="text-muted"> · </span>
              <span className={clipPlaying ? 'text-lime' : 'text-muted'}>
                {beforeStart ? 'startar snart…' : clipPlaying ? 'spelar nu ♪' : 'väntar'}
              </span>
            </>
          )}
          {spotify.playbackError && (
            <p className="mt-1 text-magenta">⚠ {spotify.playbackError}</p>
          )}
        </div>
      )}

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
          <CategoryBanner round={round} spinning={wheelSpinning} />
          <div className="flex items-center gap-5">
            <DiscoWheel round={round} size={260} />
            {timerRunning && (
              <RoundTimer remaining={remaining} total={TIMER_SECONDS} color={timerColor} />
            )}
          </div>

          {clipPlaying && (
            <p className="anim-pulse neon-text font-display text-lg" style={{ '--neon': '#22e6e6' }}>
              🎵 Lyssna och gissa!
            </p>
          )}
          {/* Facit visas inte här – det avslöjas i svarspanelen först när alla lag låst. */}
          {needsManual && (beforeStart || clipPlaying) && trackOpenUrl && (
            <div className="panel-inset p-3 text-center text-sm">
              <p className="text-muted">
                Spelar inte i appen{spotify.isMobile ? ' (mobil)' : ''} – starta låten i din Spotify:
              </p>
              <a className="text-cyan underline" href={trackOpenUrl} target="_blank" rel="noreferrer">
                Öppna låten i Spotify
              </a>
            </div>
          )}

          {isHost ? (
            <div className="flex flex-col items-center gap-2">
              <div className="flex flex-wrap justify-center gap-3">
                <NeonButton onClick={onSpin} disabled={busy || !canSpin}>
                  {wheelSpinning ? 'Snurrar…' : round ? 'Snurra igen' : 'Snurra discokulan'}
                </NeonButton>
                {canStartTrack && (
                  <NeonButton
                    variant="outline"
                    neon="#1ed760"
                    onClick={onStartTrack}
                    disabled={busy || !spotify.connected}
                  >
                    {busy ? 'Startar…' : '▶ Starta låt'}
                  </NeonButton>
                )}
              </div>
              <p className="text-center text-xs text-muted">
                {!spotify.connected
                  ? 'Koppla din Spotify nedan för att spela låtar.'
                  : hasTrack
                    ? ''
                    : `🎵 ${TRACKS.length} låtar i potten – snurra och tryck "Starta låt".`}
              </p>
            </div>
          ) : (
            <p className="text-sm text-muted">
              {wheelSpinning
                ? 'Discokulan snurrar…'
                : beforeStart
                  ? 'Gör dig redo…'
                  : clipPlaying
                    ? 'Lyssna!'
                    : 'Värden styr rundan.'}
            </p>
          )}
          {err && <p className="text-sm text-magenta">{err}</p>}
        </div>
      </section>

      {/* Svarsfas: öppnas när låten spelat klart (timern slut) */}
      {revealed && (
        <AnswerPanel
          round={round}
          answers={answers}
          players={players}
          me={me}
          isHost={isHost}
          busy={busy}
          onLock={onLockAnswer}
          onReveal={onRevealAnswers}
        />
      )}

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

      <SpotifyPanel playerId={me?.id} inGame />
    </div>
  )
}
