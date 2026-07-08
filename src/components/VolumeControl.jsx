import { useEffect, useRef, useState } from 'react'

/**
 * Kompakt volymkontroll: en liten ljudikon (i ett hörn) som öppnar en liten
 * meny med reglaget. Volymen är lokal per spelare (se useSyncedAudio).
 *
 * Props: volume (0–1), setVolume(v).
 */
export default function VolumeControl({ volume, setVolume }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const volBeforeMute = useRef(volume > 0 ? volume : 1)

  // Stäng menyn vid klick utanför.
  useEffect(() => {
    if (!open) return
    const onDoc = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('pointerdown', onDoc)
    return () => document.removeEventListener('pointerdown', onDoc)
  }, [open])

  const pct = Math.round(volume * 100)
  const icon = volume === 0 ? '🔇' : volume < 0.5 ? '🔉' : '🔊'
  const toggleMute = () => {
    if (volume > 0) {
      volBeforeMute.current = volume
      setVolume(0)
    } else {
      setVolume(volBeforeMute.current || 1)
    }
  }

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex h-9 w-9 items-center justify-center rounded-full text-lg leading-none transition-colors"
        style={{
          background: open ? 'rgba(34,230,230,0.15)' : 'rgba(244,239,255,0.06)',
          border: `1px solid ${open ? 'rgba(34,230,230,0.5)' : 'rgba(244,239,255,0.15)'}`,
        }}
        aria-label="Justera volym"
        aria-expanded={open}
        title="Volym"
      >
        {icon}
      </button>

      {open && (
        <div className="panel absolute right-0 top-11 z-30 flex w-56 items-center gap-2.5 p-3">
          <button
            type="button"
            onClick={toggleMute}
            className="text-lg leading-none"
            aria-label={volume > 0 ? 'Stäng av ljudet' : 'Slå på ljudet'}
            title={volume > 0 ? 'Stäng av ljudet' : 'Slå på ljudet'}
          >
            {icon}
          </button>
          <input
            type="range"
            min="0"
            max="100"
            value={pct}
            onChange={(e) => {
              const v = Number(e.target.value) / 100
              if (v > 0) volBeforeMute.current = v
              setVolume(v)
            }}
            className="h-1.5 flex-1 cursor-pointer"
            style={{ accentColor: '#22e6e6' }}
            aria-label="Volym"
          />
          <span className="w-9 text-right text-xs tabular-nums text-muted">{pct}%</span>
        </div>
      )}
    </div>
  )
}
