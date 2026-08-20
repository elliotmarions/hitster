// =====================================================================
//  Slår ihop MusicBrainz-domarna och Wikidata-kontrollen till den lista
//  migrationen faktiskt skriver in i potten.
//
//  Med i listan hamnar bara artister som klarar ALLA tre kraven:
//   1. dom() ger solo eller grupp (entydig, eller namnkrock löst av land),
//   2. Wikidata säger inte emot,
//   3. artisten står inte i oeniga-artister.json.
//
//  Allt annat lämnas utan artisttyp. En låt utan typ dyker aldrig upp i
//  en solo/grupp-runda – den kostar täckning, aldrig ett felaktigt svar.
//
//  Körning: node scripts/build-artist-types.mjs [--skriv]
//  Med --skriv läggs SQL-underlaget i scripts/data/artist-types.sql
// =====================================================================
import fs from 'node:fs'
import pg from 'pg'
import { huvudkreditering } from './fetch-artist-types.mjs'
import { dom } from './analyze-artist-types.mjs'

const träffar = JSON.parse(fs.readFileSync('scripts/data/artist-types.json', 'utf8'))
const oeniga = new Set(JSON.parse(fs.readFileSync('scripts/data/oeniga-artister.json', 'utf8')))

const env = fs.readFileSync('.env.local', 'utf8')
const c = new pg.Client({
  connectionString: env.match(/^SUPABASE_DB_URL=(.*)$/m)[1].trim(),
  ssl: { rejectUnauthorized: false },
})
await c.connect()
const { rows } = await c.query(
  `select artist, count(*)::int latar, bool_or(sv) sv from track_pool group by artist`
)
await c.end()

const rad = []
const bort = { oenig: 0, ingenDom: 0 }
const latar = { solo: 0, grupp: 0, utan: 0 }

for (const r of rows) {
  const namn = huvudkreditering(r.artist)
  const post = träffar[namn]
  const d = post ? dom(post, r.sv, namn) : { dom: null }
  if (!d.dom) {
    bort.ingenDom++
    latar.utan += r.latar
    continue
  }
  if (oeniga.has(namn)) {
    bort.oenig++
    latar.utan += r.latar
    continue
  }
  rad.push({ artist: r.artist, typ: d.dom })
  latar[d.dom] += r.latar
}

const med = latar.solo + latar.grupp
const alla = med + latar.utan
console.log(`artiststrängar med typ: ${rad.length} av ${rows.length}`)
console.log(`  bortvalda: ${bort.ingenDom} utan entydig dom, ${bort.oenig} motsagda av Wikidata`)
console.log(`\nLÅTAR: solo ${latar.solo}, grupp ${latar.grupp}, utan typ ${latar.utan}`)
console.log(`  täckning ${((100 * med) / alla).toFixed(1)} % av ${alla} låtar`)
console.log(`  fördelning: ${((100 * latar.solo) / med).toFixed(1)} % solo / ${((100 * latar.grupp) / med).toFixed(1)} % grupp`)

if (process.argv.includes('--skriv')) {
  const cite = (s) => "'" + s.replace(/'/g, "''") + "'"
  const sql = rad.map((r) => `  (${cite(r.artist)}, ${cite(r.typ)})`).join(',\n')
  fs.writeFileSync('scripts/data/artist-types.sql', sql)
  console.log(`\nSkrev scripts/data/artist-types.sql (${rad.length} rader)`)
}
