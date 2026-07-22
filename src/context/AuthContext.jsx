import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react'
import { supabase, isSupabaseConfigured } from '../lib/supabase'

const AuthContext = createContext(null)

const NAME_KEY = 'hbo:display-name'

/** Kortaste lösenord vi accepterar i formulären. Supabase har sitt eget krav
 *  (minst 6 som standard) – vi är medvetet lite strängare. */
export const MIN_PASSWORD_LENGTH = 8

/**
 * Supabase svarar på engelska. Vi översätter de fel användaren realistiskt
 * kan råka ut för; okända fel går fram som de är hellre än att döljas.
 */
function translateAuthError(error) {
  const msg = error?.message || ''
  if (/invalid login credentials/i.test(msg))
    return new Error('Fel e-post eller lösenord.')
  if (/email not confirmed/i.test(msg))
    return new Error('Du behöver bekräfta din e-post först – kolla inkorgen.')
  if (/already registered|already been registered|user already/i.test(msg))
    return new Error('Det finns redan ett konto med den e-posten. Logga in i stället.')
  if (/password should be at least (\d+)/i.test(msg))
    return new Error(
      `Lösenordet måste vara minst ${msg.match(/at least (\d+)/i)[1]} tecken.`,
    )
  if (/weak password|password is too weak/i.test(msg))
    return new Error('Lösenordet är för svagt – välj något längre och mindre gissningsbart.')
  if (/unable to validate email|invalid format/i.test(msg))
    return new Error('E-postadressen ser inte giltig ut.')
  // Anonym inloggning har en egen spärr: 30 per timme och IP-ADRESS, och den
  // går inte att höja. Sitter ett helt gäng på samma wifi (eller bakom samma
  // mobiloperatör) delar de på den potten, så felet är värt en egen förklaring
  // – annars låter det som att användaren själv gjort något fel.
  if (error?.code === 'over_request_rate_limit')
    return new Error(
      'Många har öppnat spelet från samma nätverk den senaste timmen. ' +
        'Vänta en liten stund och försök igen.',
    )
  if (/rate limit|too many requests|over_email_send_rate/i.test(msg))
    return new Error('För många försök. Vänta en stund och prova igen.')
  if (/same as the old password|should be different/i.test(msg))
    return new Error('Det nya lösenordet måste skilja sig från det gamla.')
  return error instanceof Error ? error : new Error(msg || 'Något gick fel.')
}

/**
 * Hela app-trädet får tillgång till inloggningsläget.
 *
 * Modell (enligt önskemål): man kan spela DIREKT som gäst utan registrering.
 * Vill man följa statistik kan man valfritt logga in med e-post. Vi använder
 * Supabase anonym auth som bas så varje besökare får ett stabilt user-id
 * (sparas i webbläsaren). Loggar man in länkas kontot till SAMMA id, så man
 * behåller sin statistik när man går från gäst -> konto.
 */
