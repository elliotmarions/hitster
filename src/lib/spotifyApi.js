import { getAccessToken } from './spotifyAuth'

// Plockar ut spellist-id ur en URI (spotify:playlist:ID) eller länk
// (open.spotify.com/playlist/ID...).
export function parsePlaylistId(input) {
  const s = (input || '').trim()
  let m = s.match(/^spotify:playlist:([A-Za-z0-9]+)$/)
  if (m) return m[1]
  m = s.match(/playlist\/([A-Za-z0-9]+)/)
  return m ? m[1] : null
}

/**
 * Hämtar alla spelbara låtar ur en spellista med metadata som används för
 * facit: { uri, meta: { name, artist, year } }.
 * Kräver en giltig Spotify-token (värden är inloggad).
 */
export async function fetchPlaylistTracks(input) {
  const id = parsePlaylistId(input)
  if (!id) throw new Error('Ogiltig spellista – klistra in en Spotify-spellistas länk eller URI.')
  const token = await getAccessToken()
  if (!token) throw new Error('Spotify är inte kopplat.')

  const fields = 'next,items(track(uri,name,is_playable,artists(name),album(release_date)))'
  let url = `https://api.spotify.com/v1/playlists/${id}/tracks?limit=100&fields=${encodeURIComponent(fields)}`
  const out = []

  while (url) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
    if (!res.ok) throw new Error('Kunde inte hämta spellistan (' + res.status + ')')
    const data = await res.json()
    for (const item of data.items || []) {
      const t = item.track
      if (!t || !t.uri || t.is_playable === false) continue
      out.push({
        uri: t.uri,
        meta: {
          name: t.name,
          artist: (t.artists || []).map((a) => a.name).join(', '),
          year: (t.album?.release_date || '').slice(0, 4),
        },
      })
    }
    url = data.next
  }
  return out
}

// Fisher–Yates-blandning (ny kopia).
export function shuffle(arr) {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}
