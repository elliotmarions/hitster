// ============================================================
//  Auto-bedömning av ett svar mot facit (körs på klienten).
//  Deterministiskt → alla klienter får samma ✓/✗. Värden kan överstyra
//  (override_correct) om hen inte håller med.
// ============================================================

// Normalisera text: gemener, bort med parenteser/feat/remaster-svansar och
// skiljetecken, behåll bokstäver (även åäö/accenter) + siffror.
function norm(s) {
  return (s || '')
    .toLowerCase()
    .replace(/\(.*?\)/g, ' ')
    .replace(/\b(feat|ft|featuring|with)\b.*$/i, ' ')
    .replace(/[-–]\s*(remaster|remastered|mono|stereo|version|mix|edit|single|original|live|radio).*$/i, ' ')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

// Levenshtein-avstånd (litet, för tolerant stavning).
function levenshtein(a, b) {
  if (a === b) return 0
  if (!a.length) return b.length
  if (!b.length) return a.length
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i)
  for (let i = 0; i < a.length; i++) {
    let cur = [i + 1]
    for (let j = 0; j < b.length; j++) {
      const cost = a[i] === b[j] ? 0 : 1
      cur.push(Math.min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
    }
    for (let j = 0; j <= b.length; j++) prev[j] = cur[j]
  }
  return prev[b.length]
}

// Tolerant textmatchning för artist/titel.
function fuzzyText(answer, target) {
  const a = norm(answer)
  const t = norm(target)
  if (!a || !t) return false
  if (a === t) return true
  // Ett innehåller det andra (t.ex. "queen" i "queen david bowie").
  if (a.includes(t) || t.includes(a)) return true
  // Alla betydande ord i facit finns i svaret (ordföljd spelar ingen roll).
  const aTokens = new Set(a.split(' '))
  const tTokens = t.split(' ').filter((w) => w.length >= 2)
  if (tTokens.length && tTokens.every((w) => aTokens.has(w))) return true
  // Tolerant stavning: ett enstaka fel godkänns alltid, annars litet
  // Levenshtein-avstånd relativt längden.
  const dist = levenshtein(a, t)
  if (dist <= 1) return true
  const ratio = 1 - dist / Math.max(a.length, t.length)
  return ratio >= 0.8
}

// Plocka ut ett 4-siffrigt år (1900–2099) ur texten.
function yearIn(text) {
  const m = (text || '').match(/\b(19|20)\d{2}\b/)
  return m ? parseInt(m[0], 10) : null
}

// Plocka ut ett årtionde ur texten: "1985" → 1980, "80-tal"/"80-talet" → 1980.
function decadeIn(text) {
  const y = yearIn(text)
  if (y != null) return Math.floor(y / 10) * 10
  const m = (text || '').toLowerCase().match(/\b(\d0)\s*-?\s*tal/)
  if (m) {
    const d = parseInt(m[1], 10)
    return d >= 30 ? 1900 + d : 2000 + d // "30-tal"..".90-tal"→19xx, "00/10/20-tal"→20xx
  }
  return null
}

/**
 * Bedömer om ett svar är rätt för rundans kategori.
 * @param category  'exact_year' | 'approx_year' | 'decade' | 'artist' | 'title'
 * @param answer    lagets/spelarens fritextsvar
 * @param meta      facit { name, artist, year }
 * @returns boolean – true om rätt enligt auto-domen
 */
export function judgeAnswer(category, answer, meta) {
  if (!answer || !meta) return false
  const facitYear = parseInt(meta.year, 10)
  switch (category) {
    case 'exact_year':
      return yearIn(answer) === facitYear
    case 'approx_year': {
      const y = yearIn(answer)
      return y != null && Math.abs(y - facitYear) <= 3
    }
    case 'decade': {
      const d = decadeIn(answer)
      return d != null && !Number.isNaN(facitYear) && d === Math.floor(facitYear / 10) * 10
    }
    case 'artist':
      return fuzzyText(answer, meta.artist)
    case 'title':
      return fuzzyText(answer, meta.name)
    default:
      return false
  }
}
