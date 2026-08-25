# Mobilharness

En dev-only miljö för att granska varje vy i telefonbredd utan riktig Supabase.
Ingår **inte** i produktionsbygget (`vite build` läser bara `index.html`), och
`playwright` ligger medvetet inte i `package.json` – annars hade Vercel laddat
ned en Chromium vid varje deploy.

## Kör

```bash
npm i --no-save playwright          # bara första gången
npx vite --config vite.harness.config.js   # startar på :5199
node harness/shots.mjs              # skärmbilder + rapport till harness/shots/
BREDD=360 node harness/shots.mjs    # smalare telefon
node harness/probe.mjs              # pekar ut vilket element som spränger bredden
```

`shots.mjs` skriver ut två saker per vy:

- **scrollWidth vs innerWidth** – är de olika scrollar sidan i sidled, och då
  zoomar telefonen ut hela gränssnittet. Det ska aldrig hända.
- **små tryckytor** – klickbara element under 36 px.

## Så hänger det ihop

`vite.harness.config.js` byter ut `lib/supabase`, `useGame`, `useSyncedAudio`
och `useTeamChat` mot attrapper i den här mappen, så vyerna kan renderas med
påhittad data. `harness/main.jsx` väljer vy via `?v=` (se listan i `shots.mjs`).
