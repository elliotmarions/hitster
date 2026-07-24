import { createPortal } from 'react-dom'

/**
 * Synkad nedräkning innan låten startar (3 · 2 · 1 · 🎵). Visas som overlay.
 *
 * Renderas via portal till <body>. Annars ärver overlayen förälderns
 * layoutmarginal – GameView ligger i en `space-y-6`, som ger varje barn utom
 * det sista `margin-bottom: 1.5rem`. På ett fixed-element med både top:0 och
 * bottom:0 dras den marginalen av från höjden.
 *
 * Höjden sätts explicit i dvh i stället för att låta `inset-0` räkna ut den ur
 * top+bottom, och `backdrop-blur` är medvetet borttaget: det tvingade fram ett
 * eget kompositeringslager som Chrome klippte mot en mindre yta än elementet,
 * så en remsa längst ned blev omålad trots att layouten mätte rätt. Mörkret är
 * höjt från /40 till /70 som kompensation för den borttagna oskärpan.
 */
export default function Countdown({ secondsToStart, preparing = false }) {
  // preparing = värden har tryckt "Starta låt" men servern har inte hunnit sätta
  // timer_start_at än (letar upp klippet). Visar en pulserande not tills den
  // riktiga 3-2-1-nedräkningen tar över – ingen död lucka, ingen pop.
  const n = Math.ceil(secondsToStart ?? 0)
  const label = preparing ? '🎵' : n <= 0 ? '🎵' : n > 3 ? '3' : String(n)
  const sub = preparing ? 'Letar upp låten…' : 'Samma låt startar hos alla samtidigt'
  return createPortal(
    <div
      className="pointer-events-none fixed left-0 top-0 z-40 m-0 flex w-full items-center justify-center bg-midnight/70"
      style={{ height: '100dvh' }}
    >
      <div className="flex flex-col items-center gap-3">
        <p className="label text-cream">Gör dig redo</p>
        <div
          className="anim-pulse font-display text-8xl leading-none neon-text sm:text-9xl"
          style={{ '--neon': '#22e6e6' }}
        >
          {label}
        </div>
        <p className="text-sm text-muted">{sub}</p>
      </div>
    </div>,
    document.body,
  )
}
