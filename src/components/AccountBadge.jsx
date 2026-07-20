import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import NeonButton from './ui/NeonButton.jsx'
import TextField from './ui/TextField.jsx'

/**
 * Konto-märke uppe till höger.
 *
 * Gäster får en tydlig "Logga in"-knapp som leder till /konto – själva
 * inloggningen bor där, inte i en gömd meny. Inloggade ser sitt namn och kan
 * fälla ut en meny för statistik, namnbyte och utloggning.
 */
export default function AccountBadge() {
  const {
    isConfigured,
    loading,
    isGuest,
    accountEmail,
    accountName,
    preferredName,
    updateAccountName,
    signOut,
  } = useAuth()
  const [open, setOpen] = useState(false)
  const [nameField, setNameField] = useState(() => accountName || preferredName || '')
  const [nameBusy, setNameBusy] = useState(false)
  const [nameErr, setNameErr] = useState('')
  const [nameSaved, setNameSaved] = useState(false)

  if (!isConfigured) return null
  if (loading) return <span className="text-xs text-muted">…</span>

  // Gäst: chipen är en ren uppmaning som leder till kontosidan.
  if (isGuest) {
    return (
      <Link
        to="/konto"
        className="chip chip-cta cursor-pointer transition hover:brightness-125"
        style={{ '--neon': '#22e6e6' }}
      >
        <span aria-hidden>👤</span>
        <span>Logga in</span>
      </Link>
    )
  }

  const badgeLabel = accountName || preferredName || 'Konto'
  const needsName = !accountName

  async function saveName(e) {
    e.preventDefault()
    setNameErr('')
    setNameSaved(false)
    setNameBusy(true)
    try {
      await updateAccountName(nameField.trim())
      setNameSaved(true)
    } catch (e2) {
      setNameErr(e2.message || 'Kunde inte spara namnet.')
    } finally {
      setNameBusy(false)
    }
  }

  return (
    <div className="relative">
      <button
        type="button"
        className="chip cursor-pointer transition hover:brightness-125"
        style={{ '--neon': '#b6ff3c' }}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="max-w-[9rem] truncate">{badgeLabel}</span>
        {needsName && <span title="Välj ett namn" aria-hidden>·</span>}
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

            <div className="space-y-3 text-sm">
              <form onSubmit={saveName} className="space-y-2">
                <TextField
                  label="Ditt namn"
                  placeholder="Välj ett namn"
                  maxLength={24}
                  value={nameField}
                  onChange={(e) => {
                    setNameField(e.target.value)
                    setNameSaved(false)
                  }}
                />
                {needsName && !nameSaved && (
                  <p className="text-xs text-muted">
                    Välj ett namn så syns det här uppe i stället för din e-post.
                  </p>
                )}
                {nameErr && <p className="text-xs text-magenta">{nameErr}</p>}
                {nameSaved && <p className="text-xs text-lime">Sparat ✓</p>}
                <NeonButton
                  type="submit"
                  disabled={nameBusy || !nameField.trim()}
                  className="w-full"
                >
                  {nameBusy ? 'Sparar…' : 'Spara namn'}
                </NeonButton>
              </form>

              <p className="truncate text-xs text-muted">Inloggad som {accountEmail}</p>
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
          </div>
        </>
      )}
    </div>
  )
}
