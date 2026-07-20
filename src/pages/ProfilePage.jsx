import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { getMyStats } from '../lib/stats.js'
import DiscoBall from '../components/DiscoBall.jsx'
import SetupNotice from '../components/SetupNotice.jsx'
import NeonButton from '../components/ui/NeonButton.jsx'
import TextField from '../components/ui/TextField.jsx'

function StatCard({ label, value, neon }) {
  return (
    <div className="panel-inset p-5 text-center">
      <p className="wordmark text-5xl" style={{ color: neon, textShadow: `0 0 18px ${neon}66` }}>
        {value}
      </p>
      <p className="label mt-2">{label}</p>
    </div>
  )
}

/**
 * Profilen: ett ställe för namn, konto och statistik.
 *
 * Namnbytet bodde tidigare i konto-menyn uppe till höger – nu är menyn bara en
 * genväg hit och all redigering sker på sidan.
 */
export default function ProfilePage() {
  const navigate = useNavigate()
  const {
    isConfigured,
    loading: authLoading,
    isGuest,
    accountEmail,
    accountName,
    preferredName,
    updateAccountName,
    signOut,
  } = useAuth()

  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')

  const [nameField, setNameField] = useState(() => accountName || preferredName || '')
  const [nameBusy, setNameBusy] = useState(false)
  const [nameErr, setNameErr] = useState('')
  const [nameSaved, setNameSaved] = useState(false)

  useEffect(() => {
    if (!isConfigured || authLoading) return
    let active = true
    setLoading(true)
    getMyStats()
      .then((s) => active && setStats(s))
      .catch((e) => active && setErr(e.message || 'Kunde inte hämta statistiken.'))
      .finally(() => active && setLoading(false))
    return () => {
      active = false
    }
  }, [isConfigured, authLoading])

  if (!isConfigured) return <SetupNotice />

  const played = stats?.games_played ?? 0
  const won = stats?.games_won ?? 0
  const tied = stats?.games_tied ?? 0
  const winRate = played > 0 ? Math.round((won / played) * 100) : 0

  async function saveName(e) {
    e.preventDefault()
    setNameErr('')
    setNameSaved(false)
    setNameBusy(true)
    try {
      await updateAccountName(nameField.trim())
      setNameSaved(true)
    } catch (e2) {
      setNameErr(e2.message || 'Kunde inte spara namnet.')
    } finally {
      setNameBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-8">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="label">Din profil</p>
          <h1 className="font-display text-3xl text-cream">
            {accountName || preferredName || 'Profil'}
          </h1>
        </div>
        <Link to="/" className="chip" style={{ '--neon': '#22e6e6' }}>
          ← Till start
        </Link>
      </div>

      {/* --- Namn ------------------------------------------------------- */}
      <section className="panel space-y-4 p-6">
        <h2 className="neon-text font-display text-xl" style={{ '--neon': '#ff2e9a' }}>
          Ditt namn
        </h2>
        {isGuest ? (
          <p className="text-sm text-muted">
            Du spelar som gäst. Namnet du väljer när du skapar eller går med i ett rum
            gäller bara det spelet.{' '}
            <Link to="/konto" className="text-cyan hover:underline">
              Skapa ett konto
            </Link>{' '}
            för att spara ett namn som följer med.
          </p>
        ) : (
          <form onSubmit={saveName} className="space-y-3">
            <TextField
              label="Visningsnamn"
              placeholder="t.ex. Discokungen"
              maxLength={24}
              value={nameField}
              onChange={(e) => {
                setNameField(e.target.value)
                setNameSaved(false)
              }}
              hint="Så här syns du för andra i rummet."
            />
            {nameErr && <p className="text-sm text-magenta">{nameErr}</p>}
            {nameSaved && <p className="text-sm text-lime">Sparat ✓</p>}
            <NeonButton type="submit" disabled={nameBusy || !nameField.trim()}>
              {nameBusy ? 'Sparar…' : 'Spara namn'}
            </NeonButton>
          </form>
        )}
      </section>

      {/* --- Statistik --------------------------------------------------- */}
      <section className="space-y-4">
        <h2 className="neon-text font-display text-xl" style={{ '--neon': '#22e6e6' }}>
          Så har det gått
        </h2>

        {loading ? (
          <div className="flex flex-col items-center gap-3 py-12 text-muted">
            <DiscoBall size={56} className="anim-spin-slow" />
            <p>Hämtar statistik…</p>
          </div>
        ) : err ? (
          <p className="panel p-6 text-center text-magenta">{err}</p>
        ) : played === 0 ? (
          <div className="panel p-8 text-center">
            <DiscoBall size={64} className="anim-float mx-auto" />
            <p className="mt-4 font-display text-xl text-cream">Inga matcher än</p>
            <p className="mt-1 text-sm text-muted">
              Spela en match så dyker dina siffror upp här.
            </p>
            <Link
              to="/"
              className="mt-5 inline-block rounded-lg px-5 py-2.5 font-display"
              style={{ background: '#ff2e9a', color: '#140c22' }}
            >
              Starta ett spel
            </Link>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard label="Spelade" value={played} neon="#22e6e6" />
            <StatCard label="Vinster" value={won} neon="#b6ff3c" />
            <StatCard label="Oavgjorda" value={tied} neon="#ffc93c" />
            <StatCard label="Vinst­andel" value={`${winRate}%`} neon="#ff2e9a" />
          </div>
        )}
      </section>

      {/* --- Konto ------------------------------------------------------- */}
      <section className="panel space-y-4 p-6">
        <h2 className="neon-text font-display text-xl" style={{ '--neon': '#b6ff3c' }}>
          Konto
        </h2>
        {isGuest ? (
          <>
            <p className="text-sm text-muted">
              Du spelar som gäst – statistiken sparas bara i den här webbläsaren.
              Skapar du ett konto följer allt du redan spelat med.
            </p>
            <NeonButton onClick={() => navigate('/konto')}>Skapa konto eller logga in</NeonButton>
          </>
        ) : (
          <>
            <p className="text-sm text-muted">
              Inloggad som <span className="text-cream">{accountEmail}</span>. Statistiken
              följer ditt konto mellan enheter.
            </p>
            <NeonButton
              variant="ghost"
              onClick={async () => {
                await signOut()
                navigate('/')
              }}
            >
              Logga ut
            </NeonButton>
          </>
        )}
      </section>
    </div>
  )
}
