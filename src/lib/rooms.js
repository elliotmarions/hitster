import { supabase } from './supabase'

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
  if (error) throw error
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
  if (error) throw error
  if (!data?.code) throw new Error('Hittade inget rum med den koden.')
  return data
}

// Lämnar ett rum via RPC:n leave_room: raderar din spelar-rad, och om det är
// VÄRDEN som lämnar avslutas spelet för alla (status='finished',
// ended_reason='host_left'). Se migration 0018.
export async function leaveRoom(roomId) {
  const { error } = await supabase.rpc('leave_room', { p_room_id: roomId })
  if (error) throw error
}
