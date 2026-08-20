// =====================================================================
//  Oberoende kontroll av MusicBrainz-domarna mot Wikidata.
//
//  MusicBrainz är en wiki: en enskild post kan vara fel eller otypad utan
//  att något larmar. Kategorin "Solo eller grupp" dömer spelare, så domen
//  ska inte vila på en enda källa. Wikidata känner igen samma artister via
//  MusicBrainz-id (P434) och har en egen uppgift om vad de är (P31:
//  Q5 = människa, Q215380 = musikgrupp, ...).
//
//  Utfallet är en felprocent, inte en fix: håller källorna med varandra i
//  princip alltid vet vi att datan bär. Gör de inte det får kategorin inte
//  byggas på den här datan alls.
//
//  Artister där källorna säger emot varandra skrivs ut och plockas bort ur
//  underlaget – tveksamma fall ska aldrig nå spelet.
//
//  Körning: node scripts/crosscheck-artist-types.mjs
//  Resultat: scripts/data/wikidata-types.json
// =====================================================================
import fs from 'node:fs'
import { dom, TYP_DOM, löst } from './analyze-artist-types.mjs'

const IN = 'scripts/data/artist-types.json'
const UT = 'scripts/data/wikidata-types.json'
const AGENT = 'Latsnurran/1.0 ( elliotmarions@gmail.com )'
const BIT = 150

// Wikidatas "instans av"-värden vi bryr oss om. Allt annat lämnas okänt.
const MANNISKA = 'Q5'
const GRUPPORD = /\b(group|band|duo|trio|quartet|ensemble|orchestra|choir|project)\b/i

const sov = (ms) => new Promise((r) => setTimeout(r, ms))

async function fraga(mbids) {
  const varden = mbids.map((m) => `"${m}"`).join(' ')
  const sparql = `
    SELECT ?mbid ?typ ?typLabel WHERE {
      VALUES ?mbid { ${varden} }
      ?item wdt:P434 ?mbid ; wdt:P31 ?typ .
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }`
  const url = 'https://query.wikidata.org/sparql?format=json&query=' + encodeURIComponent(sparql)
  for (let f = 1; f <= 3; f++) {
    try {
      const r = await fetch(url, { headers: { 'User-Agent': AGENT, Accept: 'application/json' } })
      if (!r.ok) {
        await sov(3000 * f)
        continue
      }
      return (await r.json()).results.bindings
    } catch {
      await sov(3000 * f)
    }
  }
  return []
}

