import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { createRoom, joinRoom } from '../lib/rooms.js'
import DiscoBall from '../components/DiscoBall.jsx'
import SetupNotice from '../components/SetupNotice.jsx'
import NeonButton from '../components/ui/NeonButton.jsx'
import TextField from '../components/ui/TextField.jsx'

const POINTS = [
  { c: '#22e6e6', t: 'Ingen inloggning', d: 'Korta musikklipp spelas synkat hos alla – direkt i webbläsaren, funkar på mobil.' },
  { c: '#ff2e9a', t: 'Delad discokula', d: 'Värden snurrar, alla ser samma kategori samtidigt.' },
  { c: '#b6ff3c', t: 'Solo eller i lag', d: 'Spela var för sig eller dela in gänget i lag – brickor uppdateras live.' },
]

export default function LandingPage() {
  const navigate = useNavigate()
  const { isConfigured, loading, preferredName, setPreferredName } = useAuth()

  const [name, setName] = useState(preferredName)
  const [roomName, setRoomName] = useState('')
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(null) // 'create' | 'join' | null
  const [err, setErr] = useState('')

  function requireName() {
    if (!name.trim()) {
      setErr('Skriv ditt visningsnamn först.')
      return false
    }
    return true
  }

  async function handleCreate(e) {
    e.preventDefault()
    setErr('')
    if (!requireName()) return
    setBusy('create')
    try {
      setPreferredName(name.trim())
      const room = await createRoom({ name: roomName, displayName: name })
      navigate(`/rum/${room.code}`)
    } catch (e2) {
      setErr(e2.message || 'Kunde inte skapa rummet.')
      setBusy(null)
    }
  }

  async function handleJoin(e) {
    e.preventDefault()
    setErr('')
    if (!requireName()) return
    if (!code.trim()) {
      setErr('Fyll i rumskoden.')
      return
    }
    setBusy('join')
    try {
      setPreferredName(name.trim())
      const room = await joinRoom({ code, displayName: name })
      navigate(`/rum/${room.code}`)
    } catch (e2) {
      setErr(/not found|hittades|finns/i.test(e2.message) ? 'Hittade inget rum med den koden.' : e2.message)
      setBusy(null)
    }
  }

  return (
    <div className="space-y-10">
      {/* Hero – neon-marquee */}
      <section className="pt-4 text-center">
        <DiscoBall size={104} className="anim-float mx-auto" />
        <h1 className="wordmark mt-2 text-[13vw] leading-none sm:text-6xl md:text-7xl">
          Låtsnurran
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-muted">
          Spela discospelet tillsammans på distans. En delad discokula, bingobrickor i
          realtid och synkade musikklipp – helt utan inloggning. Spela solo eller i lag.
        </p>
      </section>

      {isConfigured ? (
        <>
          {/* Namn (delas av båda korten) */}
          <section className="mx-auto max-w-md">
            <TextField
              label="Ditt visningsnamn"
              placeholder="t.ex. Discokungen"
              maxLength={24}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </section>

          {err && (
            <p className="mx-auto max-w-md text-center text-sm text-magenta">{err}</p>
          )}

          <section className="grid gap-5 md:grid-cols-2">
            {/* Skapa rum */}
            <form onSubmit={handleCreate} className="panel flex flex-col gap-4 p-6">
              <h2 className="neon-text text-2xl" style={{ '--neon': '#ff2e9a' }}>
                Skapa rum
              </h2>
              <p className="text-sm text-muted">
                Du blir värd och får en kod att dela med gänget.
              </p>
              <TextField
                label="Rumsnamn (valfritt)"
                placeholder="Fredagsdisco"
                maxLength={40}
                value={roomName}
                onChange={(e) => setRoomName(e.target.value)}
              />
              <NeonButton type="submit" disabled={loading || busy !== null}>
                {busy === 'create' ? 'Skapar…' : 'Skapa rum'}
              </NeonButton>
            </form>

            {/* Gå med */}
            <form onSubmit={handleJoin} className="panel flex flex-col gap-4 p-6">
              <h2 className="neon-text text-2xl" style={{ '--neon': '#22e6e6' }}>
                Gå med
              </h2>
              <p className="text-sm text-muted">Har du en rumskod? Hoppa in direkt.</p>
              <TextField
                label="Rumskod"
                placeholder="ABCD1"
                autoCapitalize="characters"
                className="uppercase tracking-[0.3em]"
                value={code}
                onChange={(e) => setCode(e.target.value)}
              />
              <NeonButton
                type="submit"
                variant="outline"
                neon="#22e6e6"
                disabled={loading || busy !== null}
              >
                {busy === 'join' ? 'Ansluter…' : 'Gå med i rum'}
              </NeonButton>
            </form>
          </section>

          {/* Så funkar det */}
          <section className="grid gap-4 sm:grid-cols-3">
            {POINTS.map((p) => (
              <div key={p.t} className="panel-inset p-4">
                <div className="h-1 w-10 rounded-full" style={{ background: p.c }} />
                <h3 className="mt-3 font-display text-lg" style={{ color: p.c }}>
                  {p.t}
                </h3>
                <p className="mt-1 text-sm text-muted">{p.d}</p>
              </div>
            ))}
          </section>
        </>
      ) : (
        <SetupNotice />
      )}
    </div>
  )
}
