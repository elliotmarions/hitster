// =====================================================================
//  Reder ut namnkrockar genom att fråga vem som SPELADE IN låten.
//
//  "Shakira" är både colombianskan och en tysk grupp; "The Rolling Stones"
//  delar namn med två okända. Söker man bara på namnet går det inte att
//  veta vilken av dem potten menar, och då blir svaret okänd – 505 låtar
//  faller bort i onödan, däribland några av de mest kända i hela potten.
//
//  MusicBrainz vet vilka artister som står bakom en INSPELNING. Slår vi
//  upp en konkret låttitel ur potten tillsammans med artistnamnet får vi
//  id:t på den artist som faktiskt gjorde den – och därmed rätt typ.
//  Det är ett svar som är sant, inte sannolikt.
//
//  Kravet är fortfarande hårt: artistnamnet i inspelningens kreditering
//  måste stämma exakt, id:t måste finnas bland namnsökningens träffar
//  (annars vet vi inte dess typ), och alla inspelningar som svarar måste
//  peka på samma typ. Annars förblir artisten okänd.
//
//  Körning: node scripts/resolve-ambiguous-artists.mjs
//  Resultat: scripts/data/ambiguous-resolved.json
// =====================================================================
import fs from 'node:fs'
import { namnnyckel } from './fetch-artist-types.mjs'
import { dom, TYP_DOM } from './analyze-artist-types.mjs'

const UT = 'scripts/data/ambiguous-resolved.json'
const AGENT = 'Latsnurran/1.0 ( elliotmarions@gmail.com )'
const PAUS = 1100

const sov = (ms) => new Promise((r) => setTimeout(r, ms))

async function sokInspelning(titel, artist) {
  const f = (s) => s.replace(/[\\"]/g, '\$&')
  const url =
    'https://musicbrainz.org/ws/2/recording?fmt=json&limit=25&query=' +
    encodeURIComponent(`recording:"${f(titel)}" AND artist:"${f(artist)}"`)
  for (let i = 1; i <= 4; i++) {
    try {
      const r = await fetch(url, { headers: { 'User-Agent': AGENT } })
      if (r.status === 503 || r.status === 429) {
        await sov(PAUS * 4 * i)
        continue
      }
      if (!r.ok) return null
      return (await r.json()).recordings ?? []
    } catch {
      await sov(PAUS * 2 * i)
    }
  }
  return null
}

const träffar = JSON.parse(fs.readFileSync('scripts/data/artist-types.json', 'utf8'))
const klart = fs.existsSync(UT) ? JSON.parse(fs.readFileSync(UT, 'utf8')) : {}

// Bara de som föll på motstridiga typer är värda att reda ut. Saknas typ
// helt eller finns ingen träff alls hjälper ingen inspelning.
const oklara = Object.entries(träffar).filter(
  ([namn, post]) => dom(post, post.sv).skal === 'motstridiga typer' && !klart[namn]
)
console.log(`${oklara.length} tvetydiga artister att reda ut (~${Math.round((oklara.length * 3.5) / 60)} min)`)

let löst = 0
for (const [namn, post] of oklara) {
  const nyckel = namnnyckel(namn)
  // Typen per artist-id, som namnsökningen redan gav oss.
  const typPerId = new Map(post.exakta.filter((e) => e.typ).map((e) => [e.mbid, TYP_DOM[e.typ]]))

  const inspelningar = await sokInspelning(post.exempel, namn)
  const domar = new Set()
  const idn = new Set()
  for (const insp of inspelningar ?? []) {
    for (const kred of insp['artist-credit'] ?? []) {
      const a = kred.artist
      if (!a || namnnyckel(a.name ?? '') !== nyckel) continue
      if (!typPerId.has(a.id)) continue
      idn.add(a.id)
      domar.add(typPerId.get(a.id))
    }
  }

  klart[namn] = {
    dom: domar.size === 1 ? [...domar][0] : null,
    idn: [...idn],
    titel: post.exempel,
    latar: post.latar,
  }
  if (klart[namn].dom) löst++
  fs.writeFileSync(UT, JSON.stringify(klart, null, 1))
  await sov(PAUS)
}
console.log(`klart: ${löst} av ${oklara.length} fick en dom via inspelningen`)
