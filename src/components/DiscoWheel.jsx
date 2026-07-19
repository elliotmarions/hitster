import { useEffect, useRef, useState } from 'react'
import { CATEGORIES, CATEGORY_ORDER, SPIN_MS } from '../lib/constants'

// Geometri i SVG-koordinater (viewBox 240x240).
const CX = 120
const CY = 120
const R = 112
const LABEL_R = 76
const N = CATEGORY_ORDER.length // antal kategorier = antal segment (5)
const SEG = 360 / N // gradtal per segment

// Vinkel mäts medurs från toppen (12-läget).
function pointAt(deg, radius) {
  const rad = (deg * Math.PI) / 180
  return [CX + radius * Math.sin(rad), CY - radius * Math.cos(rad)]
}
function slicePath(centerDeg) {
  const [x1, y1] = pointAt(centerDeg - SEG / 2, R)
  const [x2, y2] = pointAt(centerDeg + SEG / 2, R)
  const large = SEG > 180 ? 1 : 0
  return `M ${CX} ${CY} L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${R} ${R} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`
}

// Dekorativa lampor runt kanten (disco-marquee), roterar inte.
const BULBS = Array.from({ length: 30 }, (_, i) => pointAt(i * 12, R + 6))

export default function DiscoWheel({ round, size = 300 }) {
  const [rotation, setRotation] = useState(0)
  const [spinning, setSpinning] = useState(false)
  const lastRound = useRef(0)

  // När en ny runda kommer: rotera hjulet så rätt kategori hamnar under pekaren.
  // Alla klienter får samma kategori från servern → landar på samma segment.
  useEffect(() => {
    if (!round?.round_number || round.round_number === lastRound.current) return
    lastRound.current = round.round_number
    const seg = CATEGORY_ORDER.indexOf(round.category)
    if (seg < 0) return
    const target = (((-seg * SEG) % 360) + 360) % 360 // önskad slutorientering (mod 360)
    setRotation((prev) => {
      const curMod = ((prev % 360) + 360) % 360
      const delta = (target - curMod + 360) % 360
      return prev + delta + 360 * 5 // + 5 hela varv för känsla
    })
    setSpinning(true)
    const t = setTimeout(() => setSpinning(false), SPIN_MS)
    return () => clearTimeout(t)
  }, [round?.round_number, round?.category])

  const landedCat = round && !spinning ? CATEGORIES[round.category] : null

  return (
    <div
      className="relative mx-auto w-full"
      style={{
        // Skalar med föräldern på smala skärmar men växer aldrig större än `size`,
        // så hjulet + timern får plats sida vid sida på desktop och krymper på mobil.
        maxWidth: size,
        aspectRatio: '1 / 1',
        filter: landedCat
          ? `drop-shadow(0 0 26px ${landedCat.hex}) drop-shadow(0 0 8px ${landedCat.hex})`
          : 'drop-shadow(0 0 12px rgba(177,77,255,0.4))',
        transition: 'filter 0.4s ease',
      }}
    >
      <svg viewBox="0 0 240 240" width="100%" height="100%" className="block">
        {/* fasta kant-lampor */}
        {BULBS.map(([x, y], i) => (
          <circle
            key={i}
            cx={x}
            cy={y}
            r={2.4}
            fill={CATEGORIES[CATEGORY_ORDER[i % N]].hex}
            opacity={spinning ? 0.9 : 0.55}
          />
        ))}

        {/* roterande hjul */}
        <g
          style={{
            transformBox: 'view-box',
            transformOrigin: '120px 120px',
            transform: `rotate(${rotation}deg)`,
            transition: spinning
              ? `transform ${SPIN_MS}ms cubic-bezier(0.16, 0.9, 0.24, 1)`
              : 'none',
          }}
        >
          {CATEGORY_ORDER.map((key, i) => {
            const cat = CATEGORIES[key]
            const [lx, ly] = pointAt(i * SEG, LABEL_R)
            return (
              <g key={key}>
                <path d={slicePath(i * SEG)} fill={cat.hex} opacity="0.92" stroke="#0a0713" strokeWidth="2" />
                <path d={slicePath(i * SEG)} fill="url(#wheel-shade)" />
                <text
                  x={lx}
                  y={ly}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontFamily="Righteous, sans-serif"
                  fontSize="13"
                  fill="#0a0713"
                >
                  {cat.short}
                </text>
              </g>
            )
          })}

          {/* mitt-discokula */}
          <circle cx={CX} cy={CY} r="24" fill="url(#wheel-ball)" stroke="#0a0713" strokeWidth="2" />
          <g stroke="#2a1c47" strokeOpacity="0.5" strokeWidth="0.8" fill="none">
            <line x1={CX - 22} y1={CY} x2={CX + 22} y2={CY} />
            <line x1={CX} y1={CY - 22} x2={CX} y2={CY + 22} />
            <ellipse cx={CX} cy={CY} rx="11" ry="24" />
          </g>
          <circle cx={CX - 7} cy={CY - 8} r="3.5" fill="#fff" opacity="0.6" />
        </g>

        {/* fast pekare i toppen */}
        <path d="M120 6 L131 26 L109 26 Z" fill="#f4efff" stroke="#0a0713" strokeWidth="1.5" />

        <defs>
          <radialGradient id="wheel-shade" cx="50%" cy="50%" r="50%">
            <stop offset="55%" stopColor="#000" stopOpacity="0" />
            <stop offset="100%" stopColor="#000" stopOpacity="0.38" />
          </radialGradient>
          <radialGradient id="wheel-ball" cx="38%" cy="34%" r="72%">
            <stop offset="0%" stopColor="#ffffff" />
            <stop offset="45%" stopColor="#c9b6ff" />
            <stop offset="100%" stopColor="#3f2a6b" />
          </radialGradient>
        </defs>
      </svg>
    </div>
  )
}
