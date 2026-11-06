import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Dev-server för harness.html (mobilgranskning). Inte del av prod-bygget.
// fileURLToPath, inte URL.pathname: på Windows blir pathname "/C:/..." med
// %20 för mellanslagen, och då hittar inga alias sina attrapper.
const here = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { host: true, port: 5199 },
  resolve: {
    alias: [
      { find: /^\.\/supabase(\.js)?$/, replacement: path.join(here, 'harness/fake-supabase.js') },
      { find: /^.*\/lib\/supabase(\.js)?$/, replacement: path.join(here, 'harness/fake-supabase.js') },
      { find: /^.*\/hooks\/useGame\.js$/, replacement: path.join(here, 'harness/fake-hooks.js') },
      { find: /^.*\/hooks\/useSyncedAudio\.js$/, replacement: path.join(here, 'harness/fake-hooks.js') },
      { find: /^.*\/hooks\/useTeamChat\.js$/, replacement: path.join(here, 'harness/fake-hooks.js') },
    ],
  },
})
