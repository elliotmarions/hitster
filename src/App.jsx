import { Routes, Route, Navigate } from 'react-router-dom'
import AppShell from './components/AppShell.jsx'
import LandingPage from './pages/LandingPage.jsx'
import RoomPage from './pages/RoomPage.jsx'
import SpotifyCallback from './pages/SpotifyCallback.jsx'

export default function App() {
  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/rum/:code" element={<RoomPage />} />
        <Route path="/callback" element={<SpotifyCallback />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  )
}
