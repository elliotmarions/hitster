// Prövar om låtar går att SPELA innan de läggs i potten.
//
// Kör varje kandidat genom exakt den kedja spelet använder vid låtstart:
// _clean_title -> _itunes_search_url -> _itunes_pick, och vid miss ett andra
// försök på råtiteln (search_stage 2). Reglerna nedan är portade rakt av ur
// migrationerna och MÅSTE följa med om de ändras där – annars godkänner det
// här skriptet låtar som servern sedan inte hittar.
//
//   _clean_title        0024
//   _norm_title         0062
//   _itunes_search_url  0065  (limit 8, country=SE)
//   _itunes_pick        0068
//
// Användning:
//   node scripts/check-playable.mjs kandidater.json [utfil.json]
//
// Infilen är en lista av [titel, artist, år, sv, genre] eller objekt med
// samma fält. Utfilen får bara de spelbara, med preview_url och spår-id
// klara att lägga i en insert-migration.
//
// TRE FÄLLOR, alla dyrköpta:
//
//   1. APPLE STRYPER. En körning på 420 låtar gav 966 strypningar, och en
//      strypning ser i loggen ut precis som "låten finns inte". 67 låtar såg
//      ut att saknas – Help!, Good Vibrations, Stand by Me. Skriptet skiljer
//      därför på strypt och obesvarad, och missar ska ALLTID köras om i
//      lugnare takt innan de tros på.
//
//   2. FETCH UTAN TIMEOUT HÄNGER. En död anslutning stoppade en hel körning
//      i tio minuter utan ett tecken. AbortSignal.timeout finns därför på
//      varje anrop, precis som net.http_get har sin.
//
//   3. ARTISTNAMNET MÅSTE VARA APPLES. _itunes_pick kräver första ordet ur
//      pottens artistnamn som eget ord i Apples artistName. "The Jackson 5"
//      faller på ordet "the" när Apple skriver "Jackson 5" – inte direkt,
//      för URL:en är cachad, utan den dag raden söks om. Skriptet provar
//      därför namnet både med och utan inledande "The" och rapporterar
//      vilken form som träffade.
//
// Loggen (kandidater.progress.jsonl) gör körningen återupptagbar: avbryts
// den tas den vid där den slutade i stället för att börja om mot Apple.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'

const infil = process.argv[2]
const utfil = process.argv[3] ?? infil.replace(/\.json$/, '') + '.playable.json'
if (!infil) {
  console.error('✗ Ange kandidatfil, t.ex.: node scripts/check-playable.mjs kandidater.json')
  process.exit(1)
}
const LOGG = infil.replace(/\.json$/, '') + '.progress.jsonl'

// --- serverns hjälpfunktioner ----------------------------------------
const cleanTitle = (t) =>
  String(t ?? '')
    .replace(
      /\s*[-–(].*?(remaster|remastered|mono|stereo|version|mix|edit|single|original|feat|ft|with).*$/i,
      '',
    )
    .replace(/\s*\(.*?\)\s*$/, '')
    .trim()

const normTitle = (t) =>
  String(t ?? '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()

const JUNK_TN =
  /\b(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\b/
const JUNK_CN =
  /\b(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\b/

// _itunes_pick: bästa godkända träffen, annars null.
function itunesPick(results, title, artist) {
  const word = normTitle(artist).split(' ')[0] || normTitle(artist)
  const clean = cleanTitle(title).toLowerCase()
  const ntitle = normTitle(cleanTitle(title))
  if (!ntitle) return null
  return (
    results
      .filter((r) => (r.previewUrl ?? '').startsWith('https://'))
      .map((r) => ({
        r,
        tn: (r.trackName ?? '').toLowerCase(),
        cn: (r.collectionName ?? '').toLowerCase(),
        ntn: normTitle(r.trackName),
        nan: normTitle(r.artistName),
      }))
      .filter((x) => word === '' || ` ${x.nan} `.includes(` ${word} `))
      .filter((x) => !JUNK_CN.test(x.cn))
      .filter((x) => x.tn === clean || !JUNK_TN.test(x.tn))
      .filter(
        (x) => x.ntn === ntitle || x.ntn.startsWith(ntitle + ' ') || ntitle.startsWith(x.ntn + ' '),
      )
      .sort((a, b) => {
        const rang = (x) => (x.ntn === ntitle ? 0 : x.ntn.startsWith(ntitle + ' ') ? 1 : 2)
        return rang(a) - rang(b) || a.tn.length - b.tn.length
      })[0] ?? null
  )
}

// --- iTunes ----------------------------------------------------------
const sok = (term) =>
  'https://itunes.apple.com/search?media=music&entity=song&limit=8&country=SE&term=' +
  encodeURIComponent(term)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// {json} eller {strypt:true}. Skillnaden är hela poängen – se fälla 1.
async function hamta(url, forsok = 0) {
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'latsnurran-pool-check' },
      signal: AbortSignal.timeout(15000),
    })
    if (res.status === 403 || res.status === 429) {
      if (forsok >= 5) return { strypt: true }
      await sleep(8000 * (forsok + 1))
      return hamta(url, forsok + 1)
    }
    if (!res.ok) return { strypt: true }
    return { json: await res.json() }
  } catch {
    if (forsok >= 3) return { strypt: true }
    await sleep(3000 * (forsok + 1))
    return hamta(url, forsok + 1)
  }
}

