// Mobil-harness: renderar varje vy med påhittad data så de går att granska i
// olika skärmbredder utan riktig Supabase. Ingår aldrig i produktionsbygget.
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import '../src/index.css'
import AppShell from '../src/components/AppShell.jsx'
import { NavGuardProvider } from '../src/context/NavGuardContext.jsx'
import { AuthProvider } from '../src/context/AuthContext.jsx'
import { VolumeProvider } from '../src/context/VolumeContext.jsx'
import LobbyView from '../src/components/room/LobbyView.jsx'
import GameView from '../src/components/room/GameView.jsx'
import JoinGate from '../src/components/room/JoinGate.jsx'
import LandingPage from '../src/pages/LandingPage.jsx'
import AuthPage from '../src/pages/AuthPage.jsx'
import ProfilePage from '../src/pages/ProfilePage.jsx'
import PrivacyPage from '../src/pages/PrivacyPage.jsx'
import ResetPasswordPage from '../src/pages/ResetPasswordPage.jsx'
import { ROOM, scenario } from './fake-hooks.js'

const p = new URLSearchParams(window.location.search)
const lag = p.get('lag') === '1'

const players = [
  { id: 'p1', user_id: 'u-me', display_name: 'Elliot', is_host: true, team_id: lag ? 't1' : null },
  { id: 'p2', user_id: 'u-2', display_name: 'Sara Lindqvist-Bergström', is_host: false, team_id: lag ? 't1' : null },
  { id: 'p3', user_id: 'u-3', display_name: 'Johan', is_host: false, team_id: lag ? 't2' : null },
  { id: 'p4', user_id: 'u-4', display_name: 'Amanda', is_host: false, team_id: lag ? 't2' : null },
  { id: 'p5', user_id: 'u-5', display_name: 'Mohammed', is_host: false, team_id: lag ? 't2' : null },
]
const teams = [
  { id: 't1', room_id: 'r1', name: 'Discokulorna', color: '#22e6e6' },
  { id: 't2', room_id: 'r1', name: 'Dansbandsdemonerna', color: '#ff4d9d' },
]

const room = { ...ROOM, team_mode: lag }
const present = new Set(players.map((x) => x.user_id))

function Vy() {
  const v = scenario()
  if (v === 'lobby')
    return (
      <LobbyView
        room={{ ...room, status: 'lobby' }}
        players={players}
        teams={teams}
        me={players[0]}
        isHost
        currentUserId="u-me"
        presentUserIds={present}
      />
    )
  if (v === 'spel' || v === 'spel-facit')
    return <GameView room={room} players={players} teams={teams} me={players[0]} isHost />
  if (v === 'joingate') return <JoinGate code="DISCO7" onJoined={() => {}} />
  if (v === 'konto') return <AuthPage />
  if (v === 'profil') return <ProfilePage />
  if (v === 'integritet') return <PrivacyPage />
  if (v === 'nytt-losenord') return <ResetPasswordPage />
  return <LandingPage />
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <MemoryRouter initialEntries={[scenario() === 'lobby' || scenario().startsWith('spel') ? '/rum/DISCO7' : '/']}>
      <AuthProvider>
        <VolumeProvider>
          <NavGuardProvider>
            <AppShell>
              <Routes>
                <Route path="*" element={<Vy />} />
              </Routes>
            </AppShell>
          </NavGuardProvider>
        </VolumeProvider>
      </AuthProvider>
    </MemoryRouter>
  </StrictMode>,
)
