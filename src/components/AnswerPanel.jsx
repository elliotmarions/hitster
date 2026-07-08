import { useState } from 'react'
import { CATEGORIES } from '../lib/constants'
import NeonButton from './ui/NeonButton.jsx'
import TrackReveal from './TrackReveal.jsx'

/**
 * Svarsfas: efter att låten spelat klart skriver varje enhet (lag i lagläge,
 * annars varje spelare) sitt svar och LÅSER IN det. När alla låst
 * (round.answers_revealed) visas allas svar + facit samtidigt.
 *
 * Props:
 *   round    – senaste rundan (answers_revealed, locked_count, facit-meta)
 *   answers  – round_answers för rummet (RLS: bara mitt eget tills avslöjat)
 *   players  – rummets spelare
 *   teams    – rummets lag (lagläge)
 *   teamMode – spelar vi i lag?
 *   myUnitId – mitt lag-id (lagläge) eller mitt player-id (solo)
 *   me       – min player-rad
 *   isHost   – visar "Visa svar nu"-knappen
 *   busy     – knappar disablade under pågående RPC
 *   onLock   – (text) => void
 *   onReveal – () => void
 */
export default function AnswerPanel({
  round,
  answers,
  players,
  teams = [],
  teamMode = false,
  myUnitId,
  isHost,
  busy,
  canLock = true,
  onLock,
  onReveal,
  onOverride,
}) {
  const [text, setText] = useState('')
  if (!round) return null

  const unitWord = teamMode ? 'lag' : 'spelare'
  const roundAnswers = answers.filter((a) => a.round_id === round.id)
  const unitIdOf = (a) => (teamMode ? a.team_id : a.player_id)
  const nameOf = (a) =>
    teamMode
      ? teams.find((t) => t.id === a.team_id)?.name || 'Lag'
      : players.find((p) => p.id === a.player_id)?.display_name || 'Spelare'

  const mine = roundAnswers.find((a) => unitIdOf(a) === myUnitId)
  const revealed = Boolean(round.answers_revealed)
  const total = teamMode ? teams.length : players.length
  const locked = round.locked_count ?? 0
  const iLocked = Boolean(mine?.locked)
  const cat = CATEGORIES[round.category]

  // Årtals-kategorier kräver ett HELT fyrsiffrigt årtal (1900–2099) – "67"
  // godtas inte. Speglar serverns facit-regex (?:19|20)\d{2}. Blockerar
  // inlåsning tills formatet stämmer.
  const isYearCat = round.category === 'exact_year' || round.category === 'approx_year'
  const yearFormatBad = isYearCat && text.trim() !== '' && !/(?:19|20)\d{2}/.test(text)

  // --- Avslöjat: visa allas svar + facit ---
  if (revealed) {
    const shown = [...roundAnswers].sort((a, b) => nameOf(a).localeCompare(nameOf(b), 'sv'))
    return (
      <section className="panel p-5 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">Allas svar</h2>
          <span className="chip" style={{ '--neon': cat?.hex || '#22e6e6' }}>
            {cat?.short || 'Svar'}
          </span>
        </div>

        <div className="grid gap-2 sm:grid-cols-2">
          {shown.map((a) => {
            const isMe = unitIdOf(a) === myUnitId
            // Domen räknas server-side vid avslöjandet (auto_correct); värden kan
            // överstyra (override_correct). Effektiv dom = override ?? auto.
            const overridden = a.override_correct !== null && a.override_correct !== undefined
            const correct = overridden ? a.override_correct : a.auto_correct === true
            const good = '#3ee87b'
            const bad = '#ff4d9d'
            return (
              <div
                key={a.id}
                className="panel-inset p-3"
                style={{ borderColor: correct ? `${good}66` : `${bad}55` }}
              >
                <div className="flex items-center justify-between gap-2">
                  <p className="label" style={{ color: isMe ? '#22e6e6' : undefined }}>
                    {nameOf(a)}
                    {isMe ? (teamMode ? ' (ni)' : ' (du)') : ''}
                  </p>
                  <span className="chip shrink-0" style={{ '--neon': correct ? good : bad }}>
                    {correct ? '✓ Rätt' : '✗ Fel'}
                  </span>
                </div>
                <p className="mt-0.5 font-display text-lg text-cream break-words">
                  {a.answer?.trim() ? a.answer : <span className="text-muted">— inget svar —</span>}
                </p>

                {isHost && (
                  <div className="mt-2 flex items-center gap-1.5 text-xs">
                    <span className="text-muted">Rätta:</span>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => onOverride?.(a.id, true)}
                      className="rounded px-1.5 py-0.5"
                      style={{
                        border: `1px solid ${good}`,
                        color: correct ? '#140c22' : good,
                        background: correct ? good : 'transparent',
                      }}
                    >
                      ✓
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => onOverride?.(a.id, false)}
                      className="rounded px-1.5 py-0.5"
                      style={{
                        border: `1px solid ${bad}`,
                        color: !correct ? '#140c22' : bad,
                        background: !correct ? bad : 'transparent',
                      }}
                    >
                      ✗
                    </button>
                    {overridden && (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => onOverride?.(a.id, null)}
                        className="text-muted underline"
                      >
                        auto
                      </button>
                    )}
                  </div>
                )}
                {overridden && <p className="mt-1 text-[10px] text-muted">rättat av värden</p>}
              </div>
            )
          })}
          {shown.length === 0 && <p className="text-sm text-muted">Inga svar registrerades.</p>}
        </div>
        <p className="text-center text-[11px] text-muted">
          ✓/✗ är auto-bedömt mot facit{isHost ? ' – tryck ✓/✗ för att rätta.' : '.'}
        </p>

        <div className="flex justify-center pt-1">
          <TrackReveal meta={round.current_track_meta} category={round.category} />
        </div>
      </section>
    )
  }

  // --- Inte avslöjat än: en ruta per enhet, din egen är inmatningen ---
  // Vilka enheter som låst kommer från round.locked_units (server, utan att
  // läcka svarstexten). Din egen status speglas även av mine.locked så den
  // känns direkt vid inlåsning.
  const lockedUnits = new Set(round.locked_units || [])
  const units = teamMode
    ? teams.map((t) => ({ id: t.id, name: t.name || 'Lag' }))
    : players.map((p) => ({ id: p.id, name: p.display_name || 'Spelare' }))
  const good = '#3ee87b'

  return (
    <section className="panel p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-xl text-cream">Svar</h2>
        <span className="text-sm text-muted">
          {locked} av {total} {unitWord} klara
        </span>
      </div>

      <div
        className="grid gap-3"
        style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))' }}
      >
        {units.map((u) => {
          const isMe = u.id === myUnitId
          const unitLocked = lockedUnits.has(u.id) || (isMe && iLocked)
          return (
            <div
              key={u.id}
              className="panel-inset flex flex-col p-3"
              style={{
                borderColor: unitLocked
                  ? `${good}66`
                  : isMe
                    ? 'rgba(34,230,230,0.4)'
                    : undefined,
                boxShadow: unitLocked ? `0 0 18px -8px ${good}` : undefined,
              }}
            >
              <div className="flex items-center justify-between gap-2">
                <p className="label truncate" style={{ color: isMe ? '#22e6e6' : undefined }}>
                  {u.name}
                  {isMe ? (teamMode ? ' (ni)' : ' (du)') : ''}
                </p>
                {unitLocked ? (
                  <span className="chip shrink-0" style={{ '--neon': good }}>
                    🔒 Låst
                  </span>
                ) : (
                  <span className="shrink-0 text-xs text-muted">skriver…</span>
                )}
              </div>

              {/* Egen ruta = inmatning; andras = bara status (svaret döljs). */}
              {isMe ? (
                unitLocked ? (
                  <div className="mt-2">
                    <p className="font-display text-lg text-cream break-words">
                      {mine?.answer?.trim() ? (
                        mine.answer
                      ) : (
                        <span className="text-muted">— inget svar —</span>
                      )}
                    </p>
                    <p className="mt-1 text-xs text-muted">
                      Väntar på att alla {unitWord} låser in…
                    </p>
                  </div>
                ) : (
                  <div className="mt-2 space-y-2">
                    <textarea
                      className="field min-h-[64px] resize-none"
                      placeholder={
                        isYearCat ? 'Skriv hela årtalet, t.ex. 1967' : cat?.desc || 'Skriv ert svar…'
                      }
                      value={text}
                      onChange={(e) => setText(e.target.value)}
                      maxLength={200}
                      autoFocus
                    />
                    {yearFormatBad && (
                      <p className="text-xs text-magenta">
                        ⚠ Skriv hela årtalet, t.ex. <b>1967</b> – inte ”67”.
                      </p>
                    )}
                    <NeonButton
                      onClick={() => onLock(text.trim())}
                      disabled={busy || !text.trim() || yearFormatBad || !canLock}
                      className="w-full"
                    >
                      Lås in 🔒
                    </NeonButton>
                    {!canLock && (
                      <p className="text-[11px] text-muted">
                        🎵 Skriv medan låten spelar – lås in när klippet är slut.
                      </p>
                    )}
                  </div>
                )
              ) : (
                <div className="mt-2 flex flex-1 items-center justify-center py-3 text-center">
                  {unitLocked ? (
                    <p className="font-display text-lg" style={{ color: good }}>
                      🔒 Klar!
                    </p>
                  ) : (
                    <p className="text-sm text-muted">Väntar…</p>
                  )}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {isHost && canLock && (
        <div className="border-t border-white/10 pt-3 text-center">
          <NeonButton variant="ghost" onClick={onReveal} disabled={busy}>
            Visa svar nu
          </NeonButton>
          <p className="mt-1 text-xs text-muted">
            Värden kan avslöja även om något {unitWord} inte svarat.
          </p>
        </div>
      )}
    </section>
  )
}
