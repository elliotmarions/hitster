import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import NeonButton from './ui/NeonButton.jsx'

/**
 * "?"-knapp med spelreglerna.
 *
 * placement="floating" (default) – startsidans flytande knapp. Hjälten där är
 *   bara discokula och logga, så utan den är det inget som berättar vad spelet
 *   går ut på förrän man skrollat ned till korten.
 * placement="inline" – en liten knapp som anroparen placerar själv. Används i
 *   spelvyns rubrikrad, där reglerna behövs som mest ("vad betyder ±3 år?")
 *   men hörnet redan är upptaget av lagchatten (fixed bottom-4 right-4).
 *
 * Den ligger alltså MEDVETET inte i AppShell: två flytande knappar i samma
 * hörn krockar.
 *
 * Samma overlay-recept som ConfirmDialog: portal till <body>, explicit höjd i
 * dvh och ingen backdrop-filter (den gav ett eget kompositeringslager som
 * Chrome klippte, så en remsa längst ned blev omålad).
 */

const STEG = [
  {
    n: '1',
    c: '#ff2e9a',
    t: 'Snurra',
    d: 'Värden snurrar discokulan. Den landar på en kategori – årtionde, artist, årtal eller låttitel.',
  },
  {
    n: '2',
    c: '#22e6e6',
    t: 'Lyssna',
    d: 'Ett klipp ur en slumpad låt spelas i upp till 25 sekunder, samtidigt hos alla.',
  },
  {
    n: '3',
    c: '#b6ff3c',
    t: 'Gissa',
    d: 'Skriv ditt svar och lås in det redan medan låten spelar. När alla låst stoppas låten och svaren avslöjas samtidigt.',
  },
  {
    n: '4',
    c: '#ffc93c',
    t: 'Kryssa',
    d: 'Hade du rätt får du kryssa en ruta i rundans kategori på din bricka.',
  },
  {
    n: '5',
    c: '#b14dff',
    t: 'Vinn',
    d: 'Fem i rad vinner – vågrätt, lodrätt eller diagonalt.',
  },
]

const BRA_ATT_VETA = [
  'Värden delar en rumskod. Alla spelar i webbläsaren, ingen app behövs.',
  'Välj musik efter sällskapet: alla låtar, bara svenska, eller ett åldersspann som riktar potten mot en era.',
  'Spela var för sig eller dela in gänget i lag – då delar laget bricka och svar.',
  'Suddregeln (kan slås på): pricka utgivningsåret så får du sudda ett kryss hos någon annan. Handlar rundan inte om årtal gissar du året i en bonusruta bredvid svaret – exakt rätt år krävs, och det räknas även om du missar rundans egen fråga.',
  'Rättningen är automatisk men värden kan ändra en dom som blivit fel.',
]

/**
 * Props:
 * - placement: 'floating' | 'inline' – var den egna "?"-knappen sitter.
 * - open / onClose: styr rutan utifrån. Skickas `open` in tar den som skickar
 *   över ansvaret, och då ritas ingen egen knapp – det är så kontomenyn öppnar
 *   rutan utan att en andra "?" dyker upp i headern.
 */
