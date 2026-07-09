/**
 * Sveriges flagga som inline-SVG. Emojin 🇸🇪 renderas inte som flagga på alla
 * plattformar (t.ex. Windows/Chrome visar "SE") – den här ser likadan ut överallt.
 * Proportioner enligt flagglagen (16:10, kors 5:2:9 / 4:2:4).
 */
export default function SwedishFlag({ size = 18, className = '' }) {
  return (
    <svg
      viewBox="0 0 16 10"
      width={size}
      height={(size * 10) / 16}
      className={className}
      role="img"
      aria-label="Svenska"
      style={{ borderRadius: 2, display: 'inline-block', verticalAlign: 'middle', flexShrink: 0 }}
    >
      <rect width="16" height="10" fill="#006AA7" />
      <rect x="5" width="2" height="10" fill="#FECC00" />
      <rect y="4" width="16" height="2" fill="#FECC00" />
    </svg>
  )
}
