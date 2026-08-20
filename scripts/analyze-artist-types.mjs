// =====================================================================
//  Omvandlar MusicBrainz-träffarna till en dom per artist: solo/grupp/okänd.
//
//  Grundhållningen är att hellre svara "okänd" än fel. En okänd artist
//  kostar bara att låten aldrig dyker upp i en solo/grupp-runda; ett fel
//  svar kostar att spelet dömer en spelare orättvist.
//
//  Reglerna, i ordning:
//   1. Ingen exakt namnträff  -> okänd. (Här hamnar samarbetena: ingen
//      artist i MusicBrainz heter "Kygo, Khalid & Gryffin".)
//   2. Träffar utan typ ignoreras helt.
//   3. Person -> solo. Group/Orchestra/Choir -> grupp.
//      Character/Other -> okänd; de är varken eller.
//   4. Är alla kvarvarande träffar överens -> den domen. Namnkrockar där
//      alla bär samma typ ("Yasin" finns sju gånger, alltid Person) är
//      alltså ofarliga – det är typen kategorin frågar om, inte vem.
//   5. Är de oense ("Kent" = svensk grupp OCH fransk person) avgör i första
//      hand vem som SPELADE IN låten – se resolve-ambiguous-artists.mjs.
//      Den uppgiften gäller just den här låten och väger tyngst.
//   6. Finns ingen sådan uppgift avgör landet när potten pekar ut det: en
//      låt ur svenska potten menar den svenska artisten. Annars -> okänd.
//
//  Körning: node scripts/analyze-artist-types.mjs [--lista]
// =====================================================================
import fs from 'node:fs'
import pg from 'pg'
import { huvudkreditering } from './fetch-artist-types.mjs'

const IN = 'scripts/data/artist-types.json'
const LOST = 'scripts/data/ambiguous-resolved.json'

// Namnkrockar som resolve-ambiguous-artists.mjs redde ut genom att fråga
// vem som spelade in låten. Finns filen inte är kartan tom och allt
// fungerar som förut.
export const löst = fs.existsSync(LOST) ? JSON.parse(fs.readFileSync(LOST, 'utf8')) : {}

export const TYP_DOM = {
  Person: 'solo',
  Group: 'grupp',
  Orchestra: 'grupp',
  Choir: 'grupp',
}

// Returnerar { dom, skal } där dom är 'solo' | 'grupp' | null.
// namn = krediteringen posten hämtades på, behövs för inspelnings-domarna.
export function dom(post, sv, namn = null) {
  const typade = (post?.exakta ?? []).filter((e) => e.typ)
  if (!post || post.exakta.length === 0) return { dom: null, skal: 'ingen träff' }
  if (typade.length === 0) return { dom: null, skal: 'träff utan typ' }

  const domar = typade.map((e) => TYP_DOM[e.typ] ?? null)
  if (domar.every((d) => d === null)) return { dom: null, skal: 'bara Character/Other' }

  const unika = [...new Set(domar.filter(Boolean))]
  if (unika.length === 1) return { dom: unika[0], skal: 'entydig' }

  // Oense – men vet vi vem som spelade in låten är frågan avgjord. Den
  // uppgiften väger tyngst av alla: den handlar om just den här låten.
  if (namn && löst[namn]?.dom)
    return { dom: löst[namn].dom, skal: 'inspelningen avgjorde' }

  // Annars: svenska potten pekar ut den svenska artisten.
  if (sv) {
    const se = [...new Set(typade.filter((e) => e.land === 'SE').map((e) => TYP_DOM[e.typ]))]
    if (se.length === 1 && se[0]) return { dom: se[0], skal: 'land avgjorde (SE)' }
  }
  return { dom: null, skal: 'motstridiga typer' }
}

async function main() {
  const träffar = JSON.parse(fs.readFileSync(IN, 'utf8'))

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

  const skal = {}
  const utfall = { solo: 0, grupp: 0, okand: 0 }
  const latar = { solo: 0, grupp: 0, okand: 0 }
  const ejHamtade = []
  const exempel = {}

  for (const r of rows) {
    const namn = huvudkreditering(r.artist)
    const post = träffar[namn]
    if (!post) {
      ejHamtade.push(r.artist)
      continue
    }
    const d = dom(post, r.sv, namn)
    const nyckel = d.dom ?? 'okand'
    utfall[nyckel]++
    latar[nyckel] += r.latar
    skal[d.skal] = (skal[d.skal] ?? 0) + 1
    ;(exempel[d.skal] ??= []).push(`${r.artist} (${r.latar} låtar)`)
  }

  const summaLatar = latar.solo + latar.grupp + latar.okand
  console.log(`\n=== ${rows.length} artiststrängar, ${ejHamtade.length} ej hämtade än`)
  console.log(`\nARTISTER:  solo ${utfall.solo}  grupp ${utfall.grupp}  okänd ${utfall.okand}`)
  console.log(
    `LÅTAR:     solo ${latar.solo}  grupp ${latar.grupp}  okänd ${latar.okand}` +
      `   → täckning ${((100 * (latar.solo + latar.grupp)) / summaLatar).toFixed(1)} %` +
      `, varav grupp ${((100 * latar.grupp) / (latar.solo + latar.grupp)).toFixed(1)} %`
  )

  console.log('\nSKÄL (antal artister):')
  for (const [s, n] of Object.entries(skal).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(n).padStart(5)}  ${s}`)
    if (process.argv.includes('--lista') || s === 'motstridiga typer')
      console.log('           ' + exempel[s].slice(0, 12).join(' · '))
  }
}

if (process.argv[1]?.endsWith('analyze-artist-types.mjs')) await main()
