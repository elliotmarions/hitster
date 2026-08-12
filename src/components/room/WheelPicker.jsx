import { useState } from 'react'
import {
  ANTAL_KATEGORIER,
  CATEGORIES,
  SVART_HJUL,
  VALJBARA_KATEGORIER,
  categoryOrderFor,
} from '../../lib/constants.js'
import DiscoWheel from '../DiscoWheel.jsx'

// Samma fem, oavsett ordning? Uppsättningen är en mängd – ordningen styr bara
// var på hjulet segmenten hamnar.
const sammaSet = (a, b) =>
  Array.isArray(a) &&
  Array.isArray(b) &&
  a.length === b.length &&
  [...a].sort().join() === [...b].sort().join()

/**
 * Lobbyns andra steg: vilka fem kategorier hjulet (och brickan) ska ha.
 *
 * Tre vägar, i stigande grad av eget arbete:
 *   Originalhjul  rooms.categories = null, alltså automatiken. Klassiska fem,
 *                 och fortfarande det svårare setet om ni valt en smal era –
 *                 därför sparas NULL här och inte de fem nycklarna.
 *   Svårt hjul    samma fem som åldersläget: exakt årtal, artist, titel,
 *                 ±1 år och före/efter.
 *   Bygg själv    fem av tio.
 *
 * Props: room (med ev. optimistiskt lager), isHost, busy, onValj(cats|null).
 */
