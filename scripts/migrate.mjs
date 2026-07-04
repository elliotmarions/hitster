// Kör en SQL-migration direkt mot Supabase-databasen.
// Användning:  node scripts/migrate.mjs supabase/migrations/0003_five_categories.sql
//
// Läser SUPABASE_DB_URL från .env.local (INTE VITE_-prefixad → hamnar aldrig i
// frontend-bundlen). Anslutningssträngen ger full DB-åtkomst = hemlig, och
// .env.local är gitignorerad.
import { readFileSync } from 'node:fs'
import pg from 'pg'

// Liten .env.local-läsare så vi slipper extra beroenden.
function loadEnvLocal() {
  try {
    const txt = readFileSync(new URL('../.env.local', import.meta.url), 'utf8')
    for (const line of txt.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$/)
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim()
    }
  } catch {
    /* ingen .env.local – strunt i det */
  }
}
loadEnvLocal()

const url = process.env.SUPABASE_DB_URL
const file = process.argv[2]

if (!url) {
  console.error('✗ Saknar SUPABASE_DB_URL i .env.local (se .env.example).')
  process.exit(1)
}
if (!file) {
  console.error('✗ Ange migrationsfil, t.ex.: node scripts/migrate.mjs supabase/migrations/0003_five_categories.sql')
  process.exit(1)
}

const sql = readFileSync(file, 'utf8')
const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })

try {
  await client.connect()
  await client.query('begin')
  await client.query(sql) // hela filen körs i en transaktion (allt eller inget)
  await client.query('commit')
  console.log('✓ Migration körd:', file)
} catch (e) {
  try {
    await client.query('rollback')
  } catch {
    /* noop */
  }
  console.error('✗ Migration misslyckades:', e.message)
  process.exitCode = 1
} finally {
  await client.end()
}
