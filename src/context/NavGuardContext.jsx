import { createContext, useCallback, useContext, useEffect, useRef } from 'react'

/**
 * Spärr för navigering ut ur skalet (logotypen uppe till vänster).
 *
 * Problemet: mitt i en match ligger "Lämna" bakom en bekräftelseruta, men
 * logotypen är en vanlig <Link to="/"> – ett klick där (eller en felträff på
 * mobil, den sitter nära skärmkanten) slängde ut spelaren direkt, utan fråga
 * och utan att `leaveRoom` hann köras.
 *
 * Lösningen är avsiktligt liten: vyn som har något att förlora registrerar en
 * funktion, skalet frågar innan det navigerar. Registret ligger i en ref, inte
 * i state – skalet läser det först vid klicket, så en ny registrering ska inte
 * rita om headern.
 */
const NavGuardContext = createContext(null)

export function NavGuardProvider({ children }) {
  const guardRef = useRef(null)

  const register = useCallback((fn) => {
    guardRef.current = fn
    // Avregistrera bara sig själv – annars kan en vy som just monterats få sin
    // spärr bortstädad av den vy som lämnar (StrictMode kör dubbelt i dev).
    return () => {
      if (guardRef.current === fn) guardRef.current = null
    }
  }, [])

  /** Kör spärren om någon registrerat en. Sant = navigeringen ska stoppas. */
  const runGuard = useCallback(() => {
    const fn = guardRef.current
    if (!fn) return false
    fn()
    return true
  }, [])

  return (
    <NavGuardContext.Provider value={{ register, runGuard }}>
      {children}
    </NavGuardContext.Provider>
  )
}

/** För skalet: fråga spärren innan navigering. Utan provider blockeras inget. */
export function useNavGuardRunner() {
  const ctx = useContext(NavGuardContext)
  return ctx?.runGuard ?? (() => false)
}

/**
 * För vyn: `onBlocked` körs i stället för navigeringen så länge `active` är sant.
 * Skicka in en stabil funktion (useCallback) så registreringen inte görs om vid
 * varje omritning.
 */
export function useNavGuard(active, onBlocked) {
  const ctx = useContext(NavGuardContext)
  useEffect(() => {
    if (!ctx || !active) return undefined
    return ctx.register(onBlocked)
  }, [ctx, active, onBlocked])
}
