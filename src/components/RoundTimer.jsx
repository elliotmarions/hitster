// Synkad rund-timer. Alla klienter räknar från samma timer_start_at (serverns
// tidsstämpel) så nedräkningen är i synk. Presentationskomponent – GameView
// räknar ut `remaining` och skickar hit.
export default function RoundTimer({ remaining, total, color = '#22e6e6' }) {
  const RAD = 34
  const CIRC = 2 * Math.PI * RAD
  const frac = Math.max(0, Math.min(1, remaining / total))
  const secs = Math.max(0, Math.ceil(remaining))

  return (
    <svg width="88" height="88" viewBox="0 0 88 88" role="timer" aria-label={`${secs} sekunder kvar`}>
      <circle cx="44" cy="44" r={RAD} fill="none" stroke="#2c1e4d" strokeWidth="7" />
      <circle
        cx="44"
        cy="44"
        r={RAD}
        fill="none"
        stroke={color}
        strokeWidth="7"
        strokeLinecap="round"
        strokeDasharray={CIRC}
        strokeDashoffset={CIRC * (1 - frac)}
        transform="rotate(-90 44 44)"
        style={{ transition: 'stroke-dashoffset 0.25s linear', filter: `drop-shadow(0 0 6px ${color})` }}
      />
      <text
        x="44"
        y="45"
        textAnchor="middle"
        dominantBaseline="central"
        fontFamily="Righteous, sans-serif"
        fontSize="26"
        fill="#f4efff"
      >
        {secs}
      </text>
    </svg>
  )
}
