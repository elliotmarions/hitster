/**
 * Taktil neonknapp. variant: 'primary' | 'outline' | 'ghost'.
 * För 'outline' kan man skicka en neonfärg (t.ex. en kategorifärg) via `neon`.
 */
export default function NeonButton({
  variant = 'primary',
  neon,
  className = '',
  style,
  children,
  ...props
}) {
  const variantClass =
    variant === 'outline'
      ? 'btn-outline'
      : variant === 'ghost'
        ? 'btn-ghost'
        : 'btn-primary'

  const mergedStyle = neon ? { ...style, '--neon': neon } : style

  return (
    <button className={`btn ${variantClass} ${className}`} style={mergedStyle} {...props}>
      {children}
    </button>
  )
}
