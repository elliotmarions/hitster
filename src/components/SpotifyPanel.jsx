import { useEffect, useState } from 'react'
import { useSpotify } from '../context/SpotifyContext.jsx'
import { normalizeTrackUri } from '../lib/spotifyAuth.js'
import { supabase } from '../lib/supabase.js'
import NeonButton from './ui/NeonButton.jsx'
import TextField from './ui/TextField.jsx'

const GREEN = '#1ed760'

/**
 * Fas 3-panelen: koppla din egen Spotify Premium och spela en testlåt lokalt
 * via Web Playback SDK. `playerId` (valfri) speglar anslutningsstatus till
 * players.spotify_connected så andra ser vem som är redo.
 */
export default function SpotifyPanel({ playerId, inGame = false }) {
  const {
    isConfigured,
    isMobile,
    connected,
    profile,
    isPremium,
    deviceReady,
    currentTrack,
    paused,
    playbackError,
    connect,
    disconnect,
    playTrack,
    togglePlay,
  } = useSpotify()

  const [track, setTrack] = useState('')
  const [busy, setBusy] = useState(false)
  const [localErr, setLocalErr] = useState('')

  // Spegla status till databasen så lobbyn kan visa vem som kopplat Spotify.
  useEffect(() => {
    if (!playerId) return
    supabase.from('players').update({ spotify_connected: deviceReady }).eq('id', playerId)
  }, [playerId, deviceReady])

  async function handlePlay() {
    setLocalErr('')
    const uri = normalizeTrackUri(track)
    if (!uri) {
      setLocalErr('Klistra in en giltig Spotify-låt (URI eller länk).')
      return
    }
    setBusy(true)
    try {
      await playTrack(uri)
    } catch (e) {
      setLocalErr(e.message)
    } finally {
      setBusy(false)
    }
  }

  const header = (
    <div className="flex items-center justify-between gap-2">
      <h2 className="flex items-center gap-2 font-display text-xl text-cream">
        <span style={{ color: GREEN }}>●</span> Spotify
      </h2>
      {connected && (
        <span className="chip" style={{ '--neon': deviceReady ? GREEN : '#9a8fbf' }}>
          {deviceReady ? 'Redo' : 'Ansluter…'}
        </span>
      )}
    </div>
  )

  if (!isConfigured) {
    return (
      <section className="panel p-6">
        {header}
        <p className="mt-3 text-sm text-muted">
          Spotify är inte konfigurerat än. Lägg <code>VITE_SPOTIFY_CLIENT_ID</code> i{' '}
          <code>.env.local</code> (se README) och starta om servern.
        </p>
      </section>
    )
  }

  if (isMobile) {
    return (
      <section className="panel p-6">
        {header}
        <p className="mt-3 text-sm text-muted">
          På mobil går det inte att spela musik <em>inne i appen</em> – Spotifys Web Playback
          SDK kräver dator. Du ser fortfarande spelplan och brickor här; starta låten i din egen
          Spotify-app vid nedräkningen (byggs i Fas 4).
        </p>
      </section>
    )
  }

  if (!connected) {
    return (
      <section className="panel p-6">
        {header}
        <p className="mt-3 text-sm text-muted">
          Koppla din egen Spotify <b className="text-cream">Premium</b> för att spela låtarna i
          appen. Kräver en <b className="text-cream">dator</b> (Chrome/Edge/Firefox/Safari).
        </p>
        <div className="mt-4">
          <NeonButton variant="outline" neon={GREEN} onClick={connect}>
            Koppla Spotify
          </NeonButton>
        </div>
      </section>
    )
  }

  return (
    <section className="panel p-6">
      {header}

      <div className="mt-3 flex items-center justify-between gap-3">
        <div className="min-w-0 text-sm">
          <p className="truncate text-cream">{profile?.display_name || 'Inloggad'}</p>
          {profile?.email && <p className="truncate text-xs text-muted">{profile.email}</p>}
        </div>
        <span className="chip shrink-0" style={{ '--neon': isPremium ? GREEN : '#ff4d9d' }}>
          {profile?.product ? (isPremium ? 'Premium' : profile.product) : '…'}
        </span>
      </div>

      {profile && !isPremium && (
        <p className="mt-3 text-sm text-magenta">
          Web Playback SDK kräver Premium – uppspelning i appen fungerar inte utan det.
        </p>
      )}

      {!inGame && (
        <div className="panel-inset mt-4 p-4">
          <p className="label mb-2">Testa uppspelning</p>
        <TextField
          placeholder="spotify:track:… eller open.spotify.com/track/…"
          value={track}
          onChange={(e) => setTrack(e.target.value)}
          hint="I Spotify: högerklicka en låt → Dela → Kopiera låtlänk."
        />
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <NeonButton variant="outline" neon={GREEN} onClick={handlePlay} disabled={!deviceReady || busy}>
            {busy ? 'Startar…' : 'Spela testlåt'}
          </NeonButton>
          {currentTrack && (
            <NeonButton variant="outline" neon="#22e6e6" onClick={togglePlay}>
              {paused ? 'Spela' : 'Paus'}
            </NeonButton>
          )}
        </div>

        {currentTrack && (
          <p className="mt-3 text-sm text-cream">
            ♪ {currentTrack.name} — {currentTrack.artists?.map((a) => a.name).join(', ')}
          </p>
        )}
        {!deviceReady && (
          <p className="mt-2 text-xs text-muted">Förbereder spelaren i din webbläsare…</p>
        )}
        </div>
      )}

      {(playbackError || localErr) && (
        <p className="mt-3 text-sm text-magenta">{playbackError || localErr}</p>
      )}

      <div className="mt-4">
        <NeonButton variant="ghost" onClick={disconnect}>
          Koppla från Spotify
        </NeonButton>
      </div>
    </section>
  )
}