async function main() {
  const träffar = JSON.parse(fs.readFileSync(IN, 'utf8'))

  // Vilka artist-id domen faktiskt vilar på. För en namnkrock som en
  // inspelning avgjort är det BARA den artist som spelade in låten som
  // ska kontrolleras – de andra namnvärdarna är inte den vi menar.
  const barande = (namn, post, d) => {
    if (d.skal === 'inspelningen avgjorde')
      return post.exakta.filter((e) => (löst[namn]?.idn ?? []).includes(e.mbid))
    if (d.skal === 'land avgjorde (SE)')
      return post.exakta.filter((e) => e.land === 'SE' && e.typ)
    return post.exakta.filter((e) => e.typ)
  }

  // Bara artister som faktiskt får en dom är värda att kontrollera, och
  // bara deras exakta träffar.
  const mbidTillNamn = new Map()
  for (const [namn, post] of Object.entries(träffar)) {
    if (!dom(post, post.sv, namn).dom) continue
    for (const e of post.exakta) if (e.mbid) mbidTillNamn.set(e.mbid, namn)
  }
  const alla = [...mbidTillNamn.keys()]
  console.log(`kontrollerar ${alla.length} MusicBrainz-id i bitar om ${BIT}`)

  const wd = fs.existsSync(UT) ? JSON.parse(fs.readFileSync(UT, 'utf8')) : {}
  for (let i = 0; i < alla.length; i += BIT) {
    const bit = alla.slice(i, i + BIT).filter((m) => !(m in wd))
    if (bit.length === 0) continue
    const rader = await fraga(bit)
    for (const m of bit) wd[m] = wd[m] ?? []
    for (const rad of rader) {
      const mbid = rad.mbid.value
      const qid = rad.typ.value.split('/').pop()
      wd[mbid].push({ qid, etikett: rad.typLabel?.value ?? '' })
    }
    fs.writeFileSync(UT, JSON.stringify(wd, null, 1))
    console.log(`  ${Math.min(i + BIT, alla.length)}/${alla.length}`)
    await sov(1200)
  }

  // Wikidatas dom för ett enskilt MusicBrainz-id.
  const wdDom = (mbid) => {
    const domar = new Set()
    for (const t of wd[mbid] ?? []) {
      if (t.qid === MANNISKA) domar.add('solo')
      else if (GRUPPORD.test(t.etikett)) domar.add('grupp')
    }
    return domar.size === 1 ? [...domar][0] : null
  }

  // --- Mätning 1: säger källorna emot varandra om SAMMA artist? ---------
  //  Det är den frågan som avgör om MusicBrainz typuppgift går att lita på.
  //  Att ett NAMN bärs av både en person och ett band är en annan sak, och
  //  hanteras av dom() – här jämförs identitet mot identitet.
  let eniga = 0
  const oenigaId = []
  for (const [namn, post] of Object.entries(träffar)) {
    for (const e of post.exakta) {
      const min = TYP_DOM[e.typ]
      const deras = wdDom(e.mbid)
      if (!min || !deras) continue
      if (min === deras) eniga++
      else oenigaId.push({ namn, mbid: e.mbid, mb: min, wd: deras, latar: post.latar })
    }
  }
  const provade = eniga + oenigaId.length
  console.log(`\n=== MÄTNING 1: samma artist hos båda källorna`)
  console.log(`  ${provade} artist-id gick att jämföra: ${eniga} eniga, ${oenigaId.length} oeniga`)
  if (provade) console.log(`  → felprocent ${((100 * oenigaId.length) / provade).toFixed(2)} %`)
  oenigaId.sort((a, b) => b.latar - a.latar)
  for (const o of oenigaId.slice(0, 25))
    console.log(`    ${o.namn} — MB: ${o.mb}, WD: ${o.wd} (${o.latar} låtar)`)

  // --- Mätning 2: håller Wikidata med om den dom vi faktiskt tänker använda?
  //  Här räknas bara den artist vi valt att gå på. För namnkrockar som dom()
  //  löst med landet är det just den kontrollen som betyder något.
  let domEniga = 0
  let domOkant = 0
  const domOeniga = []
  for (const [namn, post] of Object.entries(träffar)) {
    const d = dom(post, post.sv, namn)
    if (!d.dom) continue
    const burna = barande(namn, post, d)
    const deras = [...new Set(burna.map((e) => wdDom(e.mbid)).filter(Boolean))]
    if (deras.length === 0) domOkant++
    else if (deras.length === 1 && deras[0] === d.dom) domEniga++
    else domOeniga.push({ namn, min: d.dom, wikidata: deras, latar: post.latar, skal: d.skal })
  }
  console.log(`\n=== MÄTNING 2: domen vi tänker använda`)
  console.log(`  ${domEniga} bekräftade av Wikidata, ${domOeniga.length} motsagda, ${domOkant} okontrollerbara`)
  domOeniga.sort((a, b) => b.latar - a.latar)
  for (const o of domOeniga.slice(0, 40))
    console.log(`    ${o.namn} — vi: ${o.min}, WD: ${o.wikidata.join('+')} (${o.latar} låtar, ${o.skal})`)

  fs.writeFileSync(
    'scripts/data/oeniga-artister.json',
    JSON.stringify([...new Set([...domOeniga, ...oenigaId].map((o) => o.namn))], null, 1)
  )
  console.log(`\nSkrev scripts/data/oeniga-artister.json – de utesluts ur potten.`)
}

if (process.argv[1]?.endsWith('crosscheck-artist-types.mjs')) await main()
