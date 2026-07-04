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

  // Loggar ut från kontot men loggar genast in anonymt igen -> man kan spela vidare som gäst.
  const signOut = useCallback(async () => {
    if (!isSupabaseConfigured) return
    await supabase.auth.signOut()
    bootstrapped.current = false
    const { data } = await supabase.auth.signInAnonymously()
    setUser(data?.user ?? null)
  }, [])

  const value = {
    user,
    loading,
    isConfigured: isSupabaseConfigured,
    isGuest: user?.is_anonymous ?? true,
    accountEmail: user?.email ?? null,
    preferredName,
    setPreferredName,
    signInWithEmail,
    signOut,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth måste användas inuti <AuthProvider>')
  return ctx
}
