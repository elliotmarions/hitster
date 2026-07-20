import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth, MIN_PASSWORD_LENGTH } from '../context/AuthContext.jsx'
import DiscoBall from '../components/DiscoBall.jsx'
import SetupNotice from '../components/SetupNotice.jsx'
import NeonButton from '../components/ui/NeonButton.jsx'
import TextField from '../components/ui/TextField.jsx'

/**
 * Kontosidan: logga in eller skapa konto med e-post + lösenord.
 * Magisk länk finns kvar som alternativ, och glömt-lösenord som egen vy.
 *
 * Gäst är fortfarande en fullt giltig väg – man kan alltid gå tillbaka och
 * spela utan konto.
 */
export default function AuthPage() {
  const navigate = useNavigate()
  const {
    isConfigured,
    loading,
    isGuest,
    accountEmail,
    signInWithPassword,
    signUpWithPassword,
    signInWithEmail,
    requestPasswordReset,
  } = useAuth()

  const [mode, setMode] = useState('signin') // 'signin' | 'signup' | 'forgot'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [password2, setPassword2] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [done, setDone] = useState(null) // null | 'confirm' | 'magic' | 'reset'

  if (!isConfigured) return <SetupNotice />

  // Redan inloggad – ingen anledning att visa formulären.
  if (!loading && !isGuest) {
    return (
      <div className="mx-auto max-w-md space-y-5 text-center">
        <DiscoBall size={72} className="anim-float mx-auto" />
        <h1 className="neon-text font-display text-3xl" style={{ '--neon': '#b6ff3c' }}>
          Du är inloggad
        </h1>
        <p className="text-muted">Inloggad som {accountEmail}.</p>
        <div className="flex flex-col gap-3">
          <NeonButton onClick={() => navigate('/')}>Till start</NeonButton>
          <Link to="/statistik" className="text-sm text-cyan hover:underline">
            Se min statistik
          </Link>
        </div>
      </div>
    )
  }

  function switchMode(next) {
    setMode(next)
    setErr('')
    setDone(null)
    setPassword('')
    setPassword2('')
  }

  async function handleSubmit(e) {
    e.preventDefault()
    setErr('')

    if (mode === 'signup') {
      if (password.length < MIN_PASSWORD_LENGTH) {
        setErr(`Lösenordet måste vara minst ${MIN_PASSWORD_LENGTH} tecken.`)
        return
      }
      if (password !== password2) {
        setErr('Lösenorden matchar inte.')
        return
      }
    }

    setBusy(true)
    try {
      if (mode === 'signin') {
        await signInWithPassword(email.trim(), password)
        navigate('/')
      } else if (mode === 'signup') {
        const res = await signUpWithPassword(email.trim(), password)
        if (res.needsConfirmation) setDone('confirm')
        else navigate('/')
      } else {
        await requestPasswordReset(email.trim())
        setDone('reset')
      }
    } catch (e2) {
      setErr(e2.message || 'Något gick fel. Försök igen.')
    } finally {
      setBusy(false)
    }
  }

  async function handleMagicLink() {
    setErr('')
    if (!email.trim()) {
      setErr('Fyll i din e-post först.')
      return
    }
    setBusy(true)
    try {
      await signInWithEmail(email.trim())
      setDone('magic')
    } catch (e2) {
      setErr(e2.message || 'Kunde inte skicka länken.')
    } finally {
      setBusy(false)
    }
  }

  // --- Kvitto efter att ett mejl skickats -----------------------------------
  if (done) {
    const text = {
      confirm:
        'Klicka på länken i mejlet för att bekräfta din e-post. Sen är kontot ditt – med all statistik du redan samlat på dig.',
      magic: 'Klicka på länken i mejlet så loggar vi in dig.',
      reset:
        'Har du ett konto med den adressen är en återställningslänk på väg. Klicka i mejlet för att välja ett nytt lösenord.',
    }[done]

    return (
      <div className="mx-auto max-w-md space-y-5 text-center">
        <DiscoBall size={72} className="anim-float mx-auto" />
        <h1 className="neon-text font-display text-3xl" style={{ '--neon': '#b6ff3c' }}>
          Kolla din mejl!
        </h1>
        <p className="text-muted">{text}</p>
        <p className="text-xs text-muted">Skickat till {email}</p>
        <Link to="/" className="inline-block text-sm text-cyan hover:underline">
          ← Tillbaka till start
        </Link>
      </div>
    )
  }

  const isForgot = mode === 'forgot'

  return (
    <div className="mx-auto max-w-md space-y-6">
      <header className="text-center">
        <DiscoBall size={72} className="anim-float mx-auto" />
        <h1 className="wordmark mt-2 text-4xl">
          {isForgot ? 'Glömt lösenord' : 'Ditt konto'}
        </h1>
        <p className="mt-3 text-sm text-muted">
          {isForgot
            ? 'Fyll i din e-post så skickar vi en länk för att välja ett nytt lösenord.'
            : 'Med ett konto följer din statistik med mellan enheter. Du kan fortfarande spela som gäst utan att registrera dig.'}
        </p>
      </header>

      {!isForgot && (
        <div className="flex gap-2" role="tablist">
          {[
            ['signin', 'Logga in'],
            ['signup', 'Skapa konto'],
          ].map(([key, label]) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={mode === key}
              onClick={() => switchMode(key)}
              className={`flex-1 cursor-pointer rounded-lg px-4 py-2.5 font-display text-sm uppercase tracking-[0.12em] transition ${
                mode === key
                  ? 'bg-white/10 text-cream shadow-[0_0_14px_rgba(34,230,230,0.25)]'
                  : 'text-muted hover:bg-white/5'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      )}

      <form onSubmit={handleSubmit} className="panel space-y-4 p-6">
        <TextField
          type="email"
          required
          autoComplete="email"
          label="E-post"
          placeholder="din@mejl.se"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />

        {!isForgot && (
          <>
            <TextField
              type={showPassword ? 'text' : 'password'}
              required
              autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
              label="Lösenord"
              placeholder={mode === 'signup' ? `Minst ${MIN_PASSWORD_LENGTH} tecken` : '••••••••'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />

            {mode === 'signup' && (
              <TextField
                type={showPassword ? 'text' : 'password'}
                required
                autoComplete="new-password"
                label="Upprepa lösenord"
                placeholder="Samma en gång till"
                value={password2}
                onChange={(e) => setPassword2(e.target.value)}
              />
            )}

            <label className="flex cursor-pointer items-center gap-2 text-xs text-muted">
              <input
                type="checkbox"
                checked={showPassword}
                onChange={(e) => setShowPassword(e.target.checked)}
              />
              Visa lösenord
            </label>
          </>
        )}

        {err && <p className="text-sm text-magenta">{err}</p>}

        {mode === 'signup' && (
          <p className="text-xs text-muted">
            Spelar du som gäst just nu behåller du ditt user-id – matcher och statistik
            följer med till kontot.
          </p>
        )}
        {mode === 'signin' && (
          <p className="text-xs text-muted">
            Loggar du in på ett befintligt konto lämnas gäststatistiken i den här
            webbläsaren kvar på gästkontot.
          </p>
        )}

        <NeonButton type="submit" disabled={busy} className="w-full">
          {busy
            ? 'Vänta…'
            : isForgot
              ? 'Skicka återställningslänk'
              : mode === 'signin'
                ? 'Logga in'
                : 'Skapa konto'}
        </NeonButton>

        {mode === 'signin' && (
          <>
            <button
              type="button"
              onClick={() => switchMode('forgot')}
              className="w-full cursor-pointer text-center text-xs text-muted hover:text-cream hover:underline"
            >
              Glömt lösenordet?
            </button>

            <div className="flex items-center gap-3 pt-1">
              <span className="h-px flex-1 bg-white/10" />
              <span className="label">eller</span>
              <span className="h-px flex-1 bg-white/10" />
            </div>

            <NeonButton
              type="button"
              variant="outline"
              neon="#22e6e6"
              disabled={busy}
              className="w-full"
              onClick={handleMagicLink}
            >
              Skicka inloggningslänk i stället
            </NeonButton>
          </>
        )}

        {isForgot && (
          <button
            type="button"
            onClick={() => switchMode('signin')}
            className="w-full cursor-pointer text-center text-xs text-muted hover:text-cream hover:underline"
          >
            ← Tillbaka till inloggning
          </button>
        )}
      </form>

      <p className="text-center text-sm text-muted">
        <Link to="/" className="text-cyan hover:underline">
          Fortsätt som gäst
        </Link>{' '}
        – du kan skapa konto när som helst.
      </p>
    </div>
  )
}
