import { useEffect, useState } from 'react'
import { exchangeCode, getReturnPath } from '../lib/spotifyAuth'
import DiscoBall from '../components/DiscoBall.jsx'

// Tar emot Spotifys redirect (?code=…), byter koden mot token och laddar om
// till där användaren var (full omladdning så SpotifyProvider startar med token).
export default function SpotifyCallback() {
  const [error, setError] = useState('')

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const code = params.get('code')
    const err = params.get('error')
    if (err) {
      setError(err)
      return
    }
    if (!code) {
      window.location.replace('/')
      return
    }
    exchangeCode(code)
      .then(() => window.location.replace(getReturnPath()))
      .catch((e) => setError(e.message))
  }, [])

  return (
    <div className="flex flex-col items-center gap-4 py-20 text-center">
      {error ? (
        <>
          <h2 className="text-2xl text-magenta">Spotify-kopplingen misslyckades</h2>
          <p className="text-muted">{error}</p>
          <a href="/" className="text-cyan underline">
            Till startsidan
          </a>
        </>
      ) : (
        <>
          <DiscoBall size={72} className="anim-spin-slow" />
          <p className="text-muted">Kopplar din Spotify…</p>
        </>
      )}
    </div>
  )
}
