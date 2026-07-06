import { useState } from 'react'
import { CATEGORIES } from '../lib/constants'
import NeonButton from './ui/NeonButton.jsx'
import TrackReveal from './TrackReveal.jsx'

/**
 * Svarsfas: efter att låten spelat klart skriver varje lag sitt svar och
 * LÅSER IN det. När alla lag låst (round.answers_revealed) visas allas svar
 * + facit samtidigt.
 *
 * Props:
 *   round    – senaste rundan (har answers_revealed, locked_count, facit-meta)
 *   answers  – round_answers för rummet (RLS: bara mitt eget tills avslöjat)
 *   players  – rummets spelare (för namn + totalantal)
 *   me       – min player-rad
 *   isHost   – visar "Visa svar nu"-knappen
 *   busy     – knappar disablade under pågående RPC
 *   onLock   – (text) => void
 *   onReveal – () => void
 */
export default function AnswerPanel({ round, answers, players, me, isHost, busy, onLock, onReveal }) {
  const [text, setText] = useState('')
  if (!round) return null

  const roundAnswers = answers.filter((a) => a.round_id === round.id)
  const mine = roundAnswers.find((a) => a.player_id === me?.id)
  const revealed = Boolean(round.answers_revealed)
  const total = players.length
  const locked = round.locked_count ?? 0
  const iLocked = Boolean(mine?.locked)

  const cat = CATEGORIES[round.category]
  const nameOf = (pid) => players.find((p) => p.id === pid)?.display_name || 'Lag'

  // --- Avslöjat: visa allas svar + facit ---
  if (revealed) {
    const shown = [...roundAnswers].sort((a, b) =>
      nameOf(a.player_id).localeCompare(nameOf(b.player_id), 'sv'),
    )
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
            const isMe = a.player_id === me?.id
            return (
              <div
                key={a.id}
                className="panel-inset p-3"
                style={isMe ? { borderColor: 'rgba(34,230,230,0.5)' } : undefined}
              >
                <p className="label" style={{ color: isMe ? '#22e6e6' : undefined }}>
                  {nameOf(a.player_id)}
                  {isMe ? ' (du)' : ''}
                </p>
                <p className="mt-0.5 font-display text-lg text-cream break-words">
                  {a.answer?.trim() ? a.answer : <span className="text-muted">— inget svar —</span>}
                </p>
              </div>
            )
          })}
          {shown.length === 0 && <p className="text-sm text-muted">Inga svar registrerades.</p>}
        </div>

        <div className="flex justify-center pt-1">
          <TrackReveal meta={round.current_track_meta} category={round.category} />
        </div>
      </section>
    )
  }

  // --- Inte avslöjat än ---
  return (
    <section className="panel p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-xl text-cream">Ert svar</h2>
        <span className="text-sm text-muted">
          {locked} av {total} lag klara
        </span>
      </div>

      {/* Anonym låst-progress: en prick per lag. */}
      <div className="flex flex-wrap gap-1.5">
        {Array.from({ length: total }).map((_, i) => (
          <span
            key={i}
            className="h-2.5 w-2.5 rounded-full"
            style={{
              background: i < locked ? cat?.hex || '#22e6e6' : 'rgba(244,239,255,0.15)',
              boxShadow: i < locked ? `0 0 8px ${cat?.hex || '#22e6e6'}` : 'none',
            }}
          />
        ))}
      </div>

      {iLocked ? (
        <div className="panel-inset p-4 text-center">
          <p className="font-display text-lg text-cream">Ditt svar är inlåst 🔒</p>
          {mine.answer?.trim() && <p className="mt-1 text-sm text-muted">”{mine.answer}”</p>}
          <p className="mt-2 text-sm text-muted">Väntar på att alla lag låser in…</p>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-sm text-muted">
            {cat?.desc || 'Skriv ert svar och lås in det.'}
          </p>
          <textarea
            className="field min-h-[76px] resize-none"
            placeholder="Skriv ert svar här…"
            value={text}
            onChange={(e) => setText(e.target.value)}
            maxLength={200}
            autoFocus
          />
          <div className="flex justify-end">
            <NeonButton onClick={() => onLock(text.trim())} disabled={busy || !text.trim()}>
              Lås in svar 🔒
            </NeonButton>
          </div>
        </div>
      )}

      {isHost && (
        <div className="border-t border-white/10 pt-3 text-center">
          <NeonButton variant="ghost" onClick={onReveal} disabled={busy}>
            Visa svar nu
          </NeonButton>
          <p className="mt-1 text-xs text-muted">Värden kan avslöja även om något lag inte svarat.</p>
        </div>
      )}
    </section>
  )
}
