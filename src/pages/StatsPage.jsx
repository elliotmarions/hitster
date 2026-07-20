import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import { getMyStats } from '../lib/stats.js'
import DiscoBall from '../components/DiscoBall.jsx'

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

export default function StatsPage() {
  const { isConfigured, loading: authLoading, isGuest, accountEmail } = useAuth()
  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')

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

  const played = stats?.games_played ?? 0
  const won = stats?.games_won ?? 0
  const tied = stats?.games_tied ?? 0
  const winRate = played > 0 ? Math.round((won / played) * 100) : 0

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="label">Din statistik</p>
          <h1 className="font-display text-3xl text-cream">Så har det gått</h1>
        </div>
        <Link to="/" className="chip" style={{ '--neon': '#22e6e6' }}>
          ← Till start
        </Link>
      </div>

      {loading ? (
        <div className="flex flex-col items-center gap-3 py-16 text-muted">
          <DiscoBall size={64} className="anim-spin-slow" />
          <p>Hämtar statistik…</p>
        </div>
      ) : err ? (
        <p className="panel p-6 text-center text-magenta">{err}</p>
      ) : played === 0 ? (
        <div className="panel p-8 text-center">
          <DiscoBall size={72} className="anim-float mx-auto" />
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
        <>
          <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard label="Spelade" value={played} neon="#22e6e6" />
            <StatCard label="Vinster" value={won} neon="#b6ff3c" />
            <StatCard label="Oavgjorda" value={tied} neon="#ffc93c" />
            <StatCard label="Vinst­andel" value={`${winRate}%`} neon="#ff2e9a" />
          </section>

          <p className="text-center text-xs text-muted">
            {isGuest ? (
              <>
                Du spelar som gäst – statistiken sparas i den här webbläsaren.{' '}
                <Link to="/konto" className="text-cyan hover:underline">
                  Skapa ett konto
                </Link>{' '}
                för att behålla den mellan enheter.
              </>
            ) : (
              `Inloggad som ${accountEmail}. Statistiken följer ditt konto.`
            )}
          </p>
        </>
      )}
    </div>
  )
}