// Ett försök: städad titel först, sedan råtiteln – som servern gör.
async function prova(titel, artist) {
  for (const t of [...new Set([cleanTitle(titel), titel])]) {
    const svar = await hamta(sok(`${t} ${artist}`))
    if (svar.strypt) return { strypt: true }
    const p = itunesPick(svar.json?.results ?? [], titel, artist)
    if (p) return { pick: p }
    await sleep(200)
  }
  return {}
}

// --- kör -------------------------------------------------------------
const ratt = JSON.parse(readFileSync(infil, 'utf8')).map((k) =>
  Array.isArray(k)
    ? { titel: k[0], artist: k[1], ar: k[2], sv: k[3] ?? false, genre: k[4] ?? null }
    : k,
)

const klara = new Map()
if (existsSync(LOGG)) {
  for (const rad of readFileSync(LOGG, 'utf8').split('\n')) {
    if (!rad.trim()) continue
    const o = JSON.parse(rad)
    klara.set(o.titel + '|' + o.artist, o)
  }
  console.log(`${klara.size} redan avgjorda i ${LOGG}\n`)
}

const ut = []
for (let i = 0; i < ratt.length; i++) {
  const k = ratt[i]
  const tidigare = klara.get(k.titel + '|' + k.artist)
  if (tidigare && (tidigare.url || tidigare.strypt === false)) { ut.push(tidigare); continue }

  // Artistvarianter – se fälla 3. Träffar en variant är det DEN som ska in
  // i potten, annars faller raden nästa gång servern söker om den.
  const varianter = [k.artist]
  if (/^the\s+/i.test(k.artist)) varianter.push(k.artist.replace(/^the\s+/i, ''))
  else varianter.push('The ' + k.artist)

  let traff = null
  let vinnare = k.artist
  let strypt = false
  for (const artist of varianter) {
    const r = await prova(k.titel, artist)
    if (r.pick) { traff = r.pick; vinnare = artist; break }
    if (r.strypt) strypt = true
    await sleep(200)
  }

  const rad = traff
    ? {
        ...k,
        artist: vinnare,
        url: traff.r.previewUrl,
        trackId: traff.r.trackId ?? null,
        itunesTitel: traff.r.trackName,
        itunesArtist: traff.r.artistName,
        itunesAr: Number(String(traff.r.releaseDate ?? '').slice(0, 4)) || null,
      }
    : { ...k, url: null, strypt }

  appendFileSync(LOGG, JSON.stringify(rad) + '\n', 'utf8')
  ut.push(rad)
  console.log(
    `${String(i + 1).padStart(3)}/${ratt.length} ` +
      `${rad.url ? 'ok  ' : strypt ? 'STRYPT' : 'MISS'} ${k.ar} ${vinnare} – ${k.titel}` +
      (rad.url && vinnare !== k.artist ? `   (artist ändrad till Apples form)` : ''),
  )
  await sleep(400)
}

const spelbara = ut.filter((r) => r.url)
const strypta = ut.filter((r) => !r.url && r.strypt)
writeFileSync(utfil, JSON.stringify(spelbara, null, 1), 'utf8')

console.log(`\n${spelbara.length} spelbara av ${ut.length}, skrev ${utfil}`)
if (strypta.length) {
  console.log(
    `\n⚠ ${strypta.length} blev STRYPTA och är inte avgjorda. Kör skriptet igen –\n` +
      `  loggen hoppar över de klara och prövar bara de här. Lita inte på dem som missar.`,
  )
  for (const r of strypta) console.log(`   ${r.ar} ${r.artist} – ${r.titel}`)
}
const missar = ut.filter((r) => !r.url && !r.strypt)
if (missar.length) {
  console.log(`\n${missar.length} finns inte hos Apple i Sverige:`)
  for (const r of missar) console.log(`   ${r.ar} ${r.artist} – ${r.titel}`)
}
