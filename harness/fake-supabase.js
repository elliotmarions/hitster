// Mock av Supabase-klienten – bara till mobil-harnessen (harness.html).
// Ingår aldrig i produktionsbygget.
export const isSupabaseConfigured = true

const RESULT = { data: [{ ok: true }], error: null }

const params = new URLSearchParams(window.location.search)
const ANTAL = Number(params.get('antal') ?? 12483)

function chain(result) {
  const fn = () => chain(result)
  return new Proxy(fn, {
    get(_t, prop) {
      if (prop === 'then') return (res, rej) => Promise.resolve(result).then(res, rej)
      if (prop === 'catch') return (rej) => Promise.resolve(result).catch(rej)
      if (prop === 'finally') return (f) => Promise.resolve(result).finally(f)
      return () => chain(result)
    },
    apply() {
      return chain(result)
    },
  })
}

// ?gast=1 – utloggad/gäst, så inloggningsformulären går att granska.
const gast = params.get('gast') === '1'
const user = { id: 'u-me', email: 'elliot@example.com', is_anonymous: gast }
const session = gast ? null : { user, access_token: 'x' }

export const supabase = {
  from: () => chain(RESULT),
  rpc: (name) => chain({ data: name === 'track_pool_selection_count' ? ANTAL : null, error: null }),
  channel: () => {
    const ch = { on: () => ch, subscribe: () => ch, unsubscribe: () => {}, send: () => {} }
    return ch
  },
  removeChannel: () => {},
  auth: {
    getSession: async () => ({ data: { session }, error: null }),
    getUser: async () => ({ data: { user }, error: null }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    signInAnonymously: async () => ({ data: { session }, error: null }),
    signInWithPassword: async () => ({ data: { session }, error: null }),
    signInWithOtp: async () => ({ data: {}, error: null }),
    signUp: async () => ({ data: { session }, error: null }),
    updateUser: async () => ({ data: { user }, error: null }),
    resetPasswordForEmail: async () => ({ error: null }),
    signOut: async () => ({ error: null }),
  },
}
