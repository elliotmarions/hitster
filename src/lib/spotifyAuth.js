// ============================================================
//  Spotify Authorization Code with PKCE (publik klient – ingen secret)
//  Körs helt i webbläsaren. Ger access_token + refresh_token.
// ============================================================

const CLIENT_ID = import.meta.env.VITE_SPOTIFY_CLIENT_ID

// Redirect-URI härleds från nuvarande origin, så det funkar både lokalt
// (http://127.0.0.1:5173/callback) och i produktion (https://…/callback).
// OBS: BÅDA måste registreras i Spotify-appens inställningar.
export const REDIRECT_URI = `${window.location.origin}/callback`

const SCOPES = [
  'streaming',
  'user-read-email',
  'user-read-private',
  'user-modify-playback-state',
  'user-read-playback-state',
].join(' ')

const TOKEN_KEY = 'hbo:spotify-token'
const VERIFIER_KEY = 'hbo:spotify-verifier'
const RETURN_KEY = 'hbo:spotify-return'

export const isSpotifyConfigured = Boolean(CLIENT_ID)

// --- PKCE-hjälpare ---
function randomString(len) {
  const bytes = new Uint8Array(len)
  crypto.getRandomValues(bytes)
  return Array.from(bytes, (b) => ('0' + b.toString(16)).slice(-2)).join('')
}
async function sha256Base64Url(input) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

// Startar inloggningen: skapar PKCE-verifier + challenge och skickar till Spotify.
export async function beginLogin() {
  if (!CLIENT_ID) throw new Error('VITE_SPOTIFY_CLIENT_ID saknas')
  const verifier = randomString(64)
  const challenge = await sha256Base64Url(verifier)
  sessionStorage.setItem(VERIFIER_KEY, verifier)
  // Kom ihåg var användaren var, så vi kan navigera tillbaka efter inloggning.
  sessionStorage.setItem(RETURN_KEY, window.location.pathname + window.location.search)

  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    response_type: 'code',
    redirect_uri: REDIRECT_URI,
    scope: SCOPES,
    code_challenge_method: 'S256',
    code_challenge: challenge,
  })
  window.location.href = `https://accounts.spotify.com/authorize?${params.toString()}`
}

export function getReturnPath() {
  const p = sessionStorage.getItem(RETURN_KEY) || '/'
  sessionStorage.removeItem(RETURN_KEY)
  return p
}

function storeToken(data) {
  const existing = getStored()
  const token = {
    access_token: data.access_token,
    // Spotify skickar inte alltid ny refresh_token vid refresh – behåll då den gamla.
    refresh_token: data.refresh_token || existing?.refresh_token || null,
    expires_at: Date.now() + (data.expires_in - 60) * 1000, // 60s marginal
  }
  localStorage.setItem(TOKEN_KEY, JSON.stringify(token))
}
function getStored() {
  try {
    return JSON.parse(localStorage.getItem(TOKEN_KEY))
  } catch {
    return null
  }
}

export function hasToken() {
  return Boolean(getStored()?.access_token)
}

// Byter auktoriseringskoden mot tokens (anropas på /callback).
export async function exchangeCode(code) {
  const verifier = sessionStorage.getItem(VERIFIER_KEY)
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    grant_type: 'authorization_code',
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier || '',
  })
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error('Token-utbyte misslyckades (' + res.status + ')')
  const data = await res.json()
  storeToken(data)
  sessionStorage.removeItem(VERIFIER_KEY)
  return data
}

// Ger en giltig access-token, förnyar automatiskt om den gått ut.
export async function getAccessToken() {
  const t = getStored()
  if (!t) return null
  if (Date.now() < t.expires_at) return t.access_token
  if (!t.refresh_token) {
    logout()
    return null
  }
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    grant_type: 'refresh_token',
    refresh_token: t.refresh_token,
  })
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) {
    logout()
    return null
  }
  const data = await res.json()
  storeToken(data)
  return data.access_token
}

export function logout() {
  localStorage.removeItem(TOKEN_KEY)
}

// Normaliserar en inklistrad låt (URI eller open.spotify.com-länk) till en track-URI.
export function normalizeTrackUri(input) {
  const s = (input || '').trim()
  if (/^spotify:track:[A-Za-z0-9]+$/.test(s)) return s
  const m = s.match(/track\/([A-Za-z0-9]+)/)
  return m ? `spotify:track:${m[1]}` : null
}
