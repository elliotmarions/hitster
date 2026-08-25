// Närbild + mätning av genrerutorna: får etiketten plats på en rad?
import { chromium } from 'playwright'
const BREDD = Number(process.env.BREDD || 390)
const OUT = process.argv[2] || `harness/shots/genre-${BREDD}.png`
const b = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  proxy: process.env.HTTPS_PROXY
    ? { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1,::1' }
    : undefined,
})
const ctx = await b.newContext({ viewport: { width: BREDD, height: 844 }, deviceScaleFactor: 2, ignoreHTTPSErrors: true })
const page = await ctx.newPage()
await page.goto('http://localhost:5199/harness.html?v=lobby', { waitUntil: 'load' })
await page.evaluate(() => document.fonts.ready).catch(() => {})
await page.click('text=Nej, var för sig', { timeout: 4000 }).catch(() => {})
await page.waitForSelector('button[aria-pressed]', { timeout: 10000 })
await page.waitForTimeout(400)

const matt = await page.evaluate(() => {
  const ut = []
  for (const knapp of document.querySelectorAll('button[aria-pressed]')) {
    const span = knapp.querySelector('span')
    if (!span) continue
    const r = knapp.getBoundingClientRect()
    const s = span.getBoundingClientRect()
    // Bredden texten SKULLE ta på en rad, mätt med en klon som inte får bryta.
    const klon = span.cloneNode(true)
    klon.style.position = 'absolute'
    klon.style.whiteSpace = 'nowrap'
    klon.style.visibility = 'hidden'
    document.body.appendChild(klon)
    const enRad = klon.getBoundingClientRect().width
    klon.remove()
    const st = getComputedStyle(knapp)
    const innerBredd = r.width - parseFloat(st.paddingLeft) - parseFloat(st.paddingRight)
    ut.push({
      text: span.textContent.trim(),
      ruta: Math.round(r.width),
      inner: Math.round(innerBredd),
      textEnRad: Math.round(enRad),
      rader: Math.round(s.height / parseFloat(getComputedStyle(span).lineHeight)),
      spiller: enRad > innerBredd + 0.5,
    })
  }
  return ut
})
for (const m of matt)
  console.log(
    `${m.spiller ? '⚠ ' : '  '}"${m.text}" ruta=${m.ruta} inner=${m.inner} text=${m.textEnRad}${m.spiller ? `  (${m.textEnRad - m.inner} px för brett)` : ''}`,
  )

const box = await page.evaluate(() => {
  const g = [...document.querySelectorAll('p')].find((p) => p.textContent.trim() === 'Genre')
  if (!g) return null
  const r = g.getBoundingClientRect()
  const sista = [...document.querySelectorAll('button[aria-pressed]')].pop()
  const s = sista.getBoundingClientRect()
  return {
    x: 8,
    y: r.top + window.scrollY - 6,
    width: window.innerWidth - 16,
    height: s.bottom - r.top + 14,
  }
})
if (box) await page.screenshot({ path: OUT, clip: box, fullPage: true })
else console.log('(hittade ingen Genre-rubrik att beskära mot)')
await b.close()
