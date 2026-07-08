import { supabase } from './supabase'
import { GRID } from './constants'

// --- RPC-wrappers (all spellogik är server-auktoritativ) ---

export async function startGame(roomId) {
  const { error } = await supabase.rpc('start_game', { p_room_id: roomId })
  if (error) throw error
}

// Snurra discokulan → slumpad kategori (ingen musik än).
export async function spinWheel(roomId) {
  const { data, error } = await supabase.rpc('spin_wheel', { p_room_id: roomId })
  if (error) throw error
  return data
}

// Värden startar en (slumpad) låt för senaste rundan → synkad uppspelning + 25s-timer hos alla.
export async function startTrack(roomId, trackUri, trackMeta) {
  const { data, error } = await supabase.rpc('start_track', {
    p_room_id: roomId,
    p_track_uri: trackUri,
    p_track_meta: trackMeta,
  })
  if (error) throw error
  return data
}

export async function ensureCard(roomId) {
  const { data, error } = await supabase.rpc('ensure_card', { p_room_id: roomId })
  if (error) throw error
  return data
}

export async function markCross(roomId, cellIndex) {
  const { data, error } = await supabase.rpc('mark_cross', {
    p_room_id: roomId,
    p_cell: cellIndex,
  })
  if (error) throw error
  return data
}

// Ta bort ett eget kryss (ångra felklick). Servern tillåter bara din egen bricka.
export async function unmarkCross(roomId, cellIndex) {
  const { data, error } = await supabase.rpc('unmark_cross', {
    p_room_id: roomId,
    p_cell: cellIndex,
  })
  if (error) throw error
  return data
}

export async function eraseCross(roomId, targetCardId, cellIndex) {
  const { data, error } = await supabase.rpc('erase_cross', {
    p_room_id: roomId,
    p_target_card: targetCardId,
    p_cell: cellIndex,
  })
  if (error) throw error
  return data
}

// Lås in mitt svar för senaste rundan (går bara efter att låten spelat klart).
// När alla lag låst avslöjas svaren + facit för alla (servern sätter answers_revealed).
export async function lockAnswer(roomId, answer) {
  const { data, error } = await supabase.rpc('lock_answer', {
    p_room_id: roomId,
    p_answer: answer,
  })
  if (error) throw error
  return data
}

// Värdens säkerhetsventil: avslöja svaren direkt även om något lag inte svarat.
export async function revealAnswers(roomId) {
  const { error } = await supabase.rpc('reveal_answers', { p_room_id: roomId })
  if (error) throw error
}

// Värden överstyr en auto-bedömning. correct = true/false, eller null för att
// återgå till auto-domen.
export async function overrideAnswer(roomId, answerId, correct) {
  const { error } = await supabase.rpc('override_answer', {
    p_room_id: roomId,
    p_answer_id: answerId,
    p_correct: correct,
  })
  if (error) throw error
}

export async function resetGame(roomId, backToLobby = false) {
  const { error } = await supabase.rpc('reset_game', {
    p_room_id: roomId,
    p_back_to_lobby: backToLobby,
  })
  if (error) throw error
}

// --- Lagläge (bara värden) ---

export async function createTeam(roomId, name, color) {
  const { data, error } = await supabase.rpc('create_team', {
    p_room_id: roomId,
    p_name: name ?? null,
    p_color: color ?? null,
  })
  if (error) throw error
  return data
}

export async function deleteTeam(roomId, teamId) {
  const { error } = await supabase.rpc('delete_team', {
    p_room_id: roomId,
    p_team_id: teamId,
  })
  if (error) throw error
}

// Placera/flytta en spelare i ett lag. teamId = null → ta ur lag.
export async function assignPlayer(roomId, playerId, teamId) {
  const { error } = await supabase.rpc('assign_player', {
    p_room_id: roomId,
    p_player_id: playerId,
    p_team_id: teamId ?? null,
  })
  if (error) throw error
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
