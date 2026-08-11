// Spelar riktiga rundor mot prod och rapporterar vad som faktiskt kom upp.
//
// Finns för att pottfrågor inte går att svara på från koden. Att ett urval
// SER rätt ut i _pool_match säger inget om vad sällskapet hör, och ett årtal
// går inte att läsa ur en räknare – det måste dyka upp som facit i en runda.
// Skriptet skapar ett riktigt rum med anon-nyckeln, sätter urvalet, spelar N
// rundor och läser round_tracks.meta efter reveal.
//
// Går utan databaslösenord: anonym inloggning räcker, och en ensam värd får
// starta spelet (ingen minsta spelarantal-spärr).
//
// Användning:
//   node scripts/play-test.mjs --span 1950-1960 --rundor 12
//   node scripts/play-test.mjs --span 1950-1960 --span 1989-1998 --rundor 20
//   node scripts/play-test.mjs --span 1963-1963 --sv --genre pop --rundor 8
//
// Flera --span mäter VIKTNINGEN mellan spann (0078: varje spann ska väga
// lika oavsett hur många låtar det täcker). Ett smalt --span med --sv är
// sättet att leta upp en enskild låt och kontrollera dess årtal.
//
// RATE-LIMITS PÅ SERVERN som skriptet går i om man kör hårt:
//   room_create   5/min      spin  30/min
//   track_start  20/min      track_poll 200/min
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

function loadEnvLocal() {
  try {
    const txt = readFileSync(new URL('../.env.local', import.meta.url), 'utf8')
    for (const line of txt.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$/)
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim()
    }
  } catch { /* ingen .env.local */ }
}
loadEnvLocal()

const argv = process.argv.slice(2)
const flagga = (namn, standard = null) => {
  const i = argv.indexOf(namn)
  return i >= 0 ? argv[i + 1] : standard
}
const spann = argv.reduce((ut, a, i) => (a === '--span' ? [...ut, argv[i + 1]] : ut), [])
  .map((s) => s.split('-').map(Number))
const genrer = argv.reduce((ut, a, i) => (a === '--genre' ? [...ut, argv[i + 1]] : ut), [])
const sv = argv.includes('--sv') ? true : argv.includes('--intl') ? false : null
const RUNDOR = Number(flagga('--rundor', '12'))

const url = process.env.VITE_SUPABASE_URL
const nyckel = process.env.VITE_SUPABASE_ANON_KEY
if (!url || !nyckel) {
  console.error('✗ Saknar VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY i .env.local')
  process.exit(1)
}

// Skalans ändar skrivs som lobbyn skriver dem (0079-tidens regel): övre kant
// i skalans slut blir öppen, undre kant är alltid ett årtal.
const AR_MAX = Math.max(2026, new Date().getFullYear())
const bands = spann.map(([lo, hi]) => ({ min: lo, max: hi >= AR_MAX ? null : hi }))

const sb = createClient(url, nyckel, { auth: { persistSession: false, autoRefreshToken: false } })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const rpc = async (fn, args) => {
  const { data, error } = await sb.rpc(fn, args)
  if (error) throw new Error(`${fn}: ${error.message}`)
  return data
}

await sb.auth.signInAnonymously()

for (const b of bands) {
  const n = await rpc('track_pool_selection_count', { p_swedish: sv, p_bands: [b], p_genres: genrer })
  console.log(`band ${JSON.stringify(b)} → ${n} låtar`)
}
const totalt = await rpc('track_pool_selection_count', { p_swedish: sv, p_bands: bands, p_genres: genrer })
console.log(`urvalet → ${totalt} låtar\n`)

// room_create är 5/min – vänta hellre än att dö på sista slicen.
let room = null
for (let i = 0; i < 10 && !room; i++) {
  try {
    room = await rpc('create_room', { p_name: 'Speltest', p_display_name: 'Test' })
  } catch (err) {
    if (!/För många anrop/.test(err.message)) throw err
    console.log('room_create strypt, väntar 20 s ...')
    await sleep(20000)
  }
}

const upd = await sb.from('rooms')
  .update({ swedish_mode: sv, year_bands: bands, genres: genrer }).eq('id', room.id).select()
if (upd.error || !upd.data?.length) throw new Error('kunde inte skriva urvalet: ' + JSON.stringify(upd.error))
console.log(`rum ${room.code} – year_bands ${JSON.stringify(upd.data[0].year_bands)}`)
console.log(`härlett year_min/max: ${upd.data[0].year_min} / ${upd.data[0].year_max}\n`)

await rpc('start_game', { p_room_id: room.id })
await rpc('ensure_card', { p_room_id: room.id })

const inomBand = (ar) => bands.findIndex((b) => (b.min === null || ar >= b.min) && (b.max === null || ar <= b.max))
const resultat = []

for (let i = 0; i < RUNDOR; i++) {
  try {
    const round = await rpc('spin_wheel', { p_room_id: room.id })
    const t0 = Date.now()
    await rpc('start_random_track', { p_room_id: room.id })

    // Ingen paus före första pollen: en cacheträff har redan satt låten, och
    // då ska rundan vara igång utan att någon väntat på ett uppslag.
    let klar = null
    let pollar = 0
    while (Date.now() - t0 < 45000) {
      pollar++
      const d = await rpc('poll_track_start', { p_room_id: room.id })
      if (d?.id) { klar = d; break }
      await sleep(600)
    }
    const ms = Date.now() - t0
    if (!klar) { console.log(`runda ${i + 1}: timeout`); continue }

    await rpc('reveal_answers', { p_room_id: room.id })
    const { data: rt, error } = await sb.from('round_tracks').select('meta').eq('round_id', round.id).maybeSingle()
    if (error) throw new Error('round_tracks: ' + error.message)

    const m = rt?.meta ?? {}
    const ar = Number(m.year)
    const ix = inomBand(ar)
    resultat.push({ ar, ix, ms, pollar, namn: m.name, artist: m.artist })
    console.log(
      `runda ${String(i + 1).padStart(2)}: ${ix < 0 ? 'UTANFÖR' : 'band ' + (ix + 1)}  ${ar}  ` +
        `${String(ms).padStart(5)} ms / ${pollar} poll  ${m.artist} – ${m.name}`,
    )
  } catch (err) {
    console.log(`runda ${i + 1}: ${err.message}`)
  }
  await sleep(1500)
}

console.log(`\n${resultat.length} spelade rundor`)
const utanfor = resultat.filter((r) => r.ix < 0)
console.log(`  ${utanfor.length} utanför valda spann`)
for (const r of utanfor) console.log(`    UTANFÖR ${r.ar} ${r.artist} – ${r.namn}`)
if (bands.length > 1) {
  bands.forEach((b, i) => {
    const n = resultat.filter((r) => r.ix === i).length
    console.log(`  band ${i + 1} ${JSON.stringify(b)}: ${n} (${Math.round((100 * n) / resultat.length)} %)`)
  })
}
const direkt = resultat.filter((r) => r.pollar === 1).length
console.log(`  ${direkt} startade på första pollen (cacheträff, inget uppslag)`)
if (resultat.length) {
  const tider = resultat.map((r) => r.ms).sort((a, b) => a - b)
  console.log(`  tid till låt: median ${tider[Math.floor(tider.length / 2)]} ms, värst ${tider.at(-1)} ms`)
}

await rpc('leave_room', { p_room_id: room.id }).catch(() => {})
console.log('rum stängt')
