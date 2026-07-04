import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// Appen ska kunna renderas och visa en tydlig setup-ruta även innan Supabase
// är konfigurerat. Därför skapar vi bara klienten om båda värdena finns.
export const isSupabaseConfigured = Boolean(url && anonKey)

export const supabase = isSupabaseConfigured
  ? createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // Fångar automatiskt tokens från magiska e-postlänkar när användaren
        // kommer tillbaka till appen (vår valfria kontoinloggning).
        detectSessionInUrl: true,
      },
    })
  : null
