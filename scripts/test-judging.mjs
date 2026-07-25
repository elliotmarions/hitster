// Regressionsprov för auto-rättningen (_fuzzy_text → artist- och titelsvar).
//
//   node scripts/test-judging.mjs                     kör mot live-DB
//   node scripts/test-judging.mjs <migration.sql>     laddar migrationen i en
//                                                     tillbakarullad transaktion
//                                                     och provar den först
//
// Bakgrund: rättningen har varit för slapp två gånger (se 0041). Svaret "9"
// dömdes som rätt när facit var "X", och ett ord av fem räckte för en titel.
// Provet finns för att det inte ska hända igen tyst.
import { readFileSync } from 'node:fs'
import pg from 'pg'

// true = ska dömas RÄTT, false = ska dömas FEL.
const CASES = [
  // Ska godkännas
  ['abba', 'ABBA', true, 'exakt'],
  ['Abba', 'ABBA', true, 'versaler spelar ingen roll'],
  ['abba!', 'ABBA', true, 'skiljetecken'],
  ['bohemian rhapsody', 'Bohemian Rhapsody', true, 'exakt titel'],
  ['det är bohemian rhapsody', 'Bohemian Rhapsody', true, 'facit inbakat i en mening'],
  ['bohemian rapsody', 'Bohemian Rhapsody', true, 'litet stavfel'],
  ['rhapsody bohemian', 'Bohemian Rhapsody', true, 'omkastad ordföljd'],
  ['madona', 'Madonna', true, 'ett tecken fel'],
  ['the beatles', 'Beatles', true, 'svaret har extra "the"'],
  ['Heat Is On', 'The Heat Is On', true, 'facit har "the", svaret inte'],
  ['dancing queen', 'Dancing Queen', true, 'exakt'],
  ['michael jackson', 'Michael Jackson', true, 'exakt tvåordsartist'],
  ['With Or Without You', 'With Or Without You', true, 'titel som börjar på "with"'],

  // Ska underkännas
  ['9', 'X', false, 'rapporterat fall: helt fel, ett tecken'],
  ['x', 'Y', false, 'två olika enstaka tecken'],
  ['a', 'Madonna', false, 'en bokstav som råkar finnas i facit'],
  ['9', '99 Luftballons', false, 'en siffra ur facit'],
  ['de', 'Depeche Mode', false, 'två bokstäver ur facit'],
  ['bohemian', 'Bohemian Rhapsody', false, 'ett ord av två'],
  ['rhapsody', 'Bohemian Rhapsody', false, 'ett ord av två'],
  ['dancing', 'Dancing Queen', false, 'ett ord av två'],
  ['love', 'Love Me Tender', false, 'ett ord av tre'],
  ['sunshine', 'You Are the Sunshine of My Life', false, 'ett ord av sju'],
  ['life', 'You Are the Sunshine of My Life', false, 'ett ord av sju'],
  ['Heat', 'The Heat Is On', false, 'ett ord, resten är småord'],
  ['Let', 'Let It Be', false, 'ett ord, resten är småord'],
  ['kent', 'Kent Andersson', false, 'halva namnet'],
  ['queen', 'Queens of the Stone Age', false, 'nästan-namn, annan artist'],
  ['sos', 'Sossarna', false, 'delsträng utan ordgräns'],
  ['queen', 'Bohemian Rhapsody', false, 'artist i stället för titel'],
  ['abba', 'Madonna', false, 'helt fel artist'],
  ['1999', 'Prince', false, 'siffror mot artistnamn'],
  ['', 'ABBA', false, 'tomt svar'],
  ['vet inte', 'ABBA', false, 'ingen aning'],
]

function loadEnvLocal() {
  try {
    const txt = readFileSync(new URL('../.env.local', import.meta.url), 'utf8')
    for (const line of txt.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$/)
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim()
    }
  } catch {
    /* ingen .env.local */
  }
}
loadEnvLocal()

const url = process.env.SUPABASE_DB_URL
if (!url) {
  console.error('✗ Saknar SUPABASE_DB_URL i .env.local (se .env.example).')
  process.exit(1)
}

const patch = process.argv[2]
const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
await client.connect()

if (patch) {
  await client.query('begin')
  await client.query(readFileSync(patch, 'utf8'))
  console.log(`(provar ${patch} – rullas tillbaka efteråt)\n`)
}

let fel = 0
for (const [answer, target, want, note] of CASES) {
  const { rows } = await client.query('select public._fuzzy_text($1, $2) as r', [answer, target])
  const got = rows[0].r
  if (got !== want) {
    fel++
    console.log(`  ✗ "${answer}" mot "${target}" → ${got}, skulle vara ${want}  (${note})`)
  }
}
console.log(`${CASES.length - fel}/${CASES.length} rätt${fel ? `, ${fel} FEL` : ''}`)

// Svepet över hela potten fångar det handplockade fall missar: att en ändring
// gör rättningen så sträng att riktiga svar underkänns.
const pool = (await client.query('select title, artist from track_pool')).rows
const svep = [
  ['exakt titel', (t) => t.title, 'title', 100],
  ['titel utan "the"', (t) => t.title.replace(/^the\s+/i, ''), 'title', 100],
  ['exakt artist', (t) => t.artist, 'artist', 100],
]
for (const [namn, fn, kolumn, krav] of svep) {
  const svar = pool.map(fn)
  const facit = pool.map((t) => t[kolumn])
  const { rows } = await client.query(
    `select count(*) filter (where public._fuzzy_text(s, f))::int ok, count(*)::int n
       from unnest($1::text[], $2::text[]) as x(s, f)`,
    [svar, facit],
  )
  const pct = (rows[0].ok / rows[0].n) * 100
  if (pct < krav) fel++
  console.log(`  ${pct >= krav ? '✓' : '✗'} ${namn}: ${rows[0].ok}/${rows[0].n} (${pct.toFixed(1)} %, krav ${krav} %)`)
}

if (patch) await client.query('rollback')
await client.end()
process.exitCode = fel ? 1 : 0
