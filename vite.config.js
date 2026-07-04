import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    // host: true gör att andra enheter i samma nätverk (t.ex. mobil) kan öppna dev-servern.
    host: true,
    port: 5173,
  },
})
