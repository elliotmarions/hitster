// ============================================================
//  Preview-klipp via iTunes Search API (gratis, ingen inloggning).
//
//  Spelet behöver bara en ~30s-snutt att gissa på, inte hela låten. iTunes
//  Search returnerar en publik `previewUrl` (.m4a) som spelas i ett vanligt
//  <audio>-element hos ALLA spelare – ingen Spotify, ingen Premium, ingen
//  allowlist, funkar på mobil. iTunes svarar med CORS för vår origin, så
//  webbläsaren får anropa den direkt (ingen proxy behövs).
// ============================================================

// Normalisera bort brus i titlar (remaster, remix, feat…) för bättre träffar.
function cleanTitle(title) {
  return (title || '')
    .replace(/\s*[-–(].*?(remaster|remastered|mono|stereo|version|mix|edit|single|original|feat|ft|with).*$/i, '')
    .replace(/\s*\(.*?\)\s*$/, '')
    .trim()
}

/**
 * Slår upp en spelbar preview-URL för en låt (titel + artist).
 * Försöker först en snäv sökning, sen en bredare fallback.
 * Returnerar en https-URL till ett ljudklipp, eller null om inget hittas.
 */
export async function searchPreviewUrl(title, artist) {
  const attempts = [
    `${cleanTitle(title)} ${artist}`,
    `${title} ${artist}`,
    `${cleanTitle(title)}`,
  ]
  for (const term of attempts) {
    if (!term.trim()) continue
    try {
      const url =
        `https://itunes.apple.com/search?media=music&entity=song&limit=8&country=SE&term=` +
        encodeURIComponent(term)
      const res = await fetch(url)
      if (!res.ok) continue
      const data = await res.json()
      const artistLc = (artist || '').toLowerCase()
      // Föredra en träff där artistnamnet matchar; annars första med preview.
      const byArtist = data.results?.find(
        (r) => r.previewUrl && r.artistName?.toLowerCase().includes(artistLc.split(' ')[0]),
      )
      const anyHit = data.results?.find((r) => r.previewUrl)
      const hit = byArtist || anyHit
      if (hit?.previewUrl) return hit.previewUrl
    } catch {
      // prova nästa sökterm
    }
  }
  return null
}
