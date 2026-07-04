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
export async function joinRoom({ code, displayName }) {
  const { data, error } = await supabase.rpc('join_room', {
    p_code: normalizeCode(code),
    p_display_name: displayName.trim(),
  })
  if (error) throw error
  return data
}

// Lämnar ett rum (raderar din spelar-rad). RLS tillåter bara att man raderar sin egen.
export async function leaveRoom(roomId) {
  const { data: userData } = await supabase.auth.getUser()
  const uid = userData?.user?.id
  if (!uid) return
  const { error } = await supabase
    .from('players')
    .delete()
    .eq('room_id', roomId)
    .eq('user_id', uid)
  if (error) throw error
}
