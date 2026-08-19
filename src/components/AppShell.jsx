import { Link, useLocation } from 'react-router-dom'
import { useNavGuardRunner } from '../context/NavGuardContext.jsx'
import { useVolume } from '../context/VolumeContext.jsx'
import DiscoBall from './DiscoBall.jsx'
import AccountBadge from './AccountBadge.jsx'
import VolumeControl from './VolumeControl.jsx'

export default function AppShell({ children }) {
  // Mitt i en match är logotypen inte en genväg hem utan en väg UT ur spelet.
  // Har vyn registrerat en spärr ställer den frågan i stället – samma ruta som
  // "Lämna". Utanför rummet finns ingen spärr och länken beter sig som förut.
  const runGuard = useNavGuardRunner()

  // Volymen hörde tidigare bara hemma i spelvyn, så den gick inte att ändra i
  // lobbyn eller på startsidan. Nu sitter reglaget i headern – utom i rummet,
  // där scenen har sitt eget i hörnet vid discokulan. Två kontroller för samma
  // volym hade bara sett trasigt ut, även om de nu läser samma värde.
  const { volume, setVolume } = useVolume()
  const inRoom = useLocation().pathname.startsWith('/rum/')

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
          <div className="flex items-center gap-2">
            {!inRoom && <VolumeControl volume={volume} setVolume={setVolume} />}
            <AccountBadge />
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6 sm:py-10">
        {children}
      </main>

      {/* Sidfot: den plats folk letar på när de vill veta vad en sajt sparar.
          Länken kör samma spärr som logotypen – mitt i en match är också den
          här en väg ut ur spelet. */}
      <footer className="mx-auto w-full max-w-6xl px-4 pb-6 pt-2 text-center sm:px-6">
        <Link
          to="/integritet"
          onClick={(e) => {
            if (runGuard()) e.preventDefault()
          }}
          className="text-xs text-muted transition hover:text-cream hover:underline"
        >
          Integritet och villkor
        </Link>
      </footer>
    </div>
  )
}
