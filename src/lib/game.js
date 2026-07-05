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

export async function resetGame(roomId, backToLobby = false) {
  const { error } = await supabase.rpc('reset_game', {
    p_room_id: roomId,
    p_back_to_lobby: backToLobby,
  })
  if (error) throw error
}

// --- Rena hjälpare (kosmetiskt på klienten; servern avgör vinst) ---

// Returnerar index för en full rad/kolumn om brickan har en vinstlinje, annars null.
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
  return null
}
