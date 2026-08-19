import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { useNavGuardRunner } from '../context/NavGuardContext.jsx'
import NeonButton from './ui/NeonButton.jsx'

/** Första tecknet i namnet, versalt. Array.from klarar å/ä/ö och emoji. */
function initialOf(label) {
  return (Array.from(label.trim())[0] || '?').toUpperCase()
}

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
  const menuRef = useRef(null)
  const triggerRef = useRef(null)
  // Mitt i en match är varje rad i menyn en väg UT ur spelet, precis som
  // logotypen. Samma spärr gäller därför här: rummet får ställa sin fråga
  // först. (Gamla "Profil"-länken gick förbi den och slängde ut spelaren.)
  const runGuard = useNavGuardRunner()

  // Klick utanför stänger menyn. Samma recept som VolumeControl använder – en
  // pointerdown-lyssnare och en ref runt hela härligheten. Tidigare låg här en
  // osynlig heltäckande knapp i stället, som dessutom la sig i tabbordningen.
  useEffect(() => {
    if (!open) return
    function onPointerDown(e) {
      if (rootRef.current && !rootRef.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [open])

  // Tangentbord i menyn: Escape stänger och lämnar tillbaka fokus, piltangenter
  // vandrar mellan raderna. Utan pilarna nådde man raderna bara med Tab, och
  // Tab tog en vidare ut ur menyn i stället för runt i den.
  useEffect(() => {
    if (!open) return
    function onKey(e) {
      if (e.key === 'Escape') {
        setOpen(false)
        triggerRef.current?.focus()
        return
      }
      const keys = ['ArrowDown', 'ArrowUp', 'Home', 'End']
      if (!keys.includes(e.key)) return
      const items = Array.from(menuRef.current?.querySelectorAll('[role="menuitem"]') ?? [])
      if (!items.length) return
      e.preventDefault()
      const at = items.indexOf(document.activeElement)
      const next =
        e.key === 'Home'
          ? 0
          : e.key === 'End'
            ? items.length - 1
            : e.key === 'ArrowDown'
              ? at < 0
                ? 0
                : (at + 1) % items.length
              : at < 0
                ? items.length - 1
                : (at - 1 + items.length) % items.length
      items[next].focus()
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
        ref={triggerRef}
        type="button"
        className="chip cursor-pointer !pl-1 transition hover:brightness-125"
        style={{ '--neon': '#b6ff3c' }}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span
          aria-hidden
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-lime/20 text-[0.7rem] text-lime"
        >
          {initialOf(badgeLabel)}
        </span>
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
        <div
          ref={menuRef}
          role="menu"
          aria-label="Kontomeny"
          className="panel absolute right-0 z-40 mt-2 w-72 overflow-hidden"
        >
          {/* Vem är inloggad – överst, där man tittar först. */}
          <div className="flex items-center gap-3 border-b border-white/10 px-4 py-3.5">
            <span
              aria-hidden
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-lime/15 font-display text-lg text-lime shadow-[0_0_18px_-6px_#b6ff3c]"
            >
              {initialOf(badgeLabel)}
            </span>
            <span className="min-w-0">
              <span className="block truncate font-display text-cream">{badgeLabel}</span>
              <span className="block truncate text-xs text-muted">{accountEmail}</span>
            </span>
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
      )}
    </div>
  )
}
