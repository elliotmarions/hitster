import { lazy, Suspense } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { NavGuardProvider } from './context/NavGuardContext.jsx'
import AppShell from './components/AppShell.jsx'
import DiscoBall from './components/DiscoBall.jsx'
import LandingPage from './pages/LandingPage.jsx'

// Startsidan laddas direkt – den är det första man ser och ska inte vänta på
// ett extra nätverksanrop. Resten hämtas när de behövs: rumsvyn drar med sig
// spelplanen, ljudsynken och lagchatten. Allt
// låg förut i EN bundle på ~540 kB, som alltså laddades ned i sin helhet av
// någon som bara skulle skriva in ett namn.
const RoomPage = lazy(() => import('./pages/RoomPage.jsx'))
const PrivacyPage = lazy(() => import('./pages/PrivacyPage.jsx'))

function Laddar() {
  return (
    <div className="flex flex-col items-center gap-4 py-20 text-muted">
      <DiscoBall size={72} className="anim-spin-slow" />
      <p>Laddar…</p>
    </div>
  )
}

export default function App() {
  return (
    <NavGuardProvider>
      <AppShell>
        <Suspense fallback={<Laddar />}>
          <Routes>
            <Route path="/" element={<LandingPage />} />
            <Route path="/rum/:code" element={<RoomPage />} />
            {/* Inloggning, profil och statistik är borttagna – Låtsnurran är ett
                sällskapsspel för stunden. Gamla länkar dit (/konto, /profil,
                /statistik, /nytt-losenord) faller till startsidan nedan. */}
            <Route path="/integritet" element={<PrivacyPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </AppShell>
    </NavGuardProvider>
  )
}
