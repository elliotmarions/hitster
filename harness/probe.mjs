// Letar upp EXAKT vilket element som tvingar sidan bredare än telefonen:
// gömmer ett element i taget och ser om sidans bredd faller tillbaka.
import { chromium } from 'playwright'
const url = process.argv[2] || 'http://localhost:5199/harness.html?v=lobby'
const b = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  proxy: process.env.HTTPS_PROXY
    ? { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1,::1' }
    : undefined,
})
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, ignoreHTTPSErrors: true })
const page = await ctx.newPage()
await page.goto(url, { waitUntil: 'load' })
await page.evaluate(() => document.fonts.ready).catch(() => {})
await page.waitForTimeout(600)
const res = await page.evaluate(() => {
  const bredd = () => document.documentElement.scrollWidth
  const start = bredd()
  const ut = []
  for (const el of document.querySelectorAll('body *')) {
    const gammal = el.style.display
    el.style.display = 'none'
    const ny = bredd()
    el.style.display = gammal
    if (ny < start - 20) {
      ut.push({
        tagg: el.tagName.toLowerCase(),
        klass: (el.className?.baseVal ?? el.className ?? '').toString().slice(0, 70),
        text: (el.textContent || '').trim().slice(0, 46),
        djup: (() => { let d = 0, p = el; while ((p = p.parentElement)) d++; return d })(),
        utan: ny,
      })
    }
  }
  return { start, ut }
})
console.log('startbredd', res.start)
// Djupast (alltså mest specifika) sist – de översta är bara förfäder.
for (const e of res.ut.sort((a, x) => a.djup - x.djup))
  console.log(`d${e.djup} utan=${e.utan} <${e.tagg}.${e.klass}> "${e.text}"`)
await b.close()
