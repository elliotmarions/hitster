import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react'
import {
  beginLogin,
  getAccessToken,
  getGrantedScopes,
  hasToken,
  isSpotifyConfigured,
  logout,
} from '../lib/spotifyAuth'

const SpotifyContext = createContext(null)

// Web Playback SDK fungerar INTE i mobila webbläsare – bara desktop (Chrome/Edge/Firefox/Safari).
const IS_MOBILE = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent)

// Laddar SDK-scriptet en gång. Spotify anropar en global callback när det är redo.
let sdkPromise = null
function loadSdk() {
  if (window.Spotify) return Promise.resolve()
  if (sdkPromise) return sdkPromise
  sdkPromise = new Promise((resolve) => {
    window.onSpotifyWebPlaybackSDKReady = () => resolve()
    const s = document.createElement('script')
    s.src = 'https://sdk.scdn.co/spotify-player.js'
    s.async = true
    document.body.appendChild(s)
  })
  return sdkPromise
}

export function SpotifyProvider({ children }) {
  const [connected, setConnected] = useState(() => hasToken())
  const [profile, setProfile] = useState(null) // { display_name, email, product }
  const [profileError, setProfileError] = useState('') // varför /v1/me inte kunde läsas
  const [deviceReady, setDeviceReady] = useState(false)
  // Har webbläsarens autoplay-spärr låsts upp via ett användarklick? Krävs för
  // att gäster (som startar låten via en realtidshändelse, inte ett eget klick)
  // ska höra ljud. Se activateAudio nedan.
  const [audioActivated, setAudioActivated] = useState(false)
  const [currentTrack, setCurrentTrack] = useState(null)
  const [paused, setPaused] = useState(true)
  const [playbackError, setPlaybackError] = useState('')

  const playerRef = useRef(null)
  const deviceIdRef = useRef(null)

  // Hämta profil (bl.a. product = premium/free) när man är ansluten.
  useEffect(() => {
    if (!connected) return
    let active = true
    ;(async () => {
      setProfileError('')
      const token = await getAccessToken()
      if (!active) return
      if (!token) {
        setProfileError('Ingen giltig token – koppla från och koppla Spotify igen.')
        return
      }
      try {
        const res = await fetch('https://api.spotify.com/v1/me', {
          headers: { Authorization: `Bearer ${token}` },
        })
        if (!active) return
        if (res.ok) {
          setProfile(await res.json())
        } else {
          const txt = await res.text()
          // 403 i Development Mode = kontot är inte tillagt i appens allowlist.
          const hint =
            res.status === 403
              ? ' – kontot är troligen inte tillagt i appens Spotify-allowlist (Development Mode).'
              : res.status === 401
                ? ' – token ogiltig, koppla Spotify igen.'
                : ''
          setProfileError(`Kunde inte läsa kontot (${res.status})${hint} ${txt.slice(0, 120)}`)
        }
      } catch (e) {
        if (active) setProfileError('Nätverksfel mot Spotify: ' + (e.message || 'okänt'))
      }
    })()
    return () => {
      active = false
    }
  }, [connected])

  // Skapa Web Playback-spelaren (bara desktop + ansluten).
  useEffect(() => {
    if (!connected || IS_MOBILE || !isSpotifyConfigured) return
    let cancelled = false

    loadSdk().then(() => {
      if (cancelled) return
      const player = new window.Spotify.Player({
        name: 'Hitster Bingo',
        getOAuthToken: async (cb) => {
          const t = await getAccessToken()
          if (t) cb(t)
        },
        volume: 0.7,
      })
      playerRef.current = player

      player.addListener('ready', ({ device_id }) => {
        deviceIdRef.current = device_id
        setDeviceReady(true)
        setPlaybackError('')
      })
      player.addListener('not_ready', () => {
        setDeviceReady(false)
        setAudioActivated(false)
      })
      player.addListener('player_state_changed', (state) => {
        if (!state) return
        setCurrentTrack(state.track_window?.current_track ?? null)
        setPaused(state.paused)
      })
      player.addListener('initialization_error', ({ message }) =>
        setPlaybackError('Init-fel: ' + message),
      )
      player.addListener('authentication_error', ({ message }) =>
        setPlaybackError('Autentiseringsfel: ' + message),
      )
      player.addListener('account_error', () =>
        setPlaybackError('Kontofel – Web Playback SDK kräver Spotify Premium.'),
      )
      player.addListener('playback_error', ({ message }) =>
        setPlaybackError('Uppspelningsfel: ' + message),
      )

      player.connect()
    })

    return () => {
      cancelled = true
      if (playerRef.current) {
        playerRef.current.disconnect()
        playerRef.current = null
      }
      deviceIdRef.current = null
      setDeviceReady(false)
    }
  }, [connected])

  const connect = useCallback(() => beginLogin(), [])

  // Låser upp webbläsarens autoplay – MÅSTE anropas synkront från ett
  // användarklick. Efter detta kan gäster höra låtar som startas automatiskt
  // (via realtidshändelsen) utan att själva klicka på play.
  const activateAudio = useCallback(async () => {
    try {
      await playerRef.current?.activateElement()
      setAudioActivated(true)
    } catch {
      // Vissa webbläsare saknar activateElement / kastar – markera ändå som
      // aktiverat eftersom klicket i sig räknas som användargest.
      setAudioActivated(true)
    }
  }, [])

  const disconnect = useCallback(() => {
    if (playerRef.current) {
      playerRef.current.disconnect()
      playerRef.current = null
    }
    logout()
    setConnected(false)
    setProfile(null)
    setDeviceReady(false)
    setAudioActivated(false)
    setCurrentTrack(null)
  }, [])

  // Överför uppspelning till vår SDK-enhet och spelar en track. (Fas 4 bygger den
  // SYNKADE starten ovanpå detta – här verifierar vi bara att SDK:n spelar alls.)
  const playTrack = useCallback(async (uri) => {
    setPlaybackError('')
    const token = await getAccessToken()
    const deviceId = deviceIdRef.current
    if (!token || !deviceId) {
      const msg = 'Spelaren är inte redo än (ingen enhet).'
      setPlaybackError(msg)
      throw new Error(msg)
    }

    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }

    // 1. Flytta uppspelningen till vår enhet.
    await fetch('https://api.spotify.com/v1/me/player', {
      method: 'PUT',
      headers: auth,
      body: JSON.stringify({ device_ids: [deviceId], play: false }),
    })

    // 2. Starta låten på enheten. Precis efter en enhetsöverföring hinner Spotify
    //    ibland inte se enheten än (404 "Device not found") → en kort retry.
    async function play() {
      return fetch(`https://api.spotify.com/v1/me/player/play?device_id=${deviceId}`, {
        method: 'PUT',
        headers: auth,
        body: JSON.stringify({ uris: [uri] }),
      })
    }
    let res = await play()
    if (res.status === 404) {
      await new Promise((r) => setTimeout(r, 600))
      res = await play()
    }
    if (!res.ok && res.status !== 204) {
      const txt = await res.text()
      const msg = `Kunde inte spela (${res.status}): ${txt.slice(0, 160)}`
      setPlaybackError(msg)
      throw new Error(msg)
    }
  }, [])

  const togglePlay = useCallback(() => {
    playerRef.current?.togglePlay()
  }, [])

  const pause = useCallback(() => {
    playerRef.current?.pause()
  }, [])

  const value = {
    isConfigured: isSpotifyConfigured,
    isMobile: IS_MOBILE,
    connected,
    profile,
    isPremium: profile?.product === 'premium',
    grantedScopes: connected ? getGrantedScopes() : '',
    deviceReady,
    audioActivated,
    currentTrack,
    paused,
    playbackError,
    profileError,
    connect,
    activateAudio,
    disconnect,
    playTrack,
    togglePlay,
    pause,
  }

  return <SpotifyContext.Provider value={value}>{children}</SpotifyContext.Provider>
}

export function useSpotify() {
  const ctx = useContext(SpotifyContext)
  if (!ctx) throw new Error('useSpotify måste användas inuti <SpotifyProvider>')
  return ctx
}
