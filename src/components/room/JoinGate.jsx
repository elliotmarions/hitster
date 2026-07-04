import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../context/AuthContext.jsx'
import { joinRoom } from '../../lib/rooms.js'
import NeonButton from '../ui/NeonButton.jsx'
import TextField from '../ui/TextField.jsx'

// Visas när man öppnar en rumslänk utan att vara medlem ännu.
export default function JoinGate({ code, onJoined }) {
  const { preferredName, setPreferredName } = useAuth()
  const [name, setName] = useState(preferredName)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  async function submit(e) {
    e.preventDefault()
    setErr('')
    if (!name.trim()) return setErr('Skriv ditt visningsnamn.')
    setBusy(true)
    try {
      setPreferredName(name.trim())
      await joinRoom({ code, displayName: name })
      await onJoined()
    } catch (e2) {
      setErr(
        /not found|hittades|finns/i.test(e2.message)
          ? 'Hittade inget rum med den koden.'
          : e2.message,
      )
      setBusy(false)
    }
  }

  return (
    <form onSubmit={submit} className="panel mx-auto max-w-md p-6 sm:p-8">
      <p className="label">Gå med i rum</p>
      <div className="code-badge mt-2 inline-block px-4 py-2 text-2xl">{code}</div>
      <p className="mt-4 text-sm text-muted">Skriv ditt namn så hoppar du in i rummet.</p>
      <div className="mt-4">
        <TextField
          label="Ditt visningsnamn"
          placeholder="t.ex. Discokungen"
          maxLength={24}
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
      </div>
      {err && <p className="mt-3 text-sm text-magenta">{err}</p>}
      <div className="mt-5 flex gap-3">
        <NeonButton type="submit" disabled={busy}>
          {busy ? 'Ansluter…' : 'Gå med'}
        </NeonButton>
        <Link to="/" className="btn btn-ghost">
          Avbryt
        </Link>
      </div>
    </form>
  )
}
