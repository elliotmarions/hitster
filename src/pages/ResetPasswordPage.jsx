import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth, MIN_PASSWORD_LENGTH } from '../context/AuthContext.jsx'
import { supabase } from '../lib/supabase.js'
import DiscoBall from '../components/DiscoBall.jsx'
import NeonButton from '../components/ui/NeonButton.jsx'
import TextField from '../components/ui/TextField.jsx'

/**
 * Landningssidan för återställningslänken i mejlet.
 *
 * Supabase växlar in tokens från URL-hashen till en tillfällig session
 * (detectSessionInUrl). Först när den sessionen finns kan vi sätta ett nytt
 * lösenord – därför väntar vi in PASSWORD_RECOVERY / en giltig session innan
 * formuläret visas.
 */
export default function ResetPasswordPage() {
  const navigate = useNavigate()
  const { updatePassword } = useAuth()

  const [ready, setReady] = useState(false)
  const [linkError, setLinkError] = useState('')
  const [password, setPassword] = useState('')
  const [password2, setPassword2] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    if (!supabase) return
    let active = true

    // Supabase lägger felkoder från utgångna länkar i hashen.
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
    if (hash.get('error_description') || hash.get('error_code')) {
      setLinkError(
        'Länken är ogiltig eller har gått ut. Begär en ny återställningslänk.',
      )
      return
    }

    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!active) return
      if (session) setReady(true)
      else
        setLinkError(
          'Vi hittade ingen giltig återställningslänk. Öppna länken från mejlet igen.',
        )
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY' || event === 'SIGNED_IN') {
        setLinkError('')
        setReady(true)
      }
    })

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])

  async function handleSubmit(e) {
    e.preventDefault()
    setErr('')
    if (password.length < MIN_PASSWORD_LENGTH) {
      setErr(`Lösenordet måste vara minst ${MIN_PASSWORD_LENGTH} tecken.`)
      return
    }
    if (password !== password2) {
      setErr('Lösenorden matchar inte.')
      return
    }
    setBusy(true)
    try {
      await updatePassword(password)
      setSaved(true)
      // Rensa bort tokens ur adressfältet innan vi går vidare.
      window.history.replaceState(null, '', '/nytt-losenord')
      setTimeout(() => navigate('/'), 2000)
    } catch (e2) {
      setErr(e2.message || 'Kunde inte spara lösenordet.')
    } finally {
      setBusy(false)
    }
  }

  if (saved) {
    return (
      <div className="mx-auto max-w-md space-y-4 text-center">
        <DiscoBall size={72} className="anim-float mx-auto" />
        <h1 className="neon-text font-display text-3xl" style={{ '--neon': '#b6ff3c' }}>
          Lösenordet är bytt
        </h1>
        <p className="text-muted">Du är inloggad. Skickar dig till start…</p>
      </div>
    )
  }

  if (linkError) {
    return (
      <div className="mx-auto max-w-md space-y-4 text-center">
        <DiscoBall size={72} className="mx-auto" />
        <h1 className="font-display text-2xl text-cream">Länken funkar inte</h1>
        <p className="text-muted">{linkError}</p>
        <Link to="/konto" className="inline-block text-sm text-cyan hover:underline">
          Begär en ny länk
        </Link>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-md space-y-6">
      <header className="text-center">
        <DiscoBall size={72} className="anim-float mx-auto" />
        <h1 className="wordmark mt-2 text-4xl">Nytt lösenord</h1>
        <p className="mt-3 text-sm text-muted">Välj ett nytt lösenord till ditt konto.</p>
      </header>

      {!ready ? (
        <p className="text-center text-muted">Kontrollerar länken…</p>
      ) : (
        <form onSubmit={handleSubmit} className="panel space-y-4 p-6">
          <TextField
            type={showPassword ? 'text' : 'password'}
            required
            autoComplete="new-password"
            label="Nytt lösenord"
            placeholder={`Minst ${MIN_PASSWORD_LENGTH} tecken`}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <TextField
            type={showPassword ? 'text' : 'password'}
            required
            autoComplete="new-password"
            label="Upprepa lösenord"
            placeholder="Samma en gång till"
            value={password2}
            onChange={(e) => setPassword2(e.target.value)}
          />
          <label className="flex cursor-pointer items-center gap-2 text-xs text-muted">
            <input
              type="checkbox"
              checked={showPassword}
              onChange={(e) => setShowPassword(e.target.checked)}
            />
            Visa lösenord
          </label>

          {err && <p className="text-sm text-magenta">{err}</p>}

          <NeonButton type="submit" disabled={busy} className="w-full">
            {busy ? 'Sparar…' : 'Spara nytt lösenord'}
          </NeonButton>
        </form>
      )}
    </div>
  )
}
