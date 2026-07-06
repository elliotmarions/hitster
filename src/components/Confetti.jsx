import { useMemo } from 'react'
import { TEAM_COLORS } from '../lib/constants.js'

/**
 * Diskret vinstkonfetti: några små neonbitar som faller en gång inom
 * förälderns yta (kräver position: relative + overflow: hidden på föräldern)
 * och tonar ut. Rent kosmetisk – pointer-events: none. Avstängd vid
 * prefers-reduced-motion (se index.css).
 */
export default function Confetti({ count = 26 }) {
  const pieces = useMemo(
    () =>
      Array.from({ length: count }, (_, i) => ({
        left: Math.random() * 100,
        delay: Math.random() * 0.7,
        duration: 2.2 + Math.random() * 1.6,
        size: 5 + Math.random() * 6,
        color: TEAM_COLORS[i % TEAM_COLORS.length],
        drift: (Math.random() * 2 - 1) * 46,
        rot: 180 + Math.random() * 360,
        round: Math.random() > 0.5,
      })),
    [count],
  )

  return (
    <div className="confetti-layer" aria-hidden="true">
      {pieces.map((p, i) => (
        <span
          key={i}
          className="confetti-piece"
          style={{
            left: `${p.left}%`,
            width: `${p.size}px`,
            height: `${p.size}px`,
            background: p.color,
            borderRadius: p.round ? '50%' : '2px',
            boxShadow: `0 0 6px ${p.color}`,
            animationDuration: `${p.duration}s`,
            animationDelay: `${p.delay}s`,
            '--drift': `${p.drift}px`,
            '--rot': `${p.rot}deg`,
          }}
        />
      ))}
    </div>
  )
}
