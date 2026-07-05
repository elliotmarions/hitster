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
  const [deviceReady, setDeviceReady] = useState(false)
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
      const token = await getAccessToken()
      if (!token || !active) return
      const res = await fetch('https://api.spotify.com/v1/me', {
        headers: { Authorization: `Bearer ${token}` },
      })
      if (res.ok && active) setProfile(await res.json())
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
      player.addListener('not_ready', () => setDeviceReady(false))
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

  const disconnect = useCallback(() => {
    if (playerRef.current) {
      playerRef.current.disconnect()
      playerRef.current = null
    }
    logout()
    setConnected(false)
    setProfile(null)
    setDeviceReady(false)
    setCurrentTrack(null)
  }, [])

  // Överför uppspelning till vår SDK-enhet och spelar en track. (Fas 4 bygger den
  // SYNKADE starten ovanpå detta – här verifierar vi bara att SDK:n spelar alls.)
  const playTrack = useCallback(async (uri) => {
    setPlaybackError('')
    const token = await getAccessToken()
    const deviceId = deviceIdRef.current
    if (!token || !deviceId) throw new Error('Spelaren är inte redo än.')

    // 1. Flytta uppspelningen till vår enhet.
    await fetch('https://api.spotify.com/v1/me/player', {
      method: 'PUT',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_ids: [deviceId], play: false }),
    })
    // 2. Starta låten på enheten.
    const res = await fetch(
      `https://api.spotify.com/v1/me/player/play?device_id=${deviceId}`,
      {
        method: 'PUT',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ uris: [uri] }),
      },
    )
    if (!res.ok && res.status !== 204) {
      const txt = await res.text()
      throw new Error(`Kunde inte spela (${res.status}): ${txt.slice(0, 140)}`)
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
    currentTrack,
    paused,
    playbackError,
    connect,
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
