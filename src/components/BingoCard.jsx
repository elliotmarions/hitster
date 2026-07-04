import { CATEGORIES } from '../lib/constants'
import { winningLine } from '../lib/game'

// Handritat kryss (två sneda penseldrag) – knyter det digitala till den fysiska brickan.
function CrossMark({ color, lg }) {
  return (
    <svg
      viewBox="0 0 100 100"
      className="pointer-events-none absolute inset-0 h-full w-full"
      style={{ filter: `drop-shadow(0 0 4px ${color}bb)` }}
    >
      <g
        stroke={color}
        strokeWidth={lg ? 9 : 12}
        strokeLinecap="round"
        fill="none"
        transform="rotate(-4 50 50)"
      >
        <path d="M22 24 Q 50 46 80 78" />
        <path d="M78 22 Q 52 52 20 80" />
      </g>
    </svg>
  )
}

/**
 * En spelares bingobricka (4x4). Alla ser allas brickor.
 * - Egen bricka (variant 'lg'): klicka en ruta vars kategori matchar rundan för att kryssa.
 * - Medspelares bricka (variant 'sm'): läsbar; om suddregeln gäller kan man klicka
 *   ett kryss för att sudda.
 */
export default function BingoCard({
  card,
  playerName,
  isOwn = false,
  currentCategory = null,
  canMark = false,
  canUnmark = false,
  canErase = false,
  onMark,
  onUnmark,
  onErase,
  variant = 'lg',
}) {
  const grid = card?.grid ?? []
  const win = card?.has_won ? winningLine(grid) : null
  const lg = variant === 'lg'

  return (
    <div
      className={`panel ${lg ? 'p-4' : 'p-2.5'}`}
      style={card?.has_won ? { boxShadow: '0 0 26px -3px #ffc93c', borderColor: '#ffc93c' } : undefined}
    >
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className={`truncate font-display ${lg ? 'text-lg text-cream' : 'text-xs text-cream'}`}>
          {playerName}
          {isOwn && <span className="text-muted"> (du)</span>}
        </span>
        {card?.has_won && (
          <span className="chip" style={{ '--neon': '#ffc93c' }}>
            Hitster!
          </span>
        )}
      </div>

      <div className={`grid grid-cols-5 ${lg ? 'gap-1.5' : 'gap-1'}`}>
        {grid.map((cell, i) => {
          // Fallback så en okänd/gammal kategori aldrig kraschar renderingen.
          const cat = CATEGORIES[cell.category] ?? { hex: '#6b5a9c', short: '?', label: 'Okänd' }
          const eligibleMark = isOwn && canMark && !cell.filled && cell.category === currentCategory
          const eligibleUnmark = isOwn && canUnmark && cell.filled
          const eligibleErase = canErase && !isOwn && cell.filled
          const inWin = win?.includes(i)
          const clickable = eligibleMark || eligibleUnmark || eligibleErase
          return (
            <button
              key={i}
              type="button"
              disabled={!clickable}
              onClick={() =>
                eligibleMark
                  ? onMark?.(i)
                  : eligibleUnmark
                    ? onUnmark?.(i)
                    : eligibleErase
                      ? onErase?.(i)
                      : undefined
              }
              title={eligibleUnmark ? 'Ta bort kryss' : eligibleErase ? 'Sudda kryss' : cat.label}
              className={`relative aspect-square overflow-hidden rounded-md border ${
                clickable ? 'cursor-pointer hover:brightness-125' : 'cursor-default'
              } ${eligibleErase ? 'hover:ring-2 hover:ring-magenta' : ''} ${
                eligibleUnmark ? 'hover:ring-2 hover:ring-cream/60' : ''
              }`}
              style={{
                background: `color-mix(in srgb, ${cat.hex} ${cell.filled ? 24 : eligibleMark ? 30 : 12}%, #140c22)`,
                borderColor: eligibleMark
                  ? cat.hex
                  : inWin
                    ? '#ffc93c'
                    : `color-mix(in srgb, ${cat.hex} 42%, transparent)`,
                boxShadow: eligibleMark
                  ? `0 0 14px -2px ${cat.hex}, inset 0 0 10px -6px ${cat.hex}`
                  : inWin
                    ? '0 0 14px -2px #ffc93c'
                    : 'none',
              }}
            >
              {lg && (
                <span
                  className="absolute left-1 top-0.5 font-display text-[9px] uppercase tracking-wide"
                  style={{ color: `color-mix(in srgb, ${cat.hex} 72%, #ffffff)` }}
                >
                  {cat.short}
                </span>
              )}
              {cell.filled && <CrossMark color={cat.hex} lg={lg} />}
            </button>
          )
        })}
      </div>
    </div>
  )
}
