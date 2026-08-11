// Prövar årtal mot MusicBrainz och Discogs.
//
// Pottens år är LISTÅRET – året låten var hit – eftersom potten byggdes ur
// Sverigetopplistans veckoarkiv. En källa som daterar SLÄPPET ligger därför
// ofta ett år före, och det är väntat. Två år eller mer, eller en källa som
// säger SENARE än vårt (låten kan inte ha varit hit innan den fanns), är det
// som är värt att titta på.
//
// Användning:
//   node scripts/check-years.mjs latar.json
//
// Infilen är en lista av [titel, artist, år, ...] eller objekt med titel /
// artist / ar. Ut kommer en rapport och latar.years.json.
//
// INGÅNGEN AVGÖR SVARET, och båda tjänsterna har en fälla:
//
//   MUSICBRAINZ. first-release-date på INSPELNING pekar på tidigaste utgåva
//   MB känner för just den inspelningsentiteten – för 50- och 60-tal nästan
//   alltid en samling. "Mona Lisa" blir 1986, "Cry" 1972. Release-group av
//   typen SINGLE daterar däremot singelsläppet. Provkört mot tio låtar med
//   känt facit: singel-ingången 8 exakt rätt, inspelnings-ingången 2.
//
//   DISCOGS. Söker man utan formatfilter får man samlingar och nypressningar.
//   Filtrera till 7"/Single och läs land + etikett, inte bara årtal.
//
// OCH VIKTIGAST: ett avvikande årtal betyder inget i sig. Kör alltid
// --detalj på avvikarna – där syns skillnaden mellan "källan känner bara en
// återutgåva" (vårt år står sig) och "originalpressningen ligger där och
// säger något annat" (vårt år är fel). Av 42 avvikelser i 0080 och 0081 var
// 32 återutgåvor.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'

