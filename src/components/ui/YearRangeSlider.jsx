/**
 * Tidslinje med två handtag: välj från–till-år för låtpotten.
 *
 * Props:
 *   min, max  – skalans ändar (AR_MIN/AR_MAX)
 *   value     – [från, till]
 *   disabled  – icke-värdar ser spannet men rör det inte
 *   onChange  – ([från, till]) => void, ropas på under dragningen
 */
export default function YearRangeSlider({ min, max, value, disabled = false, onChange }) {
  const [lo, hi] = value
  const pct = (v) => ((v - min) / (max - min)) * 100

  // Handtagen får inte passera varandra – då hade "från" blivit senare än
  // "till" och spannet vänt ut och in. Det som knuffas emot stannar i stället.
  const sattLo = (v) => onChange([Math.min(Number(v), hi), hi])
  const sattHi = (v) => onChange([lo, Math.max(Number(v), lo)])

  // Ligger båda handtagen på samma punkt hamnar det ena ovanpå det andra och
  // spärrar. Nära toppen lyfts "från" upp, annars går spannet inte att öppna
  // igen när man dragit ihop det längst till höger.
  const franOverst = lo > max - (max - min) * 0.12

  // Decennierna gör skalan läsbar – utan dem är det bara ett streck.
  const decennier = []
  for (let ar = Math.ceil(min / 10) * 10; ar <= max; ar += 10) decennier.push(ar)

  return (
    <div>
      <div className="tidslinje">
        <div className="tidslinje-spar" />
        <div
          className="tidslinje-valt"
          style={{ left: `${pct(lo)}%`, right: `${100 - pct(hi)}%` }}
        />
        <input
          type="range"
          min={min}
          max={max}
          value={lo}
          disabled={disabled}
          onChange={(e) => sattLo(e.target.value)}
          aria-label="Från år"
          style={{ zIndex: franOverst ? 4 : 3, '--neon': '#b14dff' }}
        />
        <input
          type="range"
          min={min}
          max={max}
          value={hi}
          disabled={disabled}
          onChange={(e) => sattHi(e.target.value)}
          aria-label="Till år"
          style={{ zIndex: franOverst ? 3 : 4 }}
        />
      </div>

      <div className="mt-1 flex justify-between text-[10px] text-muted">
        {decennier.map((ar) => (
          <span key={ar}>{`'${String(ar).slice(2)}`}</span>
        ))}
      </div>
    </div>
  )
}
