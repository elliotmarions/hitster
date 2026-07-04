/**
 * Visas när Supabase-nycklarna saknas. Gör setup uppenbar i stället för att
 * appen kraschar tyst.
 */
export default function SetupNotice() {
  const url = import.meta.env.VITE_SUPABASE_URL
  const key = import.meta.env.VITE_SUPABASE_ANON_KEY

  return (
    <div className="panel mx-auto max-w-xl p-6 sm:p-8">
      <h2 className="text-2xl neon-text" style={{ '--neon': '#ffc93c' }}>
        Nästan där – koppla Supabase
      </h2>
      <p className="mt-3 text-muted">
        Appen behöver din Supabase-anslutning för att skapa rum och köra realtid.
      </p>

      <ol className="mt-5 space-y-3 text-sm">
        <li className="flex gap-3">
          <span className="chip" style={{ '--neon': '#22e6e6' }}>1</span>
          <span>
            Skapa ett gratis projekt på{' '}
            <a className="text-cyan underline" href="https://supabase.com" target="_blank" rel="noreferrer">
              supabase.com
            </a>
            .
          </span>
        </li>
        <li className="flex gap-3">
          <span className="chip" style={{ '--neon': '#22e6e6' }}>2</span>
          <span>
            Kopiera <code>.env.example</code> till <code>.env.local</code> och fyll i{' '}
            <code>VITE_SUPABASE_URL</code> och <code>VITE_SUPABASE_ANON_KEY</code>{' '}
            (finns under Project Settings → API).
          </span>
        </li>
        <li className="flex gap-3">
          <span className="chip" style={{ '--neon': '#22e6e6' }}>3</span>
          <span>
            Kör databas-migrationen i <code>supabase/migrations/</code> (se README) och starta om{' '}
            <code>npm run dev</code>.
          </span>
        </li>
      </ol>

      <div className="panel-inset mt-6 p-3 text-xs">
        <div className="flex items-center justify-between">
          <span className="text-muted">VITE_SUPABASE_URL</span>
          <span className={url ? 'text-lime' : 'text-magenta'}>{url ? '✓ satt' : '✗ saknas'}</span>
        </div>
        <div className="mt-1.5 flex items-center justify-between">
          <span className="text-muted">VITE_SUPABASE_ANON_KEY</span>
          <span className={key ? 'text-lime' : 'text-magenta'}>{key ? '✓ satt' : '✗ saknas'}</span>
        </div>
      </div>
    </div>
  )
}
