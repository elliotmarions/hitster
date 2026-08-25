import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Dev-server för harness.html (mobilgranskning). Inte del av prod-bygget.
const here = path.dirname(new URL(import.meta.url).pathname)

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
