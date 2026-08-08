import { useEffect, useRef, useState } from 'react'
import YearRangeSlider from '../ui/YearRangeSlider.jsx'
import {
  AR_MAX,
  AR_MIN,
  nextSpanFor,
  yearBandsFor,
  yearSpanLabel,
  yearSpansFrom,
} from '../../lib/constants.js'

// Hur länge ett utkast får ligga innan det skrivs. Fördröjningen finns för
// tangentbordet och för dragningar som aldrig släpps inne i rutan – släpper
// man fingret skrivs valet direkt (se skrivNu), så den märks sällan.
const SKRIV_FORDROJNING_MS = 200

/**
 * Årsvalet: en eller flera tidslinjer, med + för att lägga till ett spann.
 *
 * Egen komponent för att den äger sitt UTKAST. Låg utkastet i LobbyView ritades
 * hela lobbyn om – spelarlista, lagruta, chatt – vid varje pixel man drog
 * handtaget, och dragningen kändes trög på telefon. Nu stannar omritningen i
 * de här raderna, och lobbyn hör av sig först när valet faktiskt ändrats.
 *
 * Props:
 *   spans     – rummets spann som [[från, till], …] (tom lista = alla årtal)
 *   disabled  – icke-värdar ser spannen men rör dem inte
 *   onCommit  – (year_bands) => void, anropas när valet ska skrivas
 */
export default function YearSpanPicker({ spans, disabled = false, onCommit }) {
  // null = följ rummet. Utkastet speglas i en ref eftersom skrivNu behöver
  // det aktuella värdet i en händelsehanterare, utan att vänta på omritning.
  const [utkast, setUtkast] = useState(null)
  const utkastRef = useRef(null)
  const onCommitRef = useRef(onCommit)
  useEffect(() => {
    onCommitRef.current = onCommit
  })

  const satt = (nytt) => {
    utkastRef.current = nytt
    setUtkast(nytt)
  }

  // Ändras spannen till något ANNAT än det vi själva skrev, kommer ändringen
  // utifrån: värden tryckte Rensa, eller skrivningen nekades och lobbyn backade
  // till serverns sanning. Då ska utkastet släppas – annars ritar raderna kvar
  // ett val som inte finns, och timern skulle strax skriva tillbaka det.
  const forvantat = useRef(null)
  const spansNyckel = JSON.stringify(spans)
  useEffect(() => {
    if (spansNyckel === forvantat.current) return
    satt(null)
    // satt sätter bara state och en ref – stabil nog att utelämna.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spansNyckel])

  const valda = utkast ?? spans
  // Utan valda spann finns ingen årsgräns – då ritas EN tidslinje i fullt
  // utslag, så "Alla årtal" ser ut som det den är: hela skalan vald.
  const rader = valda.length ? valda : [[AR_MIN, AR_MAX]]
  const nasta = nextSpanFor(valda)

  const skriv = (spann) => {
    // Tom lista är ett giltigt utkast (alla spann bortkryssade) – därför
    // jämförs mot null, inte mot sanningsvärdet.
    if (spann === null) return
    const bands = yearBandsFor(spann)
    forvantat.current = JSON.stringify(yearSpansFrom({ year_bands: bands }))
    onCommitRef.current(bands)
    satt(null)
  }

  // Släppt handtag, klickat + eller × → skriv med en gång. Utan det låg valet
  // och väntade på timern efter att man redan var klar, och antalet låtar
  // uppdaterades en tankepaus för sent.
  const skrivNu = () => skriv(utkastRef.current)

  useEffect(() => {
    if (utkast === null) return undefined
    const id = setTimeout(() => skriv(utkastRef.current), SKRIV_FORDROJNING_MS)
    return () => clearTimeout(id)
    // skriv läser bara refar – att ta med den hade startat om timern i onödan.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [utkast])

  const andra = (i, nytt) => satt(rader.map((s, ix) => (ix === i ? nytt : s)))
  const taBort = (i) => satt(rader.filter((_, ix) => ix !== i))
  const laggTill = () => {
    if (!nasta) return
    // Nya spannet läggs SIST, under de andra – där man tryckte. Att sortera
    // listan kronologiskt hade flyttat raden ifrån en medan man tittade.
    // Från "Alla årtal" blir tillägget i stället det första spannet: hela
    // skalan plus ett spann till är fortfarande hela skalan.
    satt([...valda, nasta])
  }

  // Ett spann i klartext, via samma regler som sammanfattningen: öppen undre
  // kant blir "till och med", full skala blir "Alla årtal". Årtalen står bara i
  // sammanfattningen ovanför – under tidslinjen upprepade de bara det som
  // redan stod där. Kvar behövs texten för att krysset ska säga VILKET spann
  // det tar bort när det läses upp.
  const spannText = (spann) =>
    yearSpanLabel({ year_bands: yearBandsFor([spann]) }) ?? 'Alla årtal'

  return (
    <>
      {/* Sammanfattningen läses ur utkastet, inte ur rummet, så texten följer
          med medan man drar i stället för att hoppa till när skrivningen gått
          igenom. */}
      <div className="mb-2 mt-4 flex items-baseline justify-between gap-3">
        <p className="label opacity-70">Årtal</p>
        <div className="flex items-baseline gap-2">
          <span className="font-display text-sm text-cream">
            {yearSpanLabel({ year_bands: yearBandsFor(valda) }) ?? 'Alla årtal'}
          </span>
          {!disabled && (
            <button
              type="button"
              onClick={laggTill}
              disabled={!nasta}
              aria-label="Lägg till ett årsspann"
              title="Lägg till ett årsspann"
              className="flex h-6 w-6 shrink-0 cursor-pointer items-center justify-center self-center rounded-full border border-cyan/60 font-display text-base leading-none text-cyan transition hover:bg-cyan/15 disabled:cursor-default disabled:opacity-40"
            >
              +
            </button>
          )}
        </div>
      </div>

      <div className="space-y-2" onPointerUp={skrivNu}>
        {rader.map((spann, i) => (
          <div key={i} className="panel-inset px-4 pb-2 pt-3">
            <div className="flex items-start gap-3">
              <div className="min-w-0 flex-1">
                <YearRangeSlider
                  min={AR_MIN}
                  max={AR_MAX}
                  value={spann}
                  disabled={disabled}
                  onChange={(nytt) => andra(i, nytt)}
                />
              </div>
              {/* Krysset saknas på den öppna raden: där finns inget spann att
                  ta bort, bara frånvaron av gräns. Platsen står kvar tom –
                  annars byter tidslinjen bredd (och decennierna under den
                  kryper ihop) i samma stund man lägger till sitt första
                  spann. */}
              {!disabled && valda.length > 0 ? (
                <button
                  type="button"
                  onClick={() => taBort(i)}
                  aria-label={`Ta bort spannet ${spannText(spann)}`}
                  title="Ta bort spannet"
                  className="mt-1 flex h-6 w-6 shrink-0 cursor-pointer items-center justify-center rounded-full border border-line text-muted transition hover:border-magenta hover:text-magenta"
                >
                  ×
                </button>
              ) : (
                <span className="mt-1 h-6 w-6 shrink-0" aria-hidden="true" />
              )}
            </div>
          </div>
        ))}
      </div>
    </>
  )
}
