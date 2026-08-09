import { supabase } from './supabase'
import { GRID } from './constants'
import { translateDbError } from './errors'

// --- RPC-wrappers (all spellogik är server-auktoritativ) ---

export async function startGame(roomId) {
  const { error } = await supabase.rpc('start_game', { p_room_id: roomId })
  if (error) throw translateDbError(error)
}

// Snurra discokulan → slumpad kategori (ingen musik än).
export async function spinWheel(roomId) {
  const { data, error } = await supabase.rpc('spin_wheel', { p_room_id: roomId })
  if (error) throw translateDbError(error)
  return data
}

// Adaptiv pollningstakt: kolla tidigt och tätt (iTunes svarar oftast <1s) och
// backa av till jämn takt. Väl under rate-limitern (track_poll = 200/min).
const POLL_RAMP = [120, 150, 180, 220, 260, 300, 350, 400, 450, 500, 550, 600, 700]
const POLL_STEADY = 700

// Ren säkerhetsventil, INTE en gissning på hur länge servern får hålla på.
// Förut räknade klienten ut ett eget fönster (26s) ur hur många försök servern
// gjorde – och räknade fel: servern köar fyra låtförsök × två söksteg, så den
// kunde fortfarande leta när klienten gav upp med "tog för lång tid".
// Serverns egen uppgivningslogik är den som vet när det är slut; den kastar
// 'Hittade ingen spelbar låt just nu' och då bryter loopen av sig själv.
const POLL_MAX_MS = 60000

/**
 * Driver ett pågående låtuppslag framåt tills rundan fått sin låt.
 *
 * Tillståndsmaskinen är klient-driven (pg_net är asynkront), så någon måste
 * fråga servern "är svaret framme?" om och om igen. Sedan 0077 får vilken
 * medlem som helst göra det, inte bara värden – backgroundade värden fliken
 * stod annars hela rummet still.
 *
 * Väggklockan, inte summan av väntetiderna, avgör när vi ger upp: stryper
 * webbläsaren timers i en bakgrundsflik ska taket ändå gälla i verklig tid.
 *
 * opts.intervalMs – fast takt i stället för rampen (reservpollare tar det lugnt)
 * opts.shouldStop – () => bool, avbryt tyst (t.ex. rundan bytte under tiden)
 */
export async function pollTrackStart(roomId, { intervalMs, shouldStop } = {}) {
  const start = Date.now()
  for (let i = 0; Date.now() - start < POLL_MAX_MS; i++) {
    const wait = intervalMs ?? (i < POLL_RAMP.length ? POLL_RAMP[i] : POLL_STEADY)
    await new Promise((resolve) => setTimeout(resolve, wait))
    if (shouldStop?.()) return null
    const { data, error } = await supabase.rpc('poll_track_start', { p_room_id: roomId })
    if (error) throw translateDbError(error)
    if (data?.id) return data // klart – alla klienter startar via realtiden
  }
  throw new Error('Låtstarten tog för lång tid – försök igen.')
}

// Värden startar en slumpad låt. HELT server-side: servern väljer låt ur
// potten, slår upp preview-klippet hos iTunes och sparar facit bakom
// reveal-spärren – ingen klient (inte ens värdens) ser svaret i förväg.
// pg_net är asynkront → steg 1 begär, steg 2 pollas tills rundan fått låten.
export async function startRandomTrack(roomId) {
  const { error } = await supabase.rpc('start_random_track', { p_room_id: roomId })
  if (error) throw translateDbError(error)
  return pollTrackStart(roomId)
}

// Antal låtar i EN specifik kombination (språk + årsfönster + genre). Behövs
// sedan "bara svenska" blev en modifierare: skärningen mellan två filter går
// inte att räkna ut ur de andra räknarna, och en nästan tom pott ska synas i
// lobbyn i stället för att upptäckas när snurren går i taket.
// Antal låtar i exakt det valda urvalet. bands/genres är listor (0057):
// union inom varje dimension, snitt mellan dimensionerna.
// swedish har tre lägen (0058): true = bara svenska, false = bara utländska,
// null/undefined = ingen språkgräns. Därför ?? och inte !!.
export async function trackPoolSelectionCount({ swedish, bands, genres }) {
  const { data, error } = await supabase.rpc('track_pool_selection_count', {
    p_swedish: swedish ?? null,
    p_bands: bands ?? [],
    p_genres: genres ?? [],
  })
  if (error) throw translateDbError(error)
  return Number(data)
}

export async function ensureCard(roomId) {
  const { data, error } = await supabase.rpc('ensure_card', { p_room_id: roomId })
  if (error) throw translateDbError(error)
  return data
}

export async function markCross(roomId, cellIndex) {
  const { data, error } = await supabase.rpc('mark_cross', {
    p_room_id: roomId,
    p_cell: cellIndex,
  })
  if (error) throw translateDbError(error)
  return data
}

