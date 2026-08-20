// =====================================================================
//  Hämtar artisttyp (Person / Group) från MusicBrainz för hela låtpotten.
//
//  Kategorin "Solo eller grupp" måste kunna dömas vattentätt. Vi gissar
//  därför ALDRIG utifrån artistnamnet – strängen slås upp mot MusicBrainz
//  och bara ett EXAKT namnträff (eller alias-träff) räknas.
//
//  Två saker gör jobbet knepigt och styr designen:
//
//   1. Samarbeten. "Kygo, Khalid & Gryffin" är tre soloartister, inte en
//      grupp – men "Simon & Garfunkel" och "Bill Haley & His Comets" ÄR
//      en enda grupp. Regeln som skiljer dem: hela krediteringen måste
//      finnas som EN artist i MusicBrainz. Samarbeten matchar inget och
//      faller därmed bort av sig själva.
//
//   2. Namnkrockar. "Kent" är både en svensk grupp och en fransk person,
//      "Marilyn Manson" både personen och bandet. Alla exakta träffar
//      sparas därför med typ/land/poäng så att analyssteget kan se när
//      en artist är tvetydig – och välja bort den hellre än att chansa.
//
//  Gästartister påverkar inte huvudakten, så "Gotye (feat. Kimbra)" slås
//  upp som "Gotye". Se huvudkreditering() nedan.
//
//  Körning:  node scripts/fetch-artist-types.mjs
//  Resultat: scripts/data/artist-types.json (skrivs löpande, går att
//            avbryta och återuppta – redan hämtade namn hoppas över).
// =====================================================================
import fs from 'node:fs'
import path from 'node:path'
import pg from 'pg'

const UT = 'scripts/data/artist-types.json'
// MusicBrainz kräver en identifierande User-Agent och max ett anrop/sekund.
const AGENT = 'Latsnurran/1.0 ( elliotmarions@gmail.com )'
const PAUS = 1100

// Gästartister och versus-kopplingar hör inte till huvudakten: det är
// huvudakten som är solo eller grupp. Klipp bort svansen.
export function huvudkreditering(artist) {
  let s = artist
  // "(feat. X)" / "(with X)" – hela parentesen bort.
  s = s.replace(/\s*\((?:feat|ft|featuring|with|med)\.?\s[^)]*\)/gi, '')
  // "feat. X" utan parentes – allt från nyckelordet och framåt.
  s = s.replace(/\s+(?:feat|ft|featuring)\.?\s+.*$/gi, '')
  // "A vs B", "A with B" – bara första ledet.
  s = s.replace(/\s+(?:vs|versus)\.?\s+.*$/gi, '')
  s = s.replace(/\s+with\s+.*$/gi, '')
  return s.replace(/\s+/g, ' ').trim()
}

// Jämförelsenyckel för namn: gemener, utan diakriter och skiljetecken.
// "Charli xcx" ska matcha "Charli XCX", "Beyoncé" matcha "Beyonce".
export function namnnyckel(s) {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

const sov = (ms) => new Promise((r) => setTimeout(r, ms))

async function sokArtist(namn) {
  // Inuti ett citerat Lucene-uttryck behöver bara " och \ escapas.
  const fras = namn.replace(/[\\"]/g, '\\$&')
  const url =
    'https://musicbrainz.org/ws/2/artist?fmt=json&limit=10&query=' +
    encodeURIComponent(`artist:"${fras}"`)

  for (let forsok = 1; forsok <= 4; forsok++) {
    try {
      const r = await fetch(url, { headers: { 'User-Agent': AGENT } })
      if (r.status === 503 || r.status === 429) {
        // MusicBrainz strypte oss – backa av och försök igen.
        await sov(PAUS * 4 * forsok)
        continue
      }
      if (!r.ok) return { fel: `HTTP ${r.status}` }
      return { artister: (await r.json()).artists ?? [] }
    } catch (e) {
      if (forsok === 4) return { fel: String(e.message ?? e) }
      await sov(PAUS * 2 * forsok)
    }
  }
  return { fel: 'gav upp' }
}

async function main() {
  const env = fs.readFileSync('.env.local', 'utf8')
  const c = new pg.Client({
    connectionString: env.match(/^SUPABASE_DB_URL=(.*)$/m)[1].trim(),
    ssl: { rejectUnauthorized: false },
  })
  await c.connect()
  // En rad per artiststräng: hur många låtar den bär, om den bor i svenska
  // potten och en exempeltitel (för att kunna reda ut namnkrockar senare).
  const { rows } = await c.query(`
    select artist,
           count(*)::int      as latar,
           bool_or(sv)        as sv,
           min(title)         as exempel
      from track_pool
     group by artist
     order by count(*) desc
  `)
  await c.end()

  // Flera artiststrängar kan dela huvudkreditering ("Gotye" och
  // "Gotye (feat. Kimbra)") – slå ihop dem till ett uppslag.
  const krediteringar = new Map()
  for (const r of rows) {
    const namn = huvudkreditering(r.artist)
    if (!namn) continue
    const post = krediteringar.get(namn) ?? { namn, latar: 0, sv: false, exempel: r.exempel }
    post.latar += r.latar
    post.sv = post.sv || r.sv
    krediteringar.set(namn, post)
  }
  const lista = [...krediteringar.values()].sort((a, b) => b.latar - a.latar)

  fs.mkdirSync(path.dirname(UT), { recursive: true })
  const träffar = fs.existsSync(UT) ? JSON.parse(fs.readFileSync(UT, 'utf8')) : {}
  const kvar = lista.filter((k) => !träffar[k.namn])

  console.log(
    `${lista.length} unika krediteringar, ${lista.length - kvar.length} redan hämtade, ` +
      `${kvar.length} kvar (~${Math.round((kvar.length * PAUS) / 60000)} min)`
  )

  let n = 0
  for (const k of kvar) {
    const svar = await sokArtist(k.namn)
    const nyckel = namnnyckel(k.namn)

    // Bara EXAKTA namnträffar duger. Alias räknas – MusicBrainz för in
    // stavningsvarianter och skrivsätt där ("Charli XCX", "P!nk").
    const exakta = (svar.artister ?? [])
      .filter((a) => {
        if (namnnyckel(a.name ?? '') === nyckel) return true
        return (a.aliases ?? []).some((al) => namnnyckel(al.name ?? '') === nyckel)
      })
      .map((a) => ({
        mbid: a.id,
        namn: a.name,
        typ: a.type ?? null,
        land: a.country ?? a.area?.['iso-3166-1-codes']?.[0] ?? null,
        poang: a.score,
        forklaring: a.disambiguation ?? '',
      }))

    träffar[k.namn] = {
      latar: k.latar,
      sv: k.sv,
      exempel: k.exempel,
      fel: svar.fel ?? null,
      exakta,
    }

    // Skriv efter varje träff: körningen tar över en timme och ska tåla
    // att avbrytas.
    fs.writeFileSync(UT, JSON.stringify(träffar, null, 1))
    if (++n % 50 === 0) console.log(`  ${n}/${kvar.length} … senast: ${k.namn}`)
    await sov(PAUS)
  }
  console.log(`Klart: ${Object.keys(träffar).length} krediteringar i ${UT}`)
}

// Går att importera för sina hjälpfunktioner utan att hämtningen startar.
if (process.argv[1]?.endsWith('fetch-artist-types.mjs')) await main()
