import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react'
import { supabase, isSupabaseConfigured } from '../lib/supabase'
import { translateDbError } from '../lib/errors'

const AuthContext = createContext(null)

const NAME_KEY = 'hbo:display-name'

/**
 * Supabase svarar på engelska. Det enda fel en spelare realistiskt råkar ut
 * för här är spärren på anonyma inloggningar: 30 per timme och IP-ADRESS, och
 * den går inte att höja. Sitter ett helt gäng på samma wifi (eller bakom samma
 * mobiloperatör) delar de på den potten, så felet är värt en egen förklaring –
 * annars låter det som att användaren själv gjort något fel.
 */
function translateAuthError(error) {
  const msg = error?.message || ''
  if (error?.code === 'over_request_rate_limit' || /rate limit|too many requests/i.test(msg))
    return new Error(
      'Många har öppnat spelet från samma nätverk den senaste timmen. ' +
        'Vänta en liten stund och försök igen.',
    )
  return error instanceof Error ? error : new Error(msg || 'Något gick fel.')
}

/**
 * Sessionen bakom spelet.
 *
 * Låtsnurran är ett sällskapsspel för stunden: det finns ingen inloggning,
 * inget konto och ingen statistik att följa. Varje besökare får ändå ett
 * stabilt anonymt user-id från Supabase (sparas i webbläsaren) – databasens
 * behörigheter (RLS) bygger på auth.uid(), så rum, brickor och svar behöver
 * veta vem som är vem.
 *
 * (Inloggning med e-post fanns tidigare. Den som redan är inloggad behåller
 * sin session – den fungerar precis som en gästs.)
 *
 * NÄR skapas gästsessionen? Först när besökaren gör något som kräver den –
 * skapar rum eller går med i ett – via ensureSession() längre ned. Supabase
 * strypar anonyma inloggningar till 30 per timme och IP-adress, och mätning
 * mot databasen visade att 68 av 97 gäster aldrig gick med i ett enda rum.
 * Följden är att `user` är null tills besökaren agerar; RLS ger då tomt svar
 * i stället för fel, så useRoom landar i JoinGate.
 */
export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const [preferredName, setPreferredNameState] = useState(
    () => localStorage.getItem(NAME_KEY) || '',
  )
  // Två samtidiga ensureSession() ska dela på EN inloggning – annars bränner
  // samma besökare två platser i timpotten.
  const signInFlight = useRef(null)

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setLoading(false)
      return
    }

    let active = true

    // Plocka bara upp en session som redan finns i webbläsaren. Ingen
    // gästinloggning här; den sker i ensureSession när den faktiskt behövs.
    async function bootstrap() {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!active) return
      setUser(session?.user ?? null)
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
   * Raderar allt som hör till den här webbläsarens id – på riktigt, inte dolt.
   *
   * Radering sker i RPC:n delete_my_account (migration 0085): klienten har
   * ingen åtkomst till auth.users. Där tas raden bort och kaskaderna städar
   * statistik, svar, brickor, lagchatt och rummen man varit VÄRD för.
   *
   * Efteråt pekar sessionens token på en användare som inte finns – därför
   * loggas den ut lokalt direkt. Nästa spel får ett nytt id.
   */
  const deleteMyData = useCallback(async () => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (!session?.user) return false // inget sparat att radera
    const { error } = await supabase.rpc('delete_my_account')
    if (error) throw translateDbError(error)
    await supabase.auth.signOut()
    setUser(null)
    return true
  }, [])

  /**
   * Ser till att det finns en session INNAN vi gör något som kräver en – och
   * är enda stället där en gästsession skapas.
   *
   * Finns redan en session är det en ren uppslagning utan nätverksanrop.
   * Annars loggas besökaren in anonymt här, i samma ögonblick som hen faktiskt
   * ska skapa eller gå med i ett rum. Slår spärren till (30/timme och IP) kastas
   * ett begripligt svenskt fel i stället för RPC:ns "permission denied for
   * function create_room".
   */
  const ensureSession = useCallback(async () => {
    if (!isSupabaseConfigured) throw new Error('Supabase är inte konfigurerat.')
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (session?.user) return session.user

    if (!signInFlight.current) {
      signInFlight.current = supabase.auth.signInAnonymously().finally(() => {
        signInFlight.current = null
      })
    }
    const { data, error } = await signInFlight.current
    if (error) throw translateAuthError(error)
    setUser(data.user)
    return data.user
  }, [])

  const value = {
    user,
    loading,
    isConfigured: isSupabaseConfigured,
    preferredName,
    setPreferredName,
    deleteMyData,
    ensureSession,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth måste användas inuti <AuthProvider>')
  return ctx
}
