import NeonButton from './ui/NeonButton.jsx'

/**
 * Liten overlay-ruta som visas för kvarvarande spelare när VÄRDEN lämnat
 * rummet och spelet därmed avslutats (rooms.ended_reason = 'host_left').
 */
export default function HostLeftNotice({ onBack }) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(10,7,19,0.72)', backdropFilter: 'blur(2px)' }}
      role="dialog"
      aria-modal="true"
    >
      <div
        className="panel w-full max-w-sm p-6 text-center"
        style={{ borderColor: '#ff2e9a', boxShadow: '0 0 44px -12px #ff2e9a' }}
      >
        <p className="text-4xl">👋</p>
        <h2 className="mt-2 font-display text-2xl text-cream">Värden lämnade rummet</h2>
        <p className="mt-2 text-sm text-muted">
          Spelet avslutades eftersom värden lämnade. Starta ett nytt spel från startsidan.
        </p>
        <div className="mt-5 flex justify-center">
          <NeonButton neon="#ff2e9a" onClick={onBack}>
            Till startsidan
          </NeonButton>
        </div>
      </div>
    </div>
  )
}
