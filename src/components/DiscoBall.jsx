/**
 * Dekorativ discokula (SVG). Ren pynt/identitet – detta är INTE spelets
 * snurrande kula (den byggs i Fas 2). De färgade facetterna använder
 * kategorifärgerna så temat hänger ihop.
 */
export default function DiscoBall({ size = 120, className = '' }) {
  return (
    <svg
      width={size}
      height={size * 1.2}
      viewBox="0 0 120 144"
      className={className}
      role="img"
      aria-label="Discokula"
    >
      <defs>
        <radialGradient id="db-face" cx="38%" cy="32%" r="74%">
          <stop offset="0%" stopColor="#ffffff" />
          <stop offset="42%" stopColor="#d7c8ff" />
          <stop offset="100%" stopColor="#3f2a6b" />
        </radialGradient>
        <radialGradient id="db-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#b14dff" stopOpacity="0.55" />
          <stop offset="100%" stopColor="#b14dff" stopOpacity="0" />
        </radialGradient>
        <pattern id="db-facets" width="11" height="11" patternUnits="userSpaceOnUse">
          <rect x="0.8" y="0.8" width="9.4" height="9.4" rx="1.4" fill="#ffffff" opacity="0.07" />
        </pattern>
        <clipPath id="db-clip">
          <circle cx="60" cy="76" r="46" />
        </clipPath>
      </defs>

      {/* upphängning */}
      <line x1="60" y1="6" x2="60" y2="30" stroke="#6b5a9c" strokeWidth="2" />
      <circle cx="60" cy="7" r="3" fill="#9a8fbf" />
      <rect x="52" y="26" width="16" height="7" rx="2" fill="#3a2b63" />

      {/* glöd bakom kulan */}
      <circle cx="60" cy="76" r="60" fill="url(#db-glow)" />

      {/* själva klotet */}
      <circle cx="60" cy="76" r="46" fill="url(#db-face)" />

      <g clipPath="url(#db-clip)">
        {/* fasta longitud-/latitudlinjer */}
        <g stroke="#2a1c47" strokeOpacity="0.45" strokeWidth="1" fill="none">
          <ellipse cx="60" cy="76" rx="15" ry="46" />
          <ellipse cx="60" cy="76" rx="31" ry="46" />
          <line x1="14" y1="60" x2="106" y2="60" />
          <line x1="14" y1="76" x2="106" y2="76" />
          <line x1="14" y1="92" x2="106" y2="92" />
        </g>

        {/* facetter + lysande kategori-flisor som snurrar långsamt */}
        <g className="anim-spin-slow" style={{ transformOrigin: '60px 76px' }}>
          <rect x="14" y="30" width="92" height="92" fill="url(#db-facets)" />
          <rect x="37" y="51" width="8.5" height="8.5" rx="1.4" fill="#22e6e6" opacity="0.9" />
          <rect x="66" y="60" width="8.5" height="8.5" rx="1.4" fill="#ff2e9a" opacity="0.9" />
          <rect x="52" y="86" width="8.5" height="8.5" rx="1.4" fill="#b6ff3c" opacity="0.85" />
          <rect x="73" y="78" width="8.5" height="8.5" rx="1.4" fill="#ffc93c" opacity="0.9" />
          <rect x="44" y="72" width="8.5" height="8.5" rx="1.4" fill="#ffffff" opacity="0.5" />
        </g>
      </g>

      {/* fast highlight ovanpå */}
      <ellipse cx="47" cy="60" rx="14" ry="10" fill="#ffffff" opacity="0.28" />
      <circle cx="60" cy="76" r="46" fill="none" stroke="#ffffff" strokeOpacity="0.14" />
    </svg>
  )
}
