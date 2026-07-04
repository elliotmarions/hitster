import { useState } from 'react'
import NeonButton from './NeonButton.jsx'

export default function CopyButton({ value, label, neon = '#22e6e6' }) {
  const [done, setDone] = useState(false)
  async function copy() {
    try {
      await navigator.clipboard.writeText(value)
      setDone(true)
      setTimeout(() => setDone(false), 1600)
    } catch {
      /* clipboard kan vara blockerad – ignorera tyst */
    }
  }
  return (
    <NeonButton type="button" variant="outline" neon={done ? '#b6ff3c' : neon} onClick={copy}>
      {done ? 'Kopierat!' : label}
    </NeonButton>
  )
}
