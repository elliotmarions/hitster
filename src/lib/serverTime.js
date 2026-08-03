// ============================================================
//  Serverklocka – kompenserar för att enheters klockor går isär
// ============================================================
//
//  Uppspelningen synkas genom att alla klienter startar klippet vid rundans
//  timer_start_at. Tidigare jämfördes den tidpunkten mot enhetens EGEN
//  Date.now(), med antagandet att alla är NTP-synkade inom tiondelar. Det
//  håller inte i praktiken – en surfplatta som legat i standby kan ligga
//  flera sekunder fel, och då hör den spelaren låten lika många sekunder före
//  eller efter alla andra.
//
//  Vi mäter därför EN gång per sidladdning hur mycket enhetens klocka skiljer
//  sig från serverns, via RPC:n server_now() (migration 0045).
//
//  Att i stället läsa HTTP:ns Date-header går INTE: den är inte
//  CORS-safelistad, så headers.get('date') ger null cross-origin.
//
//  Saknas RPC:n (migration 0045 inte körd) eller är man offline står offset
//  kvar på 0 = exakt det gamla beteendet. Synken blir alltså aldrig sämre av
//  det här, bara bättre.

import { supabase } from './supabase'

// Flera stickprov – vi behåller det med kortast rundtur, eftersom osäkerheten
// i mätningen är ungefär halva rundturstiden.
const SAMPLES = 3

let offsetMs = 0
let syncPromise = null

/** Serverns "nu", uttryckt i samma tidsbas som Date.now(). */
export function serverNow() {
  return Date.now() + offsetMs
}

/** Hur fel enhetens klocka går, i ms (positivt = enheten ligger efter). */
export function clockOffsetMs() {
  return offsetMs
}

async function sample() {
  const t0 = Date.now()
  const { data, error } = await supabase.rpc('server_now')
  const t1 = Date.now()
  if (error || !data) return null
  const serverMs = Date.parse(data)
  if (!Number.isFinite(serverMs)) return null
  const rtt = t1 - t0
  // Servern läste sin klocka någonstans mitt i anropet → serverns tid vid t1
  // är ungefär avläsningen plus halva rundturen.
  return { offset: serverMs + rtt / 2 - t1, rtt }
}

/**
 * Mät klockskillnaden mot servern. Idempotent – första anropet gör jobbet,
 * senare anrop får samma löfte tillbaka.
 */
export function syncServerTime() {
  if (syncPromise) return syncPromise
  if (!supabase) return Promise.resolve(0)
  syncPromise = (async () => {
    let best = null
    for (let i = 0; i < SAMPLES; i++) {
      try {
        const s = await sample()
        if (s && (!best || s.rtt < best.rtt)) best = s
      } catch {
        /* offline e.d. – behåll den lokala klockan */
      }
    }
    if (best) offsetMs = Math.round(best.offset)
    return offsetMs
  })()
  return syncPromise
}