export default function HowToPlay({ placement = 'floating', open: openProp, onClose }) {
  const controlled = openProp !== undefined
  const [openState, setOpenState] = useState(false)
  const open = controlled ? openProp : openState
  const closeRef = useRef(null)
  const openerRef = useRef(null)

  useEffect(() => {
    if (!open) return
    const onKey = (e) => {
      // Samma väg ut som Stäng-knappen: fokus tillbaka till "?" så man inte
      // hamnar på <body> och får börja tabba om från sidans topp.
      if (e.key === 'Escape') close()
    }
    window.addEventListener('keydown', onKey)
    // preventScroll: rutan är scrollbar och Stäng ligger längst ned – utan det
    // scrollar fokuseringen rutan till botten och man möts av steg 3 i stället
    // för rubriken.
    closeRef.current?.focus({ preventScroll: true })
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  // Fokus tillbaka till knappen när rutan stängs – annars tappar tangentbords-
  // och skärmläsaranvändare sin plats på sidan. Styrs rutan utifrån är det den
  // som öppnade som får lämna tillbaka fokus; den vet vart.
  function close() {
    if (controlled) {
      onClose?.()
      return
    }
    setOpenState(false)
    openerRef.current?.focus()
  }

  return (
    <>
      {/* Mobil: absolut i sidans övre högra hörn, alltså PARKERAD där uppe –
          den ska inte följa med i vyn när man skrollar (fixed la sig mitt över
          formulärfälten på vägen ned). Kräver `relative` på LandingPage-roten.
          Desktop (sm+): fast nere till höger, där marginalerna ändå står tomma.
          z-10 på mobil (headern är z-20): knappen ska glida IN UNDER den sticky
          headern när man skrollar förbi, inte ovanpå den. */}
      {!controlled && (
      <button
        ref={openerRef}
        type="button"
        onClick={() => setOpenState(true)}
        aria-label="Så spelar man"
        title="Så spelar man"
        className={
          placement === 'inline'
            ? 'flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-full border border-cyan/60 font-display text-base text-cyan transition hover:bg-cyan/10'
            : 'absolute right-0 top-0 z-10 flex h-11 w-11 cursor-pointer items-center justify-center rounded-full border border-cyan/60 bg-midnight/80 font-display text-xl text-cyan transition hover:bg-cyan/10 sm:fixed sm:bottom-4 sm:right-4 sm:top-auto sm:z-40'
        }
        style={placement === 'inline' ? undefined : { boxShadow: '0 0 22px -6px #22e6e6' }}
      >
        ?
      </button>
      )}

      {open &&
        createPortal(
          <div
            className="fixed left-0 top-0 z-50 m-0 flex w-full items-center justify-center p-4"
            style={{ height: '100dvh', background: 'rgba(10,7,19,0.86)' }}
            role="dialog"
            aria-modal="true"
            aria-labelledby="howto-title"
            onClick={(e) => {
              if (e.target === e.currentTarget) close()
            }}
          >
            <div
              className="panel w-full max-w-lg overflow-y-auto p-6"
              style={{
                maxHeight: '86dvh',
                borderColor: '#22e6e6',
                boxShadow: '0 0 44px -12px #22e6e6',
              }}
            >
              <h2 id="howto-title" className="font-display text-2xl text-cream">
                Så spelar man
              </h2>
              <p className="mt-1 text-sm text-muted">
                Musikquiz och bingo på samma bricka.
              </p>

              <ol className="mt-5 space-y-3">
                {STEG.map((s) => (
                  <li key={s.n} className="flex gap-3">
                    <span
                      className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full font-display text-sm"
                      style={{ background: `${s.c}22`, color: s.c, border: `1px solid ${s.c}66` }}
                    >
                      {s.n}
                    </span>
                    <span>
                      <span className="font-display text-cream" style={{ color: s.c }}>
                        {s.t}
                      </span>
                      <span className="mt-0.5 block text-sm text-muted">{s.d}</span>
                    </span>
                  </li>
                ))}
              </ol>

              <p className="label mt-6">Bra att veta</p>
              <ul className="mt-2 space-y-1.5">
                {BRA_ATT_VETA.map((t) => (
                  <li key={t} className="flex gap-2 text-sm text-muted">
                    <span aria-hidden="true" className="text-cyan">
                      •
                    </span>
                    <span>{t}</span>
                  </li>
                ))}
              </ul>

              <div className="mt-6 flex justify-end">
                {/* outline, inte primary: btn-primary är hårdkodat magenta och
                    lyssnar inte på neon-proppen, vilket krockar med cyan-ramen. */}
                <NeonButton ref={closeRef} variant="outline" neon="#22e6e6" onClick={close}>
                  Stäng
                </NeonButton>
              </div>
            </div>
          </div>,
          document.body,
        )}
    </>
  )
}
