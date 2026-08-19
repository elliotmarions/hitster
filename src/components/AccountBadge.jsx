import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { useNavGuardRunner } from '../context/NavGuardContext.jsx'
import NeonButton from './ui/NeonButton.jsx'

/**
 * En rad i kontomenyn. Ser likadan ut oavsett vart den leder, så menyn läses
 * som en lista och inte som en samling lösa länkar.
 */
function MenuRow({ to, onClick, children, hint }) {
  return (
    <Link
      to={to}
      onClick={onClick}
      role="menuitem"
      className="group flex items-center justify-between gap-3 rounded-xl px-3 py-2.5 transition hover:bg-white/[0.07] focus-visible:bg-white/[0.07] focus-visible:outline-none"
    >
      <span className="min-w-0">
        <span className="block font-display text-sm text-cream">{children}</span>
        {hint && <span className="mt-0.5 block text-xs text-muted">{hint}</span>}
      </span>
      <span
        aria-hidden
        className="text-muted transition group-hover:translate-x-0.5 group-hover:text-cyan"
      >
        ›
      </span>
    </Link>
  )
}

/**
 * Konto-märke uppe till höger.
 *
 * Gäster får en tydlig "Logga in"-knapp som leder till /konto – själva
 * inloggningen bor där, inte i en gömd meny. Inloggade ser sitt namn och en
 * meny med genvägarna som faktiskt saknas någon annanstans: profilen (namn och
 * statistik) och lösenordsbytet. All redigering sker på respektive sida, inte
 * här i menyn.
 */
export default function AccountBadge() {
  const { isConfigured, loading, isGuest, accountEmail, accountName, preferredName, signOut } =
    useAuth()
  const [open, setOpen] = useState(false)
  const rootRef = useRef(null)
  // Mitt i en match är varje rad i menyn en väg UT ur spelet, precis som
  // logotypen. Samma spärr gäller därför här: rummet får ställa sin fråga
  // först. (Gamla "Profil"-länken gick förbi den och slängde ut spelaren.)
  const runGuard = useNavGuardRunner()

  // Escape stänger menyn, och fokus går tillbaka till chipen. Utan det satt
  // man fast i menyn så fort man öppnat den med tangentbordet.
  useEffect(() => {
    if (!open) return
    function onKey(e) {
      if (e.key !== 'Escape') return
      setOpen(false)
      rootRef.current?.querySelector('button')?.focus()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

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
  // Har man inte valt namn än: en prick på chipen som lockar in i profilen,
  // och en rad i menyn som säger vad pricken handlar om.
  const needsName = !accountName
  const close = () => setOpen(false)

  function navigateAway(e) {
    setOpen(false)
    if (runGuard()) e.preventDefault()
  }

  return (
    <div className="relative" ref={rootRef}>
      <button
        type="button"
        className="chip cursor-pointer transition hover:brightness-125"
        style={{ '--neon': '#b6ff3c' }}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="max-w-[9rem] truncate">{badgeLabel}</span>
        {needsName && (
          <span
            aria-hidden
            title="Välj ett namn"
            className="h-1.5 w-1.5 shrink-0 rounded-full bg-cyan shadow-[0_0_8px_#22e6e6]"
          />
        )}
        <span aria-hidden className={`transition ${open ? 'rotate-180' : ''}`}>
          ▾
        </span>
      </button>

      {open && (
        <>
          {/* klick-utanför-yta */}
          <button
            type="button"
            aria-label="Stäng"
            className="fixed inset-0 z-30 cursor-default"
            onClick={close}
          />
          <div
            role="menu"
            aria-label="Kontomeny"
            className="panel absolute right-0 z-40 mt-2 w-72 overflow-hidden"
          >
            {/* Vem är inloggad – överst, där man tittar först. */}
            <div className="border-b border-white/10 px-4 py-3.5">
              <p className="label">Inloggad</p>
              <p className="mt-1 truncate font-display text-cream">{badgeLabel}</p>
              <p className="mt-0.5 truncate text-xs text-muted">{accountEmail}</p>
            </div>

            <nav className="space-y-0.5 p-2">
              <MenuRow
                to="/profil"
                onClick={navigateAway}
                hint={needsName ? 'Välj ett visningsnamn' : 'Namn och statistik'}
              >
                Min profil
              </MenuRow>
              <MenuRow to="/nytt-losenord" onClick={navigateAway} hint="Välj ett nytt lösenord">
                Byt lösenord
              </MenuRow>
              <MenuRow to="/" onClick={navigateAway} hint="Skapa eller gå med i ett rum">
                Starta ett spel
              </MenuRow>
            </nav>

            <div className="border-t border-white/10 p-2">
              <NeonButton
                variant="ghost"
                className="w-full"
                role="menuitem"
                onClick={async () => {
                  await signOut()
                  close()
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
