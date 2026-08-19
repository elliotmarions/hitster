import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './index.css'
import App from './App.jsx'
import { AuthProvider } from './context/AuthContext.jsx'
import { VolumeProvider } from './context/VolumeContext.jsx'
import { syncServerTime } from './lib/serverTime.js'

// Mät klockavvikelsen redan vid start, så offseten är klar långt innan någon
// runda drar igång (mätningen är idempotent – senare anrop återanvänder den).
syncServerTime()

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <VolumeProvider>
          <App />
        </VolumeProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
)