export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const [preferredName, setPreferredNameState] = useState(
    () => localStorage.getItem(NAME_KEY) || '',
  )
  // Skyddar mot dubbel anonym inloggning i React StrictMode (dev kör effekter två gånger).
  const bootstrapped = useRef(false)

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setLoading(false)
      return
    }

    let active = true

    async function bootstrap() {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!active) return

      if (session?.user) {
        setUser(session.user)
        setLoading(false)
        return
      }
      if (bootstrapped.current) return
      // Kommer vi tillbaka från en e-postlänk (återställning, bekräftelse) ligger
      // tokens i URL-hashen och Supabase håller på att växla in dem. Att logga in
      // anonymt här skulle skriva över den sessionen – då kunde man aldrig sätta
      // ett nytt lösenord. Låt bootstrapen vila; onAuthStateChange tar över.
      if (/access_token=|type=recovery|error_code=/.test(window.location.hash)) {
        setLoading(false)
        return
      }
      bootstrapped.current = true
      // Ingen session -> logga in anonymt så man kan skapa/gå med i rum direkt.
      const { data, error } = await supabase.auth.signInAnonymously()
      if (!active) return
      if (error) console.error('Anonym inloggning misslyckades:', error.message)
      setUser(data?.user ?? null)
      setLoading(false)
    }
    bootstrap()

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])

  const setPreferredName = useCallback((name) => {
    setPreferredNameState(name)
    if (name) localStorage.setItem(NAME_KEY, name)
  }, [])

  /**
   * Skickar en magisk inloggningslänk till angiven e-post.
   * - Är man gäst uppgraderas kontot på plats (samma id, statistiken följer med).
   * - Finns e-posten redan som konto loggar vi in i det befintliga istället.
   */
  const signInWithEmail = useCallback(async (email) => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const emailRedirectTo = window.location.origin
    const {
      data: { user: current },
    } = await supabase.auth.getUser()

    if (current?.is_anonymous) {
      const { error } = await supabase.auth.updateUser(
        { email },
        { emailRedirectTo },
      )
      if (!error) return { mode: 'upgrade' }
      // Om e-posten redan tillhör ett konto: logga in där i stället.
      if (/regist|already|exist|taken/i.test(error.message)) {
        const { error: e2 } = await supabase.auth.signInWithOtp({
          email,
          options: { emailRedirectTo, shouldCreateUser: false },
        })
        if (e2) throw e2
        return { mode: 'existing' }
      }
      throw error
    }

    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo, shouldCreateUser: false },
    })
    if (error) throw error
    return { mode: 'existing' }
  }, [])

  /**
   * Skapar ett konto med e-post + lösenord.
   *
   * Är man gäst uppgraderas det anonyma kontot PÅ PLATS (samma user-id), så
   * rum, brickor och statistik följer med – allt i databasen nycklas på
   * auth.uid(). Vi skapar alltså aldrig ett nytt id för en gäst.
   *
   * Returnerar { needsConfirmation } – är den true måste användaren klicka i
   * mejlet innan kontot går att logga in på från en annan enhet.
   */
  const signUpWithPassword = useCallback(async (email, password) => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const emailRedirectTo = window.location.origin
    const {
      data: { user: current },
    } = await supabase.auth.getUser()

    if (current?.is_anonymous) {
      const { data, error } = await supabase.auth.updateUser(
        { email, password },
        { emailRedirectTo },
      )
      if (error) throw translateAuthError(error)
      if (data?.user) setUser(data.user)
      return { needsConfirmation: !data?.user?.email_confirmed_at, upgraded: true }
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo },
    })
    if (error) throw translateAuthError(error)
    // Utan session tillbaka väntar Supabase på att e-posten bekräftas.
    return { needsConfirmation: !data?.session, upgraded: false }
  }, [])

  /**
   * Loggar in på ett befintligt konto. OBS: det byter user-id från gästens,
   * så eventuell gäststatistik i den här webbläsaren lämnas kvar på gäst-id:t.
   */
  const signInWithPassword = useCallback(async (email, password) => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw translateAuthError(error)
  }, [])

  /** Skickar en återställningslänk som landar på /nytt-losenord. */
  const requestPasswordReset = useCallback(async (email) => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/nytt-losenord`,
    })
    if (error) throw translateAuthError(error)
  }, [])

  /** Sätter ett nytt lösenord på den session återställningslänken gav oss. */
  const updatePassword = useCallback(async (password) => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const { data, error } = await supabase.auth.updateUser({ password })
    if (error) throw translateAuthError(error)
    if (data?.user) setUser(data.user)
  }, [])

  /**
   * Sparar ett visningsnamn på kontot (Supabase user_metadata.display_name).
   * Att uppdatera metadata kräver INGEN e-postbekräftelse – det gäller direkt.
   * Håller även det lokala "preferredName" i synk så landningssidan matchar.
   */
  const updateAccountName = useCallback(
    async (name) => {
      const clean = (name || '').trim()
      if (!clean) throw new Error('Skriv ett namn.')
      const { data, error } = await supabase.auth.updateUser({
        data: { display_name: clean },
      })
      if (error) throw error
      if (data?.user) setUser(data.user)
      setPreferredNameState(clean)
      if (clean) localStorage.setItem(NAME_KEY, clean)
    },
    [],
  )

  /**
   * Ser till att det finns en session INNAN vi gör något som kräver en.
   *
   * Bootstrapen ovan loggar in anonymt vid sidladdning, men den kan ha
   * misslyckats (se spärren i translateAuthError). Då står vi utan session,
   * och RPC:erna svarar "permission denied for function create_room" – en
   * teknisk engelsk sträng som inte hjälper någon. Att försöka igen här är
   * dessutom ofta nog: spärrens fönster rullar, så en plats kan ha frigjorts
   * sedan sidan laddades.
   */
  const ensureSession = useCallback(async () => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (session?.user) return session.user

    const { data, error } = await supabase.auth.signInAnonymously()
    if (error) throw translateAuthError(error)
    bootstrapped.current = true
    setUser(data.user)
    return data.user
  }, [])

  // Loggar ut från kontot men loggar genast in anonymt igen -> man kan spela vidare som gäst.
  const signOut = useCallback(async () => {
    if (!isSupabaseConfigured) return
    await supabase.auth.signOut()
    bootstrapped.current = false
    // Misslyckas gästinloggningen (spärren) står vi utan användare – det är
    // ensureSession som får försöka igen när man faktiskt gör något.
    const { data, error } = await supabase.auth.signInAnonymously()
    if (error) console.error('Anonym inloggning misslyckades:', error.message)
    setUser(data?.user ?? null)
  }, [])

  const value = {
    user,
    loading,
    isConfigured: isSupabaseConfigured,
    isGuest: user?.is_anonymous ?? true,
    accountEmail: user?.email ?? null,
    accountName: user?.user_metadata?.display_name ?? '',
    preferredName,
    setPreferredName,
    signInWithEmail,
    signUpWithPassword,
    signInWithPassword,
    requestPasswordReset,
    updatePassword,
    updateAccountName,
    ensureSession,
    signOut,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth måste användas inuti <AuthProvider>')
  return ctx
}
