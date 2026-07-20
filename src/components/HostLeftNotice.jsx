import { createPortal } from 'react-dom'
import NeonButton from './ui/NeonButton.jsx'

/**
 * Liten overlay-ruta som visas för kvarvarande spelare när VÄRDEN lämnat
 * rummet och spelet därmed avslutats (rooms.ended_reason = 'host_left').
 *
 * Portal till <body> av samma skäl som Countdown: förälderns `space-y-6` ger
 * annars overlayen en bottenmarginal som kortar av den mot skärmens nederkant.
 */
export default function HostLeftNotice({ onBack }) {
  return createPortal(
    <div
      className="fixed left-0 top-0 z-50 m-0 flex w-full items-center justify-center p-4"
      style={{ height: '100dvh', background: 'rgba(10,7,19,0.86)' }}
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
    </div>,
    document.body,
  )
}
