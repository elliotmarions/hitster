import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import NeonButton from './ui/NeonButton.jsx'
import TextField from './ui/TextField.jsx'

/**
 * Litet konto-märke uppe till höger. Gäster kan spela vidare men erbjuds att
 * logga in med e-post för att spara statistik. Inloggade ser sin e-post + utloggning.
 */
export default function AccountBadge() {
  const { isConfigured, loading, isGuest, accountEmail, signInWithEmail, signOut } =
    useAuth()
  const [open, setOpen] = useState(false)
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(null) // null | 'upgrade' | 'existing'
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  if (!isConfigured) return null
  if (loading) return <span className="text-xs text-muted">…</span>

  async function submit(e) {
    e.preventDefault()
    setErr('')
    setBusy(true)
    try {
      const res = await signInWithEmail(email.trim())
      setSent(res.mode)
    } catch (e2) {
      setErr(e2.message || 'Något gick fel. Försök igen.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="relative">
      <button
        type="button"
        className="chip"
        style={{ '--neon': isGuest ? '#9a8fbf' : '#b6ff3c' }}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="max-w-[9rem] truncate">
          {isGuest ? 'Gäst' : accountEmail || 'Konto'}
        </span>
        <span aria-hidden>▾</span>
      </button>

      {open && (
        <>
          {/* klick-utanför-yta */}
          <button
            type="button"
            aria-label="Stäng"
            className="fixed inset-0 z-30 cursor-default"
            onClick={() => setOpen(false)}
          />
          <div className="panel absolute right-0 z-40 mt-2 w-72 p-4">
            <Link
              to="/statistik"
              onClick={() => setOpen(false)}
              className="mb-3 flex items-center gap-2 rounded-lg px-2 py-1.5 font-display text-cream hover:bg-white/5"
            >
              📊 Min statistik
            </Link>
            <div className="mb-3 border-t border-white/10" />
            {isGuest ? (
              sent ? (
                <div className="text-sm">
                  <p className="neon-text font-display" style={{ '--neon': '#b6ff3c' }}>
                    Kolla din mejl!
                  </p>
                  <p className="mt-2 text-muted">
                    {sent === 'upgrade'
                      ? 'Klicka på länken för att spara ditt konto – du behåller ditt namn och din statistik.'
                      : 'Vi hittade ett konto med den e-posten. Klicka på länken i mejlet för att logga in.'}
                  </p>
                </div>
              ) : (
                <form onSubmit={submit} className="space-y-3">
                  <p className="text-sm text-muted">
                    Du spelar som gäst. Logga in för att spara statistik mellan spel.
                  </p>
                  <TextField
                    type="email"
                    required
                    label="E-post"
                    placeholder="din@mejl.se"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                  {err && <p className="text-xs text-magenta">{err}</p>}
                  <NeonButton type="submit" disabled={busy} className="w-full">
                    {busy ? 'Skickar…' : 'Skicka inloggningslänk'}
                  </NeonButton>
                </form>
              )
            ) : (
              <div className="space-y-3 text-sm">
                <p className="text-muted">Inloggad som</p>
                <p className="truncate text-cream">{accountEmail}</p>
                <NeonButton
                  variant="ghost"
                  className="w-full"
                  onClick={async () => {
                    await signOut()
                    setOpen(false)
                  }}
                >
                  Logga ut
                </NeonButton>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}
