export default function TextField({ label, hint, className = '', ...props }) {
  return (
    <label className="block">
      {label && <span className="label mb-1.5 block">{label}</span>}
      <input className={`field ${className}`} {...props} />
      {hint && <span className="mt-1.5 block text-xs text-muted">{hint}</span>}
    </label>
  )
}
