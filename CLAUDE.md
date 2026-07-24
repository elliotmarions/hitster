# Hitster / Latsnurran

## Deploy-flöde (viktigt)

Prod-sajten **latsnurran.vercel.app** byggs av Vercel från branchen **`main`**.

**Stående regel:** När Elliot ber om en förändring ska den till prod. Det räcker
alltså inte att pusha feature-branchen – för att ändringen ska synas måste den nå
`main`. Standardflödet per ändring:

1. Utveckla på arbetsbranchen, verifiera att `npx vite build` går igenom.
2. Committa.
3. Fast-forward/merga in i `main` och `git push origin main` så Vercel bygger om.

Elliot har gett stående ok för detta – fråga inte om lov varje gång, pusha till
`main` som en del av att leverera ändringen (om inget annat sägs).

## Projektstruktur

- React + Vite frontend (`src/`), Supabase backend (`supabase/migrations/`).
- Rums-/spel-state speglas till klienter via Supabase Realtime
  (`postgres_changes`), se `src/hooks/useRoom.js` och `useGame.js`.
- Låtpotten bor i databasen och är **oläsbar för klienter** – all filtrering
  (språk, årsfönster/åldersgrupp) sker server-side i RPC:erna
  (`start_random_track`, `poll_track_start`).