export default function WheelPicker({ room, isHost, busy = false, onValj }) {
  const valda = Array.isArray(room?.categories) ? room.categories : null
  const aktiv = !valda ? 'original' : sammaSet(valda, SVART_HJUL) ? 'svart' : 'eget'

  // Har rummet redan en egen uppsättning ändrar man i den. Annars börjar man
  // TOMT: förifyllt med originalhjulet såg ut som ett förslag man skulle sålla
  // i, fast meningen är att man fyller i själv.
  const [egna, setEgna] = useState(() => (valda ? [...valda] : []))
  const [oppetEget, setOppetEget] = useState(aktiv === 'eget')
  const [hint, setHint] = useState('')

  // Hjulet visar utkastet så fort man börjat bygga. Ett TOMT utkast visar i
  // stället det som faktiskt gäller – rummet spelar ju fortfarande på den
  // sparade uppsättningen tills fem nya är i.
  const bygger = (aktiv === 'eget' || oppetEget) && egna.length > 0
  const hjulet = bygger ? egna : categoryOrderFor(room)

  // Gratispoäng: två av kategorierna har samma svar hela matchen om urvalet
  // redan låst dem. Servern hindrar det inte – urvalet kan ändras efteråt –
  // så det är här det ska sägas.
  const genreLast = Array.isArray(room?.genres) && room.genres.length === 1
  const sprakLast = room?.swedish_mode === true || room?.swedish_mode === false
  const varningar = []
  if (hjulet.includes('genre') && genreLast)
    varningar.push('Ni spelar bara en genre, så Genren har samma svar varje runda.')
  if (hjulet.includes('swedish') && sprakLast)
    varningar.push('Ni har låst språket, så Svenskt eller inte har samma svar varje runda.')

  function valjKort(kort) {
    if (!isHost) return
    setHint('')
    if (kort === 'original') {
      setOppetEget(false)
      onValj(null)
    } else if (kort === 'svart') {
      setOppetEget(false)
      onValj([...SVART_HJUL])
    } else {
      // Öppnar bara byggaren. Den sparade uppsättningen står kvar tills fem
      // egna är i – att skriva något vid själva klicket vore att spara ett val
      // man inte gjort än.
      setOppetEget(true)
    }
  }

  function toggla(key) {
    if (!isHost) return
    const har = egna.includes(key)
    if (!har && egna.length >= ANTAL_KATEGORIER) {
      setHint('Fem åt gången – klicka bort en först.')
      return
    }
    const nya = har ? egna.filter((k) => k !== key) : [...egna, key]
    setHint('')
    setEgna(nya)
    // Bara en komplett uppsättning går att spara (kolumnens check kräver fem),
    // så en halvfärdig ändring lever i utkastet tills den femte klickas i.
    if (nya.length === ANTAL_KATEGORIER) onValj(nya)
  }

  // Korten säger vad de ger med kategorinamnen, inte med en mening till.
  // Tre rader beskrivande text ovanför tio rader beskrivande text gjorde vyn
  // omöjlig att överblicka – och namnen är vad man faktiskt jämför.
  const kort = [
    {
      key: 'original',
      namn: 'Originalhjul',
      cats: categoryOrderFor({ ...room, categories: null }),
    },
    { key: 'svart', namn: 'Svårt hjul', cats: SVART_HJUL },
    { key: 'eget', namn: 'Bygg själv', cats: egna },
  ]

  return (
    <div className="space-y-5">
      <div>
        <p className="label">Steg 2 av 2</p>
        <h2 className="mt-1 font-display text-2xl text-cream">Vad ska hjulet fråga om?</h2>
      </div>

      <div className="grid items-center gap-5 sm:grid-cols-[1fr_auto]">
        <div className="space-y-3">
          {kort.map((k) => {
            // Ramen följer kortet man står i, chippen det som FAKTISKT är
            // sparat. Öppnar man byggaren med ett tomt utkast spelar rummet
            // fortfarande på sin gamla uppsättning, och då vore "Valt" en lögn.
            const oppen = (oppetEget ? 'eget' : aktiv) === k.key
            const sparad = aktiv === k.key
            return (
              <button
                key={k.key}
                type="button"
                disabled={!isHost || busy}
                onClick={() => valjKort(k.key)}
                aria-pressed={oppen}
                className="panel-inset w-full cursor-pointer p-4 text-left transition disabled:cursor-default disabled:opacity-60"
                style={{
                  borderColor: oppen ? '#22e6e6' : undefined,
                  boxShadow: oppen ? '0 0 24px -10px #22e6e6' : undefined,
                }}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="font-display text-lg text-cream">{k.namn}</span>
                  {sparad && (
                    <span className="chip shrink-0" style={{ '--neon': '#22e6e6' }}>
                      Valt
                    </span>
                  )}
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {k.cats.map((c) => (
                    <span
                      key={c}
                      className="rounded-full px-2 py-0.5 text-[11px]"
                      style={{
                        border: `1px solid ${CATEGORIES[c]?.hex}66`,
                        color: CATEGORIES[c]?.hex,
                      }}
                    >
                      {CATEGORIES[c]?.short}
                    </span>
                  ))}
                  {k.cats.length < ANTAL_KATEGORIER && (
                    <span className="text-[11px] text-muted">
                      {k.cats.length} av {ANTAL_KATEGORIER} valda
                    </span>
                  )}
                </div>
              </button>
            )
          })}
        </div>

        {/* Hjulet som det kommer att se ut – snabbare att förstå än fem namn. */}
        <div className="mx-auto w-full max-w-[220px] sm:w-[220px]">
          <DiscoWheel round={null} order={hjulet} size={220} />
        </div>
      </div>

      {oppetEget && (
        <div className="panel-inset p-4">
          <div className="flex items-center justify-between gap-3">
            <p className="label">Välj fem</p>
            <span className="text-xs text-muted">
              {egna.length} av {ANTAL_KATEGORIER}
            </span>
          </div>
          {/* Bara namnen. Tio förklaringar under tio knappar sa mindre än de
              tio namnen gjorde – frågan står i klartext i spelet ändå. */}
          <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
            {VALJBARA_KATEGORIER.map((key) => {
              const c = CATEGORIES[key]
              const pa = egna.includes(key)
              return (
                <button
                  key={key}
                  type="button"
                  disabled={!isHost || busy}
                  onClick={() => toggla(key)}
                  aria-pressed={pa}
                  title={c.desc}
                  className="panel-inset cursor-pointer px-3 py-2 text-left font-display text-sm text-cream transition disabled:cursor-default disabled:opacity-60"
                  style={{
                    borderColor: pa ? c.hex : undefined,
                    boxShadow: pa ? `0 0 20px -10px ${c.hex}` : undefined,
                    opacity: !pa && egna.length >= ANTAL_KATEGORIER ? 0.5 : undefined,
                  }}
                >
                  {c.label}
                </button>
              )
            })}
          </div>
          {hint && <p className="mt-2 text-xs" style={{ color: '#ff8a3c' }}>{hint}</p>}
          {egna.length < ANTAL_KATEGORIER && (
            <p className="mt-2 text-xs text-muted">
              Välj {ANTAL_KATEGORIER - egna.length} till – hjulet sparas när fem är i.
            </p>
          )}
        </div>
      )}

      {varningar.map((v) => (
        <p key={v} className="text-xs" style={{ color: '#ff8a3c' }}>
          ⚠ {v}
        </p>
      ))}
    </div>
  )
}
