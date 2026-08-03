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

// OBS: vi går medvetet förbi supabase-js och anropar RPC:n med rå fetch.
// Klienten köar sina anrop bakom auth-initieringen, vilket gjorde att
// mätningen blev klar först många sekunder efter sidladdning – och startade
// en runda innan dess användes fortfarande enhetens felgående klocka.
// server_now() är grantad till anon, så apikey-headern räcker.
const URL_BASE = import.meta.env.VITE_SUPABASE_URL
const ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

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
  const res = await fetch(URL_BASE.replace(/\/+$/, '') + '/rest/v1/rpc/server_now', {
    method: 'POST',
    headers: {
      apikey: ANON_KEY,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: '{}',
    cache: 'no-store',
  })
  const t1 = Date.now()
  if (!res.ok) return null
  const serverMs = Date.parse(await res.json())
  if (!Number.isFinite(serverMs)) return null
  const rtt = t1 - t0
  // Servern läste sin klocka någonstans mitt i anropet → serverns tid vid t1
  // är ungefär avläsningen plus halva rundturen.
  return { offset: serverMs + rtt / 2 - t1, rtt }
}

/**
 * Mät klockskillnaden mot servern. En LYCKAD mätning cachas och återanvänds;
 * en misslyckad gör det inte, så nästa anropare får försöka igen (annars hade
 * ett enda hicka vid sidladdning låst appen till fel klocka för all framtid).
 */
export function syncServerTime() {
  if (syncPromise) return syncPromise
  if (!URL_BASE || !ANON_KEY) return Promise.resolve(0)
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
    if (!best) {
      syncPromise = null // misslyckades – tillåt ett nytt försök
      return 0
    }
    offsetMs = Math.round(best.offset)
    return offsetMs
  })()
  return syncPromise
}
