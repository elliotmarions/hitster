import { supabase } from './supabase'
import { translateDbError } from './errors'

// Normaliserar en inklistrad rumskod: versaler, utan mellanslag/bindestreck.
export function normalizeCode(input) {
  return (input || '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

// Alla skrivningar mot rum går via SECURITY DEFINER-RPC:er i databasen.
// Det löser "hönan-och-ägget" med Row Level Security: man måste kunna slå upp
// ett rum via kod INNAN man är medlem, utan att kunna läsa alla andras rum.

// Skapar ett nytt rum + lägger till dig som värd. Returnerar rums-raden.
export async function createRoom({ name, displayName }) {
  const { data, error } = await supabase.rpc('create_room', {
    p_name: name?.trim() || null,
    p_display_name: displayName.trim(),
  })
  if (error) throw translateDbError(error)
  return data
}

// Går med i ett befintligt rum via kod. Returnerar rums-raden.
// Okänd kod ger null (inte ett fel) från RPC:n – se migration 0027: ett kastat
// fel hade rullat tillbaka anropets rate limit-räknare och gjort det gratis att
// botta sig igenom rumskoder.
export async function joinRoom({ code, displayName }) {
  const { data, error } = await supabase.rpc('join_room', {
    p_code: normalizeCode(code),
    p_display_name: displayName.trim(),
  })
  if (error) throw translateDbError(error)
  if (!data?.code) throw new Error('Hittade inget rum med den koden.')
  return data
}

// Lämnar ett rum via RPC:n leave_room: raderar din spelar-rad, och om det är
// VÄRDEN som lämnar avslutas spelet för alla (status='finished',
// ended_reason='host_left'). Se migration 0018.
export async function leaveRoom(roomId) {
  const { error } = await supabase.rpc('leave_room', { p_room_id: roomId })
  if (error) throw translateDbError(error)
}

// Värden rensar bort en spelare som tappat anslutningen (se 0059). Frånvaron
// syns bara i Realtime Presence, så det är klienten som pekar ut raden –
// servern kontrollerar att det är värden, att rummet är i lobbyn och att det
// inte är värden själv.
export async function removeAbsentPlayer(roomId, playerId) {
  const { error } = await supabase.rpc('remove_absent_player', {
    p_room_id: roomId,
    p_player_id: playerId,
  })
  if (error) throw translateDbError(error)
}

// Hjärtslag: håller min last_seen_at färsk medan jag sitter i lobbyn, så att
// servern kan avgöra om VÄRDEN försvunnit (se close_room_if_host_absent).
//
// Notera att det inte finns någon pagehide-hanterare som lämnar rummet när
// fliken stängs. Det vore den uppenbara lösningen och den är fel: pagehide
// utlöses även av en vanlig omladdning, så F5 hade raderat spelaren – och
// för en värd stängt hela rummet – utan att någon lämnat något.
export async function touchLastSeen(roomId) {
  const { error } = await supabase.rpc('touch_last_seen', { p_room_id: roomId })
  if (error) throw translateDbError(error)
}

// Ber servern kontrollera om värden är borta och i så fall stänga rummet.
// Klienten påstår ingenting – servern avgör på värdens hjärtslagsstämpel.
export async function closeRoomIfHostAbsent(roomId) {
  const { data, error } = await supabase.rpc('close_room_if_host_absent', {
    p_room_id: roomId,
  })
  if (error) throw translateDbError(error)
  return Boolean(data)
}
