import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import NeonButton from './NeonButton.jsx'

/**
 * Bekräftelseruta för handlingar som inte går att ångra.
 *
 * Samma overlay-recept som resten av appen: portal till <body>, explicit höjd
 * i dvh och INGEN backdrop-filter – den senare gav ett eget kompositeringslager
 * som Chrome klippte, så en remsa längst ned blev omålad.
 */
export default function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = 'Ja',
  cancelLabel = 'Avbryt',
  neon = '#ff2e9a',
  busy = false,
  onConfirm,
  onCancel,
}) {
  const cancelRef = useRef(null)

  // Esc avbryter. Fokus landar på Avbryt så ett råkat Enter inte lämnar rummet.
  useEffect(() => {
    if (!open) return
    const onKey = (e) => {
      if (e.key === 'Escape') onCancel()
    }
    window.addEventListener('keydown', onKey)
    cancelRef.current?.focus()
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onCancel])

  if (!open) return null

  return createPortal(
    <div
      className="fixed left-0 top-0 z-50 m-0 flex w-full items-center justify-center p-4"
      style={{ height: '100dvh', background: 'rgba(10,7,19,0.86)' }}
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) onCancel()
      }}
    >
      <div
        className="panel w-full max-w-sm p-6 text-center"
        style={{ borderColor: neon, boxShadow: `0 0 44px -12px ${neon}` }}
      >
        <h2 id="confirm-title" className="font-display text-2xl text-cream">
          {title}
        </h2>
        {message && <p className="mt-2 text-sm text-muted">{message}</p>}
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-center">
          <NeonButton ref={cancelRef} variant="ghost" onClick={onCancel} disabled={busy}>
            {cancelLabel}
          </NeonButton>
          <NeonButton neon={neon} onClick={onConfirm} disabled={busy}>
            {busy ? 'Lämnar…' : confirmLabel}
          </NeonButton>
        </div>
      </div>
    </div>,
    document.body,
  )
}
