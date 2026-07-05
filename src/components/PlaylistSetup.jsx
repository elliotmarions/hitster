import { useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { parsePlaylistId } from '../lib/spotifyApi.js'
import NeonButton from './ui/NeonButton.jsx'
import TextField from './ui/TextField.jsx'

// Värden väljer en Spotify-spellista för rummet (Läge A). Sparas på rooms.playlist_uri;
// värdens klient hämtar + blandar låtarna och delar ut en per snurr (se useTrackQueue).
export default function PlaylistSetup({ room, isHost }) {
  const [value, setValue] = useState(room.playlist_uri || '')
  const [saved, setSaved] = useState(false)
  const [err, setErr] = useState('')

  if (!isHost) {
    return (
      <p className="text-sm text-muted">
        {room.playlist_uri
          ? '🎵 Värden har valt en spellista.'
          : 'Väntar på att värden väljer en spellista…'}
      </p>
    )
  }

  async function save() {
    setErr('')
    setSaved(false)
    if (!parsePlaylistId(value)) {
      setErr('Klistra in en giltig Spotify-spellistlänk eller -URI.')
      return
    }
    const { error } = await supabase
      .from('rooms')
      .update({ playlist_uri: value.trim() })
      .eq('id', room.id)
    if (error) setErr(error.message)
    else setSaved(true)
  }

  return (
    <div>
      <TextField
        label="Spotify-spellista (värden)"
        placeholder="open.spotify.com/playlist/… eller spotify:playlist:…"
        value={value}
        onChange={(e) => {
          setValue(e.target.value)
          setSaved(false)
        }}
        hint="Appen blandar låtarna och delar ut en per runda."
      />
      <div className="mt-3 flex items-center gap-3">
        <NeonButton variant="outline" neon="#1ed760" onClick={save}>
          Spara spellista
        </NeonButton>
        {saved && <span className="text-sm text-lime">Sparad ✓</span>}
        {room.playlist_uri && !saved && (
          <span className="text-xs text-muted">En spellista är sparad</span>
        )}
      </div>
      {err && <p className="mt-2 text-sm text-magenta">{err}</p>}
    </div>
  )
}
