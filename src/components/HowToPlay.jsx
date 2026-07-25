import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import NeonButton from './ui/NeonButton.jsx'

/**
 * Flytande "?"-knapp med spelreglerna.
 *
 * Finns på startsidan, där hjälten numera bara är discokula och logga – utan
 * den här är det inget som berättar vad spelet går ut på förrän man skrollat
 * ned till korten. Den ligger MEDVETET inte i AppShell: lagchatten sitter på
 * exakt samma plats (fixed bottom-4 right-4) inne i ett rum, och två flytande
 * knappar i samma hörn krockar.
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
    d: 'Ett klipp ur en slumpad låt spelas i 25 sekunder, samtidigt hos alla.',
  },
  {
    n: '3',
    c: '#b6ff3c',
    t: 'Gissa',
    d: 'Skriv ditt svar och lås in det. När alla låst avslöjas svaren samtidigt.',
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
  'Suddregeln (kan slås på): rätt svar på "Exakt årtal" låter dig sudda ett kryss hos någon annan.',
  'Rättningen är automatisk men värden kan ändra en dom som blivit fel.',
]

export default function HowToPlay() {
  const [open, setOpen] = useState(false)
  const closeRef = useRef(null)
  const openerRef = useRef(null)

  useEffect(() => {
    if (!open) return
    const onKey = (e) => {
      // Samma väg ut som Stäng-knappen: fokus tillbaka till "?" så man inte
      // hamnar på <body> och får börja tabba om från sidans topp.
      if (e.key === 'Escape') {
        setOpen(false)
        openerRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKey)
    // preventScroll: rutan är scrollbar och Stäng ligger längst ned – utan det
    // scrollar fokuseringen rutan till botten och man möts av steg 3 i stället
    // för rubriken.
    closeRef.current?.focus({ preventScroll: true })
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  // Fokus tillbaka till knappen när rutan stängs – annars tappar tangentbords-
  // och skärmläsaranvändare sin plats på sidan.
  function close() {
    setOpen(false)
    openerRef.current?.focus()
  }

  return (
    <>
      <button
        ref={openerRef}
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Så spelar man"
        title="Så spelar man"
        className="fixed bottom-4 right-4 z-40 flex h-11 w-11 cursor-pointer items-center justify-center rounded-full border border-cyan/60 bg-midnight/80 font-display text-xl text-cyan transition hover:bg-cyan/10"
        style={{ boxShadow: '0 0 22px -6px #22e6e6' }}
      >
        ?
      </button>

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
