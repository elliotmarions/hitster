// Synkad nedräkning innan låten startar (3 · 2 · 1 · 🎵). Visas som overlay.
export default function Countdown({ secondsToStart }) {
  const n = Math.ceil(secondsToStart)
  const label = n <= 0 ? '🎵' : n > 3 ? '3' : String(n)
  return (
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
    </div>
  )
}
