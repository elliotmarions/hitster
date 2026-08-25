// Närbild på årtalsväljaren – för att kunna jämföra färgstyrkan.
import { chromium } from 'playwright'
const OUT = process.argv[2] || 'harness/shots/tidslinje.png'
const b = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  proxy: process.env.HTTPS_PROXY
    ? { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1,::1' }
    : undefined,
})
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, ignoreHTTPSErrors: true })
const page = await ctx.newPage()
await page.goto('http://localhost:5199/harness.html?v=lobby', { waitUntil: 'load' })
await page.evaluate(() => document.fonts.ready).catch(() => {})
await page.click('text=Nej, var för sig', { timeout: 4000 }).catch(() => {})
await page.waitForTimeout(400)
// Rutan från "Årtal"-rubriken ned till sista tidslinjen, plus genrechipen
// under så att styrkan går att jämföra mot dem.
const box = await page.evaluate(() => {
  const rubrik = [...document.querySelectorAll('p')].find((p) => p.textContent.trim() === 'Årtal')
  const genre = [...document.querySelectorAll('p')].find((p) => p.textContent.trim() === 'Genre')
  const a = rubrik.getBoundingClientRect()
  const g = genre.getBoundingClientRect()
  return { x: 8, y: a.top + window.scrollY - 8, width: 374, height: g.bottom - a.top + 90 }
})
await page.screenshot({ path: OUT, clip: box })
await b.close()
