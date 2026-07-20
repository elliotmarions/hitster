import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import NeonButton from './ui/NeonButton.jsx'

/**
 * Konto-märke uppe till höger.
 *
 * Gäster får en tydlig "Logga in"-knapp som leder till /konto – själva
 * inloggningen bor där, inte i en gömd meny. Inloggade ser sitt namn och en
 * liten meny med genväg till profilen och utloggning. All redigering (namn,
 * statistik) sker på /profil, inte här i menyn.
 */
export default function AccountBadge() {
  const { isConfigured, loading, isGuest, accountEmail, accountName, preferredName, signOut } =
    useAuth()
  const [open, setOpen] = useState(false)

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
        <span>Logga in</span>
      </Link>
    )
  }

  const badgeLabel = accountName || preferredName || 'Konto'
  // Har man inte valt namn än: liten prick som lockar in i profilen.
  const needsName = !accountName

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
          <div className="panel absolute right-0 z-40 mt-2 w-64 p-4">
            <Link
              to="/profil"
              onClick={() => setOpen(false)}
              className="flex items-center gap-2 rounded-lg px-2 py-1.5 font-display text-cream hover:bg-white/5"
            >
              👤 Profil
            </Link>

            <div className="my-3 border-t border-white/10" />

            <p className="mb-3 truncate px-2 text-xs text-muted">
              Inloggad som {accountEmail}
            </p>
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
        </>
      )}
    </div>
  )
}
