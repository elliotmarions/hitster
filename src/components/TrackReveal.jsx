import { CATEGORIES } from '../lib/constants'

// Facit efter rundan: låt, artist och år (från Spotify-metadatan).
export default function TrackReveal({ meta, category }) {
  if (!meta) return null
  const cat = CATEGORIES[category]
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
    </div>
  )
}
