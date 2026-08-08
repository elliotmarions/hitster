import { Link } from 'react-router-dom'
import { useNavGuardRunner } from '../context/NavGuardContext.jsx'
import DiscoBall from './DiscoBall.jsx'
import AccountBadge from './AccountBadge.jsx'

export default function AppShell({ children }) {
  // Mitt i en match är logotypen inte en genväg hem utan en väg UT ur spelet.
  // Har vyn registrerat en spärr ställer den frågan i stället – samma ruta som
  // "Lämna". Utanför rummet finns ingen spärr och länken beter sig som förut.
  const runGuard = useNavGuardRunner()

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-20 border-b border-line/60 bg-midnight/70 backdrop-blur-md">
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
          <Link
            to="/"
            className="flex items-center gap-2.5"
            onClick={(e) => {
              if (runGuard()) e.preventDefault()
            }}
          >
            <DiscoBall size={30} />
            <span
              className="neon-text font-display text-sm uppercase tracking-[0.18em]"
              style={{ '--neon': '#ff4d9d' }}
            >
              Låtsnurran
            </span>
          </Link>
          <AccountBadge />
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6 sm:py-10">
        {children}
      </main>

    </div>
  )
}