// Ta bort ett eget kryss (ångra felklick). Servern tillåter bara din egen bricka.
export async function unmarkCross(roomId, cellIndex) {
  const { data, error } = await supabase.rpc('unmark_cross', {
    p_room_id: roomId,
    p_cell: cellIndex,
  })
  if (error) throw translateDbError(error)
  return data
}

export async function eraseCross(roomId, targetCardId, cellIndex) {
  const { data, error } = await supabase.rpc('erase_cross', {
    p_room_id: roomId,
    p_target_card: targetCardId,
    p_cell: cellIndex,
  })
  if (error) throw translateDbError(error)
  return data
}

// Lås in mitt svar för senaste rundan. Går så fort låten börjat spela – man
// behöver inte vänta ut klippet. När alla lag låst avslöjas svaren + facit för
// alla (servern sätter answers_revealed) och klienterna tystar låten.
// bonusYear = extrarutans årsgissning (0064). Bara i spel när suddregeln är på
// och rundans kategori inte redan handlar om årtal; annars tom sträng.
export async function lockAnswer(roomId, answer, bonusYear = '') {
  const { data, error } = await supabase.rpc('lock_answer', {
    p_room_id: roomId,
    p_answer: answer,
    p_bonus: bonusYear,
  })
  if (error) throw translateDbError(error)
  return data
}

// Värdens säkerhetsventil: avslöja svaren direkt även om något lag inte svarat.
export async function revealAnswers(roomId) {
  const { error } = await supabase.rpc('reveal_answers', { p_room_id: roomId })
  if (error) throw translateDbError(error)
}

// Värden överstyr en auto-bedömning. correct = true/false, eller null för att
// återgå till auto-domen.
export async function overrideAnswer(roomId, answerId, correct) {
  const { error } = await supabase.rpc('override_answer', {
    p_room_id: roomId,
    p_answer_id: answerId,
    p_correct: correct,
  })
  if (error) throw translateDbError(error)
}

export async function resetGame(roomId, backToLobby = false) {
  const { error } = await supabase.rpc('reset_game', {
    p_room_id: roomId,
    p_back_to_lobby: backToLobby,
  })
  if (error) throw translateDbError(error)
}

// --- Lagläge (bara värden) ---

export async function createTeam(roomId, name, color) {
  const { data, error } = await supabase.rpc('create_team', {
    p_room_id: roomId,
    p_name: name ?? null,
    p_color: color ?? null,
  })
  if (error) throw translateDbError(error)
  return data
}

export async function deleteTeam(roomId, teamId) {
  const { error } = await supabase.rpc('delete_team', {
    p_room_id: roomId,
    p_team_id: teamId,
  })
  if (error) throw translateDbError(error)
}

// Utse lagets kapten – den enda som får låsa in lagets svar. playerId = null
// tar bort kaptenen, och då får vem som helst i laget låsa igen.
export async function setTeamCaptain(roomId, teamId, playerId) {
  const { error } = await supabase.rpc('set_team_captain', {
    p_room_id: roomId,
    p_team_id: teamId,
    p_player_id: playerId ?? null,
  })
  if (error) throw translateDbError(error)
}

// Placera/flytta en spelare i ett lag. teamId = null → ta ur lag.
export async function assignPlayer(roomId, playerId, teamId) {
  const { error } = await supabase.rpc('assign_player', {
    p_room_id: roomId,
    p_player_id: playerId,
    p_team_id: teamId ?? null,
  })
  if (error) throw translateDbError(error)
}

// --- Lagchatt ---

// Skicka ett meddelande till mitt eget lag. Servern avgör vilket lag det
// hamnar i (utifrån min players-rad) – klienten kan inte välja mottagare.
export async function sendTeamMessage(roomId, body) {
  const { data, error } = await supabase.rpc('send_team_message', {
    p_room_id: roomId,
    p_body: body,
  })
  if (error) throw translateDbError(error)
  return data
}

// --- Rena hjälpare (kosmetiskt på klienten; servern avgör vinst) ---

// Returnerar index för en full rad/kolumn/diagonal om brickan har en
// vinstlinje, annars null.
export function winningLine(grid) {
  if (!grid) return null
  const filled = (i) => Boolean(grid[i]?.filled)
  for (let r = 0; r < GRID; r++) {
    const idx = Array.from({ length: GRID }, (_, c) => r * GRID + c)
    if (idx.every(filled)) return idx
  }
  for (let c = 0; c < GRID; c++) {
    const idx = Array.from({ length: GRID }, (_, r) => r * GRID + c)
    if (idx.every(filled)) return idx
  }
  // Diagonalerna: uppifrån-vänster → ner-höger, och uppifrån-höger → ner-vänster.
  const diag = Array.from({ length: GRID }, (_, i) => i * GRID + i)
  if (diag.every(filled)) return diag
  const anti = Array.from({ length: GRID }, (_, i) => i * GRID + (GRID - 1 - i))
  if (anti.every(filled)) return anti
  return null
}
