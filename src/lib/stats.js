import { supabase } from './supabase'

/**
 * Hämtar den inloggade användarens statistik (spelade matcher + vinster).
 * RLS ser till att man bara kan läsa sin egen rad. Returnerar nollor om man
 * inte spelat något än.
 */
export async function getMyStats() {
  if (!supabase) return { games_played: 0, games_won: 0, games_tied: 0 }
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { games_played: 0, games_won: 0, games_tied: 0 }

  const { data, error } = await supabase
    .from('player_stats')
    .select('games_played, games_won, games_tied')
    .eq('user_id', user.id)
    .maybeSingle()
  if (error) throw error
  return {
    games_played: data?.games_played ?? 0,
    games_won: data?.games_won ?? 0,
    games_tied: data?.games_tied ?? 0,
  }
}
