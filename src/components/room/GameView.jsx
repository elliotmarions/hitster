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
  overrideAnswer,
  resetGame,
} from '../../lib/game.js'
import { leaveRoom } from '../../lib/rooms.js'
import { useSyncedAudio } from '../../hooks/useSyncedAudio.js'
import { TRACKS } from '../../data/tracks.js'
import { searchPreviewUrl } from '../../lib/previewApi.js'
import DiscoWheel from '../DiscoWheel.jsx'
import CategoryBanner from '../CategoryBanner.jsx'
import RoundTimer from '../RoundTimer.jsx'
import BingoCard from '../BingoCard.jsx'
import WinBanner from '../WinBanner.jsx'
import HostLeftNotice from '../HostLeftNotice.jsx'
import VolumeControl from '../VolumeControl.jsx'
import Countdown from '../Countdown.jsx'
import AnswerPanel from '../AnswerPanel.jsx'
import NeonButton from '../ui/NeonButton.jsx'

export default function GameView({ room, players, teams = [], me, isHost }) {
  const navigate = useNavigate()
  const { round, cards, answers, refetch, optimisticCell, optimisticOverride } = useGame(room.id)
  // Synkad uppspelning av preview-klippet (samma ljud-URL hos alla vid start_at).
  const audio = useSyncedAudio(round)

  const [now, setNow] = useState(() => Date.now())
  const [wheelSpinning, setWheelSpinning] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [markedRoundId, setMarkedRoundId] = useState(null) // runda där jag redan kryssat (optimistiskt)
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
  // Värden lämnade → spelet avslutat utan vinnare (visar notis, inte vinstbanner).
  const hostLeft = finished && room.ended_reason === 'host_left'
  // timer_start_at sätts först när värden trycker "Starta låt" (= start_at).
  const startMs = round?.timer_start_at ? new Date(round.timer_start_at).getTime() : null
  const hasTrack = Boolean(round?.current_track_id)
  const remaining = startMs != null ? TIMER_SECONDS - (now - startMs) / 1000 : 0

  // Uppspelningsfaser (efter "Starta låt").
  const beforeStart = hasTrack && startMs != null && now < startMs
  const clipPlaying = hasTrack && startMs != null && now >= startMs && now < startMs + TIMER_SECONDS * 1000
  const revealed = hasTrack && startMs != null && now >= startMs + TIMER_SECONDS * 1000
  const timerRunning = clipPlaying && remaining > 0

  const teamMode = Boolean(room.team_mode)
  const myTeamId = me?.team_id
  const playerName = (pid) => players.find((p) => p.id === pid)?.display_name || 'Spelare'
  const teamName = (tid) => teams.find((t) => t.id === tid)?.name || 'Lag'
  // Namnet på den enhet (lag/spelare) som en bricka tillhör.
  const cardName = (c) => (teamMode ? teamName(c.team_id) : playerName(c.player_id))

  // "Min" bricka = mitt lags bricka (lagläge) eller min egen (solo).
  const myCard = teamMode
    ? cards.find((c) => c.team_id && c.team_id === myTeamId)
    : cards.find((c) => c.player_id === me?.id)
  const otherCards = cards.filter((c) => c.id !== myCard?.id)

  // Kategorin gäller så fort hjulet landat.
  const currentCategory = round && !wheelSpinning ? round.category : null

  // Svarsspärr: när en låt spelats får man kryssa/sudda först när svaren
  // avslöjats OCH den egna enhetens svar validerats som RÄTT (server-styrt;
  // effektiv dom = värdens override ?? auto). Speglar mark_cross/erase_cross.
  const myRoundAnswer = round
    ? answers.find(
        (a) =>
          a.round_id === round.id &&
          (teamMode ? a.team_id === myTeamId : a.player_id === me?.id),
      )
    : null
  const myAnswerCorrect = myRoundAnswer
    ? (myRoundAnswer.override_correct ?? myRoundAnswer.auto_correct) === true
    : false
  // Kryss kräver att DENNA rundas låt spelats, avslöjats och att det egna
  // svaret var rätt. Utan låt (nyss snurrat) är grinden stängd – annars kunde
  // man kryssa direkt efter snurret innan man gissat. Speglar mark_cross.
  const answerGateOk = hasTrack && revealed && myAnswerCorrect

  // Rätt svar ger bara ETT kryss per runda (server-styrt via round_answers.has_marked;
  // markedRoundId speglar det optimistiskt så knappen låses direkt vid klick).
  const alreadyMarkedThisRound =
    (round && markedRoundId === round.id) || myRoundAnswer?.has_marked === true

  const canMark =
    !finished &&
    !!currentCategory &&
    !myCard?.has_won &&
    answerGateOk &&
    !(hasTrack && alreadyMarkedThisRound)
  const canUnmark = !finished
  const canErase =
    !finished && room.erase_rule_enabled && currentCategory === 'exact_year' && answerGateOk

  // Förklaring till varför kryssning är låst/öppen just nu.
  const markHint =
    finished || !currentCategory || myCard?.has_won
      ? null
      : !hasTrack
        ? 'Starta låten och gissa innan ni kryssar.'
        : !revealed
          ? 'Lås in ert svar och vänta på facit innan ni kryssar.'
          : !myAnswerCorrect
            ? 'Fel svar den här rundan – ingen kryssning.'
            : alreadyMarkedThisRound
              ? 'Kryss placerat – ett per runda. Klicka på krysset för att ändra.'
              : 'ok'

  // Snurr-spärr: lämna inte en avslöjad runda medan någon rätt-svarande ännu
  // inte kryssat (och har en ledig ruta i kategorin att kryssa). Speglar spin_wheel.
  const pendingCross = Boolean(
    round &&
      revealed &&
      answers.some((a) => {
        if (a.round_id !== round.id) return false
        if ((a.override_correct ?? a.auto_correct) !== true) return false
        if (a.has_marked === true) return false
        const card = teamMode
          ? cards.find((c) => c.team_id && c.team_id === a.team_id)
          : cards.find((c) => c.player_id === a.player_id)
        return card?.grid?.some((cell) => cell.category === round.category && !cell.filled)
      }),
  )

  // Värdens kontroller
  const canSpin = isHost && !finished && !wheelSpinning && !beforeStart && !clipPlaying && !pendingCross
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

  // Optimistisk åtgärd: visa ändringen lokalt direkt, skicka till servern i
  // bakgrunden (blockerar inte UI:t), backa via refetch om det blir fel.
  function optimistic(applyLocal, rpc) {
    setErr('')
    applyLocal()
    Promise.resolve()
      .then(rpc)
      .catch((e) => {
        setErr(e.message || 'Något gick fel.')
        refetch()
      })
  }

  const onSpin = () => run(() => spinWheel(room.id))
  // Slumpar en låt ur potten, slår upp ett preview-klipp (iTunes) och startar det
  // synkat hos alla. Ingen inloggning krävs – klippet är en publik ljud-URL.
  async function pickAndStart() {
    for (let attempt = 0; attempt < 15; attempt++) {
      const idx = Math.floor(Math.random() * TRACKS.length)
      if (recentRef.current.includes(idx)) continue
      const t = TRACKS[idx]
      let previewUrl = null
      try {
        previewUrl = await searchPreviewUrl(t.title, t.artist)
      } catch {
        continue // sökfel – prova en annan låt
      }
      if (previewUrl) {
        recentRef.current = [idx, ...recentRef.current].slice(0, 50)
        await startTrack(room.id, previewUrl, {
          name: t.title,
          artist: t.artist,
          year: String(t.year),
        })
        return
      }
    }
    throw new Error('Hittade ingen spelbar låt just nu – försök igen.')
  }
  const onStartTrack = () => run(pickAndStart)
  const onMark = (i) =>
    myCard &&
    optimistic(
      () => {
        optimisticCell(myCard.id, i, true)
        if (round?.id) setMarkedRoundId(round.id) // lås fler kryss direkt (ett per runda)
      },
      () => markCross(room.id, i),
    )
  const onUnmark = (i) =>
    myCard &&
    optimistic(
      () => {
        optimisticCell(myCard.id, i, false)
        setMarkedRoundId(null) // frigör rundans kryss så felklick kan läggas om
      },
      () => unmarkCross(room.id, i),
    )
  const onErase = (cardId, i) =>
    optimistic(
      () => optimisticCell(cardId, i, false),
      () => eraseCross(room.id, cardId, i),
    )
  const onLockAnswer = (t) => run(() => lockAnswer(room.id, t))
  const onRevealAnswers = () => run(() => revealAnswers(room.id))
  const onOverrideAnswer = (answerId, correct) =>
    optimistic(
      () => optimisticOverride(answerId, correct),
      () => overrideAnswer(room.id, answerId, correct),
    )
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
            {teamMode ? `${teams.length} lag · ${players.length} spelare` : `${players.length} spelare`}
          </span>
          <NeonButton variant="ghost" onClick={handleLeave}>
            Lämna
          </NeonButton>
        </div>
      </div>

      {/* Ljud-upplåsning: klippet startas åt spelaren av en realtidshändelse (inget
          eget klick) → webbläsaren blockerar ljudet tills detta klick skett. Varje
          spelare klickar en gång innan spelet börjar. */}
      {!audio.ready && (
        <div
          className="panel flex flex-wrap items-center justify-between gap-3 p-4"
          style={{ '--neon': '#1ed760', borderColor: 'rgba(30,215,96,0.5)' }}
        >
          <p className="text-sm text-cream">
            🔊 <b>Aktivera ljudet</b> innan spelet börjar – annars hör du inte låten
            (webbläsaren kräver ett klick).
          </p>
          <NeonButton variant="outline" neon="#1ed760" onClick={() => audio.unlock()}>
            Aktivera ljud
          </NeonButton>
        </div>
      )}

      {hostLeft && <HostLeftNotice onBack={() => navigate('/')} />}

      {finished && !hostLeft && (
        <WinBanner
          winnerName={teamMode ? teamName(room.winner_team_id) : playerName(room.winner_player_id)}
          isMe={Boolean(myCard?.has_won)}
          teamMode={teamMode}
          isHost={isHost}
          busy={busy}
          onPlayAgain={onPlayAgain}
          onBackToLobby={onBackToLobby}
        />
      )}

      {/* Scen: discokula + kategori + timer */}
      <section className="panel relative p-6">
        {/* Kompakt volymkontroll i hörnet. */}
        <div className="absolute right-3 top-3 z-20">
          <VolumeControl volume={audio.volume} setVolume={audio.setVolume} />
        </div>
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
          {audio.error && (beforeStart || clipPlaying) && (
            <p className="panel-inset p-3 text-center text-sm text-magenta">⚠ {audio.error}</p>
          )}

          {isHost ? (
            <div className="flex flex-col items-center gap-2">
              <div className="flex flex-wrap justify-center gap-3">
                <NeonButton onClick={onSpin} disabled={busy || !canSpin}>
                  {wheelSpinning ? 'Snurrar…' : round ? 'Snurra igen' : 'Snurra discokulan'}
                </NeonButton>
                {canStartTrack && (
                  <NeonButton variant="outline" neon="#1ed760" onClick={onStartTrack} disabled={busy}>
                    {busy ? 'Startar…' : '▶ Starta låt'}
                  </NeonButton>
                )}
              </div>
              <p className="text-center text-xs text-muted">
                {pendingCross
                  ? '⏳ Alla som hade rätt måste kryssa innan du kan snurra igen.'
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
          teams={teams}
          teamMode={teamMode}
          myUnitId={teamMode ? myTeamId : me?.id}
          isHost={isHost}
          busy={busy}
          onLock={onLockAnswer}
          onReveal={onRevealAnswers}
          onOverride={onOverrideAnswer}
        />
      )}

      {/* Egen bricka */}
      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">
            {teamMode ? (myTeamId ? `Ert lag: ${teamName(myTeamId)}` : 'Din bricka') : 'Din bricka'}
          </h2>
          {markHint === 'ok' && CATEGORIES[currentCategory] ? (
            <span className="text-xs" style={{ color: '#3ee87b' }}>
              ✓ Rätt! Kryssa en{' '}
              <b style={{ color: CATEGORIES[currentCategory].hex }}>
                {CATEGORIES[currentCategory].short}
              </b>
              -ruta
            </span>
          ) : (
            markHint && <span className="text-xs text-muted">🔒 {markHint}</span>
          )}
        </div>
        {myCard ? (
          <div className="mx-auto max-w-[380px] space-y-2">
            <BingoCard
              card={myCard}
              playerName={teamMode ? teamName(myTeamId) : me?.display_name}
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

      {/* Övriga brickor – full insyn */}
      {otherCards.length > 0 && (
        <section>
          <h2 className="mb-2 font-display text-xl text-cream">
            {teamMode ? 'Andra lag' : 'Medspelare'}
          </h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
            {otherCards.map((c) => (
              <BingoCard
                key={c.id}
                card={c}
                playerName={cardName(c)}
                currentCategory={currentCategory}
                canErase={canErase}
                onErase={(i) => onErase(c.id, i)}
                variant="sm"
              />
            ))}
          </div>
          {canErase && (
            <p className="mt-2 text-xs text-muted">
              Suddregel aktiv: klicka ett kryss på {teamMode ? 'ett annat lags' : 'en medspelares'}{' '}
              bricka för att sudda.
            </p>
          )}
        </section>
      )}
    </div>
  )
}
