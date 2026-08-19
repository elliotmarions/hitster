import { createContext, useCallback, useContext, useMemo, useState } from 'react'

/**
 * Volymen, som en enda sanning för hela appen.
 *
 * Den bodde tidigare inuti useSyncedAudio, alltså inuti spelvyn – därför gick
 * den bara att ändra medan man spelade. Nu ligger den här, så headern kan visa
 * samma reglage på start-, lobby- och profilsidan utan att två kontroller
 * hamnar i otakt.
 *
 * Volymen är LOKAL per enhet (varje spelare spelar sitt eget klipp – inget
 * synkas) och sparas mellan spel. 0–1.
 *
 * NIVÅN sparas, men inte MUTNINGEN. Noll är inte en nivå utan ett tillstånd
 * för stunden ("tyst nu, någon ringer"), och sparades den vaknade appen tyst
 * nästa spelkväll också. Enda signalen var en liten 🔇-ikon i scenens hörn, så
 * det såg ut precis som en bugg: allt fungerar, ingen låt hörs.
 */
const VOLUME_KEY = 'hbo:volume'

function rememberedVolume() {
  try {
    const v = parseFloat(localStorage.getItem(VOLUME_KEY))
    // <= 0 kan bara komma från en gammal sparad mutning – börja med ljud på.
    return Number.isFinite(v) && v > 0 ? Math.min(1, v) : 1
  } catch {
    return 1
  }
}

const VolumeContext = createContext(null)

export function VolumeProvider({ children }) {
  const [volume, setVolumeState] = useState(rememberedVolume)

  const setVolume = useCallback((v) => {
    const clamped = Math.min(1, Math.max(0, Number(v) || 0))
    setVolumeState(clamped)
    try {
      // Bara riktiga nivåer sparas – en mutning gäller den här sidladdningen.
      if (clamped > 0) localStorage.setItem(VOLUME_KEY, String(clamped))
    } catch {
      /* privat läge e.d. – strunt samma */
    }
  }, [])

  const value = useMemo(() => ({ volume, setVolume }), [volume, setVolume])
  return <VolumeContext.Provider value={value}>{children}</VolumeContext.Provider>
}

/** Utan provider (t.ex. i ett test) är volymen full och går inte att ändra. */
export function useVolume() {
  return useContext(VolumeContext) ?? { volume: 1, setVolume: () => {} }
}
