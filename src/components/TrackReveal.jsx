import { CATEGORIES, GENRE_CHOICES } from '../lib/constants'

// Facit efter rundan: låt, artist och år (från låtpottens metadata).
export default function TrackReveal({ meta, category }) {
  if (!meta) return null
  const cat = CATEGORIES[category]
  // Rundans egen fråga syns inte i titel/artist/år när den handlade om genre
  // eller språk – då skrivs svaret ut, annars vet ingen om de hade rätt.
  const extra =
    category === 'genre'
      ? GENRE_CHOICES.find(([k]) => k === meta.genre)?.[1] || null
      : category === 'swedish' && meta.sv !== undefined
        ? meta.sv
          ? 'Svensk låt'
          : 'Utländsk låt'
        : null
  return (
    <div className="panel-inset w-full max-w-md p-4 text-center">
      <p className="label" style={{ color: cat?.hex }}>
        Facit
      </p>
      <p className="mt-1 font-display text-xl text-cream">{meta.name}</p>
      <p className="text-sm text-muted">
        {meta.artist}
        {meta.year ? ` · ${meta.year}` : ''}
      </p>
      {extra && (
        <p className="mt-1 font-display text-sm" style={{ color: cat?.hex }}>
          {extra}
        </p>
      )}
    </div>
  )
}
