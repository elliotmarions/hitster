import { createPortal } from 'react-dom'

/**
 * Synkad nedräkning innan låten startar (3 · 2 · 1 · 🎵). Visas som overlay.
 *
 * Renderas via portal till <body>. Annars ärver overlayen förälderns
 * layoutmarginal – GameView ligger i en `space-y-6`, som ger varje barn utom
 * det sista `margin-bottom: 1.5rem`. På ett fixed-element med både top:0 och
 * bottom:0 dras den marginalen av från höjden, så nedräkningen slutade 24px
 * ovanför skärmens nederkant och lämnade en omörklagd remsa där.
 */
export default function Countdown({ secondsToStart }) {
  const n = Math.ceil(secondsToStart)
  const label = n <= 0 ? '🎵' : n > 3 ? '3' : String(n)
  return createPortal(
    <div className="pointer-events-none fixed inset-0 z-40 flex items-center justify-center bg-midnight/40 backdrop-blur-[2px]">
      <div className="flex flex-col items-center gap-3">
        <p className="label text-cream">Gör dig redo</p>
        <div
          className="anim-pulse font-display text-8xl leading-none neon-text sm:text-9xl"
          style={{ '--neon': '#22e6e6' }}
        >
          {label}
        </div>
        <p className="text-sm text-muted">Samma låt startar hos alla samtidigt</p>
      </div>
    </div>,
    document.body,
  )
}
