import { useEffect, useRef, useState } from 'react'
import { useTeamChat } from '../hooks/useTeamChat.js'

/**
 * Lagets privata chatt – en flytande docka nere i hörnet.
 *
 * Bara lagkamraterna ser innehållet (RLS på team_messages), så det är här man
 * resonerar om artist och årtal utan att motståndarna läser med. Dockan är
 * medvetet INGEN modal: spelet ska synas bakom medan man skriver, så det går
 * att lyssna, chatta och kryssa samtidigt.
 *
 * Props:
 *   room  – rummet (team_mode avgör om chatten finns alls)
 *   me    – min players-rad (team_id = mitt lag)
 *   teams – rummets lag (för namn/färg)
 */
export default function TeamChat({ room, me, teams = [] }) {
  const teamId = me?.team_id || null
  const enabled = Boolean(room?.team_mode && teamId)
  const [open, setOpen] = useState(false)
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  // Allt som skrivits av någon annan efter den här tidpunkten räknas som oläst.
  // Startar på "nu" så gammal historik inte lyser upp bricka-knappen vid join.
  const [seenAt, setSeenAt] = useState(() => new Date().toISOString())
  const listRef = useRef(null)
  const inputRef = useRef(null)

  const { messages, loading, error, send } = useTeamChat(enabled ? room.id : null, teamId)

  const team = teams.find((t) => t.id === teamId)
  const neon = team?.color || '#22e6e6'
  const unread = messages.filter((m) => m.user_id !== me?.user_id && m.created_at > seenAt).length

  // Öppen chatt = allt är läst (även det som trillar in medan den är öppen).
  useEffect(() => {
    if (!open || messages.length === 0) return
    setSeenAt(messages[messages.length - 1].created_at)
  }, [open, messages])

  // Håll senaste meddelandet i sikte.
  useEffect(() => {
    if (!open || !listRef.current) return
    listRef.current.scrollTop = listRef.current.scrollHeight
  }, [open, messages])

  // Esc stänger (fokus ligger oftast i skrivfältet).
  useEffect(() => {
    if (!open) return
    const onKey = (e) => {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  if (!enabled) return null

  async function handleSubmit(e) {
    e.preventDefault()
    const body = text.trim()
    if (!body || sending) return
    setSending(true)
    const ok = await send(body)
    setSending(false)
    if (ok) setText('')
    inputRef.current?.focus()
  }

  const clock = (iso) =>
    new Date(iso).toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit' })

  return (
    <div className="fixed bottom-4 right-4 z-40 flex flex-col items-end gap-2">
      {open && (
        <section
          className="panel flex w-[min(22rem,calc(100vw-2rem))] flex-col overflow-hidden p-0"
          style={{
            height: 'min(60dvh, 26rem)',
            borderColor: neon,
            boxShadow: `0 0 40px -14px ${neon}`,
          }}
          aria-label={`Lagchatt för ${team?.name || 'ditt lag'}`}
        >
          <header
            className="flex items-center justify-between gap-2 border-b border-white/10 px-3 py-2"
            style={{ background: `color-mix(in srgb, ${neon} 12%, transparent)` }}
          >
            <div className="min-w-0">
              <p className="label truncate" style={{ color: neon }}>
                💬 {team?.name || 'Ditt lag'}
              </p>
              <p className="text-[10px] text-muted">Bara ditt lag ser det här</p>
            </div>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="shrink-0 rounded px-2 py-1 text-sm text-muted hover:text-cream"
              aria-label="Stäng lagchatten"
            >
              ✕
            </button>
          </header>

          <div ref={listRef} className="flex-1 space-y-2 overflow-y-auto px-3 py-3">
            {loading ? (
              <p className="text-center text-xs text-muted">Hämtar…</p>
            ) : messages.length === 0 ? (
              <p className="text-center text-xs text-muted">
                Inga meddelanden än. Skriv vad ni tror – artist, årtal, känsla.
              </p>
            ) : (
              messages.map((m) => {
                const mine = m.user_id === me?.user_id
                return (
                  <div key={m.id} className={mine ? 'flex justify-end' : 'flex justify-start'}>
                    <div
                      className="max-w-[85%] rounded-xl px-2.5 py-1.5"
                      style={{
                        background: mine
                          ? `color-mix(in srgb, ${neon} 20%, transparent)`
                          : 'rgba(255,255,255,0.06)',
                        border: `1px solid ${mine ? `color-mix(in srgb, ${neon} 45%, transparent)` : 'rgba(255,255,255,0.10)'}`,
                      }}
                    >
                      {!mine && (
                        <p className="text-[10px] uppercase tracking-wide text-muted">
                          {m.author_name}
                        </p>
                      )}
                      <p className="break-words text-sm text-cream">{m.body}</p>
                      <p className="mt-0.5 text-right text-[10px] text-muted">
                        {clock(m.created_at)}
                      </p>
                    </div>
                  </div>
                )
              })
            )}
          </div>

          {error && <p className="px-3 pb-1 text-xs text-magenta">{error}</p>}

          <form onSubmit={handleSubmit} className="flex gap-2 border-t border-white/10 p-2">
            <input
              ref={inputRef}
              className="field flex-1 py-2 text-sm"
              placeholder="Skriv till laget…"
              value={text}
              onChange={(e) => setText(e.target.value)}
              maxLength={300}
              autoFocus
            />
            <button
              type="submit"
              disabled={sending || !text.trim()}
              className="btn btn-outline px-3 py-2 text-sm"
              style={{ '--neon': neon }}
            >
              Skicka
            </button>
          </form>
        </section>
      )}

      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="btn btn-outline relative h-12 w-12 rounded-full p-0 text-xl"
        style={{ '--neon': neon }}
        aria-label={open ? 'Stäng lagchatten' : 'Öppna lagchatten'}
      >
        💬
        {!open && unread > 0 && (
          <span
            className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full px-1 font-display text-[11px]"
            style={{ background: '#ff2e9a', color: '#140c22' }}
          >
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>
    </div>
  )
}
