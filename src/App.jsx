import { Routes, Route, Navigate } from 'react-router-dom'
import AppShell from './components/AppShell.jsx'
import LandingPage from './pages/LandingPage.jsx'
import RoomPage from './pages/RoomPage.jsx'
import ProfilePage from './pages/ProfilePage.jsx'
import AuthPage from './pages/AuthPage.jsx'
import ResetPasswordPage from './pages/ResetPasswordPage.jsx'

export default function App() {
  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/rum/:code" element={<RoomPage />} />
        <Route path="/profil" element={<ProfilePage />} />
        {/* Statistiken bor numera på profilen – gamla länkar ska inte dö. */}
        <Route path="/statistik" element={<Navigate to="/profil" replace />} />
        <Route path="/konto" element={<AuthPage />} />
        <Route path="/nytt-losenord" element={<ResetPasswordPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  )
}
