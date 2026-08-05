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

// Värden startar en slumpad låt. HELT server-side: servern väljer låt ur
// potten, slår upp preview-klippet hos iTunes och sparar facit bakom
// reveal-spärren – ingen klient (inte ens värdens) ser svaret i förväg.
// pg_net är asynkront → steg 1 begär, steg 2 pollas tills rundan fått låten.
export async function startRandomTrack(roomId) {
  const { error } = await supabase.rpc('start_random_track', { p_room_id: roomId })
  if (error) throw translateDbError(error)
  // Adaptiv pollning: kolla tidigt och tätt (iTunes svarar oftast <1s) och backa
  // av till jämn takt. Pollningen är KLIENT-DRIVEN → fönstret måste rymma
  // serverns låtförsök (0036: 3) när ett remix-bara resultat hoppas över.
  //
  // Fönstret är satt efter serverns VÄRSTA fall, inte normalfallet: 3 låtar ×
  // 2 sökningar × 4s timeout = 24s. Med de tidigare 15s gav klienten upp med
  // "tog för lång tid" medan servern höll på och hittade en låt strax efter –
  // värden fick ett fel trots att allt fungerade. Normalfallet svarar ändå på
  // första pollen. Väl under rate-limitern (track_poll = 200/min).
  const ramp = [120, 150, 180, 220, 260, 300, 350, 400, 450, 500, 550, 600, 700]
  const steady = 700
  const maxMs = 26000
  let elapsed = 0
  for (let i = 0; elapsed < maxMs; i++) {
    const wait = i < ramp.length ? ramp[i] : steady
    await new Promise((resolve) => setTimeout(resolve, wait))
    elapsed += wait
    const { data, error: pollError } = await supabase.rpc('poll_track_start', {
      p_room_id: roomId,
    })
    if (pollError) throw translateDbError(pollError)
    if (data?.id) return data // klart – alla klienter startar via realtiden
  }
  throw new Error('Låtstarten tog för lång tid – försök igen.')
}

// Antal låtar per pott (lobbyns visning). Själva potten är oläsbar för klienter.
export async function trackPoolCounts() {
  const { data, error } = await supabase.rpc('track_pool_counts')
  if (error) throw translateDbError(error)
  return data
}

// Antal låtar per genreläge, till lobbyns kategoriknappar. Returnerar rader
// { genre, antal } – potten växer, så siffrorna hämtas i stället för hårdkodas.
export async function trackPoolGenreCounts() {
  const { data, error } = await supabase.rpc('track_pool_genre_counts')
  if (error) throw translateDbError(error)
  return Object.fromEntries((data || []).map((r) => [r.genre, Number(r.antal)]))
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
