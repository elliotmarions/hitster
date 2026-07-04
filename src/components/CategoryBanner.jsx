import { CATEGORIES } from '../lib/constants'

// Visar rundans kategori stort och färgat – "lyser upp" gränssnittet i kategorifärgen.
export default function CategoryBanner({ round, spinning }) {
  if (!round) {
    return (
      <div className="text-center">
        <p className="label">Discokulan</p>
        <p className="mt-1 font-display text-2xl text-muted">Väntar på snurr…</p>
      </div>
    )
  }
  if (spinning) {
    return (
      <div className="text-center">
        <p className="label">Discokulan snurrar</p>
        <p className="anim-pulse mt-1 font-display text-3xl text-cream">Snurrar…</p>
      </div>
    )
  }
  const cat = CATEGORIES[round.category]
  if (!cat) return null
  return (
    <div className="text-center" style={{ '--neon': cat.hex }}>
      <p className="label">Rundans kategori</p>
      <h2 className="neon-text mt-1 font-display text-4xl">{cat.label}</h2>
      <p className="mt-1 text-sm text-muted">{cat.desc}</p>
    </div>
  )
}