const infil = process.argv[2]
const detalj = process.argv.includes('--detalj')
if (!infil) {
  console.error('✗ Ange fil, t.ex.: node scripts/check-years.mjs latar.json [--detalj]')
  process.exit(1)
}
const LOGG = infil.replace(/\.json$/, '') + '.years.jsonl'
const MB_UA = 'latsnurran-pool-check/1.0 ( https://github.com/elliotmarions/hitster )'
const DC_UA = 'latsnurran-pool-check/1.0 +https://github.com/elliotmarions/hitster'

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const norm = (t) =>
  String(t ?? '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/g, ' ').trim()
const cleanTitle = (t) =>
  String(t ?? '')
    .replace(/\s*[-–(].*?(remaster|remastered|mono|stereo|version|mix|edit|single|original|feat|ft|with).*$/i, '')
    .replace(/\s*\(.*?\)\s*$/, '')
    .trim()
const huvudartist = (a) =>
  String(a ?? '').replace(/\s*(?:feat\.?|ft\.?|with|vs\.?)\s.*$/i, '').replace(/\s*[,&/(].*$/, '').trim()
const lucene = (s) => String(s).replace(/["\\]/g, ' ').trim()
const arAv = (d) => { const y = Number(String(d ?? '').slice(0, 4)); return y >= 1900 && y <= 2030 ? y : null }

async function json(url, headers, forsok = 0) {
  try {
    const res = await fetch(url, { headers, signal: AbortSignal.timeout(20000) })
    if (res.status === 503 || res.status === 429) {
      if (forsok >= 5) return null
      await sleep(10000 * (forsok + 1))
      return json(url, headers, forsok + 1)
    }
    if (!res.ok) return null
    return await res.json()
  } catch {
    if (forsok >= 3) return null
    await sleep(3000 * (forsok + 1))
    return json(url, headers, forsok + 1)
  }
}

// --- MusicBrainz: tidigaste SINGELN (1 anrop/sekund) ------------------
async function mbAr(titel, artist) {
  const a = huvudartist(artist)
  for (const t of [...new Set([cleanTitle(titel), titel])]) {
    const q = `releasegroup:"${lucene(t)}" AND artist:"${lucene(a)}" AND primarytype:Single`
    const j = await json(
      `https://musicbrainz.org/ws/2/release-group?query=${encodeURIComponent(q)}&fmt=json&limit=25`,
      { 'User-Agent': MB_UA, Accept: 'application/json' },
    )
    const nt = norm(t)
    const ar = (j?.['release-groups'] ?? [])
      .filter((g) => norm(g.title) === nt || norm(g.title).startsWith(nt + ' '))
      .filter((g) => norm((g['artist-credit'] ?? []).map((c) => c.name).join(' ')).includes(norm(a)))
      .map((g) => arAv(g['first-release-date'])).filter(Boolean)
    await sleep(1100)
    if (ar.length) return Math.min(...ar)
  }
  return null
}

// --- Discogs: tidigaste 7"/singeln (25 anrop/minut) -------------------
const arSingel = (r) => (r.format ?? []).some((f) => /7"|Single|45 RPM/i.test(f))

async function dcSok(params) {
  return json(
    'https://api.discogs.com/database/search?' +
      new URLSearchParams({ ...params, type: 'release', per_page: '100' }),
    { 'User-Agent': DC_UA },
  )
}

async function dcAr(titel, artist) {
  const a = huvudartist(artist)
  let j = await dcSok({ artist: a, release_title: titel })
  await sleep(2600)
  let ar = (j?.results ?? []).filter(arSingel).map((r) => arAv(r.year)).filter(Boolean)
  if (ar.length) return { ar: Math.min(...ar), kalla: 'singel', antal: ar.length }

  // Albumspår har ingen singel – sök på spåret i stället.
  j = await dcSok({ artist: a, track: titel })
  await sleep(2600)
  ar = (j?.results ?? []).map((r) => arAv(r.year)).filter(Boolean)
  if (ar.length) return { ar: Math.min(...ar), kalla: 'spår', antal: ar.length }
  return { ar: null, kalla: null, antal: 0 }
}

// Pressningarna bakom siffran: det som skiljer återutgåva från original.
async function dcPressningar(titel, artist) {
  const j = await dcSok({ artist: huvudartist(artist), release_title: titel })
  await sleep(2600)
  const perAr = {}
  for (const r of (j?.results ?? []).filter(arSingel)) {
    const y = arAv(r.year)
    if (y) (perAr[y] ??= []).push(`${r.country ?? '?'}/${(r.label ?? [])[0] ?? '?'}`)
  }
  return perAr
}

// --- kör -------------------------------------------------------------
const latar = JSON.parse(readFileSync(infil, 'utf8')).map((k) =>
  Array.isArray(k) ? { titel: k[0], artist: k[1], ar: k[2] } : k,
)

const klara = new Map()
if (existsSync(LOGG)) {
  for (const rad of readFileSync(LOGG, 'utf8').split('\n')) {
    if (!rad.trim()) continue
    const o = JSON.parse(rad)
    klara.set(o.titel + '|' + o.artist, o)
  }
  console.log(`${klara.size} redan kollade\n`)
}

const ut = []
for (let i = 0; i < latar.length; i++) {
  const k = latar[i]
  const nyckel = k.titel + '|' + k.artist
  if (klara.has(nyckel)) { ut.push(klara.get(nyckel)); continue }

  const mb = await mbAr(k.titel, k.artist)
  // Discogs bara när MB inte räckte – den är långsammare.
  const dc = mb === null ? await dcAr(k.titel, k.artist) : { ar: null, kalla: null, antal: 0 }

  const o = { titel: k.titel, artist: k.artist, ar: k.ar, mbAr: mb, dcAr: dc.ar, kalla: dc.kalla, antal: dc.antal }
  appendFileSync(LOGG, JSON.stringify(o) + '\n', 'utf8')
  ut.push(o)

  const kallaAr = mb ?? dc.ar
  const d = kallaAr === null ? null : kallaAr - k.ar
  const flagga = d === null ? '?' : d === 0 ? 'ok' : d === -1 ? '-1' : `${d > 0 ? '+' : ''}${d} GRANSKA`
  console.log(
    `${String(i + 1).padStart(3)}/${latar.length} ${String(flagga).padEnd(10)} ${k.ar} ${k.artist} – ${k.titel}` +
      (kallaAr && kallaAr !== k.ar ? `  (${mb ? 'MB' : 'Discogs'} ${kallaAr})` : ''),
  )
}

writeFileSync(infil.replace(/\.json$/, '') + '.years.json', JSON.stringify(ut, null, 1), 'utf8')

const kalla = (r) => r.mbAr ?? r.dcAr
const utan = ut.filter((r) => kalla(r) === null)
const lika = ut.filter((r) => kalla(r) === r.ar)
const ettFore = ut.filter((r) => kalla(r) !== null && r.ar - kalla(r) === 1)
const granska = ut.filter((r) => kalla(r) !== null && (r.ar - kalla(r) >= 2 || kalla(r) > r.ar))

console.log(`\n===== ${ut.length} låtar =====`)
console.log(`  ${lika.length} samma år, ${ettFore.length} källan ett år före → ${lika.length + ettFore.length} bekräftade`)
console.log(`  ${granska.length} att granska, ${utan.length} utan svar`)

console.log('\n--- ATT GRANSKA ---')
for (const r of granska.sort((a, b) => Math.abs(b.ar - kalla(b)) - Math.abs(a.ar - kalla(a)))) {
  console.log(`  ${r.ar} -> ${kalla(r)}  ${r.artist} – ${r.titel}`)
  if (detalj) {
    const perAr = await dcPressningar(r.titel, r.artist)
    const y = Object.keys(perAr).sort()
    if (!y.length) console.log('      inga daterade singlar hos Discogs → källan känner bara återutgåvor')
    for (const a of y.slice(0, 5)) {
      console.log(`      ${a}  ${String(perAr[a].length).padStart(2)} st  ${[...new Set(perAr[a])].slice(0, 3).join(' | ')}`)
    }
  }
}

console.log('\n--- UTAN SVAR ---')
for (const r of utan) console.log(`  ${r.ar} ${r.artist} – ${r.titel}`)
if (!detalj && granska.length) {
  console.log('\nKör om med --detalj för att se pressningarna bakom avvikelserna.')
}
