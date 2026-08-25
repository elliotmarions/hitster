// Skjuter skärmbilder av varje vy i telefonbredd och letar efter innehåll som
// sticker ut utanför skärmen. Kör: node harness/shots.mjs [utmapp]
import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'

const OUT = process.argv[2] || 'harness/shots'
const BAS = 'http://localhost:5199/harness.html'
const BREDD = Number(process.env.BREDD || 390)

const vyer = [
  { namn: 'landing', url: `${BAS}?v=landing` },
  { namn: 'joingate', url: `${BAS}?v=joingate` },
  { namn: 'lobby', url: `${BAS}?v=lobby` },
  { namn: 'lobby-lag', url: `${BAS}?v=lobby&lag=1` },
  { namn: 'lobby-hjul', url: `${BAS}?v=lobby`, klick: 'text=Nej, var för sig', klick2: 'text=Vidare: välj hjul' },
  { namn: 'lobby-hjul-bygg', url: `${BAS}?v=lobby`, klick: 'text=Nej, var för sig', klick2: 'text=Vidare: välj hjul', klick3: 'text=Bygg själv' },
  { namn: 'spel', url: `${BAS}?v=spel` },
  { namn: 'spel-lag', url: `${BAS}?v=spel&lag=1` },
  { namn: 'spel-facit', url: `${BAS}?v=spel-facit` },
  { namn: 'spel-genre', url: `${BAS}?v=spel&kat=genre` },
  { namn: 'spel-foreefter', url: `${BAS}?v=spel&kat=before_after` },
  { namn: 'spel-chatt', url: `${BAS}?v=spel&lag=1`, klick: '[aria-label="Öppna lagchatten"]' },
  { namn: 'regler', url: `${BAS}?v=spel`, klick: '[aria-label="Så spelar man"]' },
  { namn: 'konto', url: `${BAS}?v=konto` },
  { namn: 'konto-gast', url: `${BAS}?v=konto&gast=1` },
  { namn: 'konto-nytt', url: `${BAS}?v=konto&gast=1`, klick: 'text=Skapa konto' },
  { namn: 'profil', url: `${BAS}?v=profil` },
  { namn: 'integritet', url: `${BAS}?v=integritet` },
  { namn: 'nytt-losenord', url: `${BAS}?v=nytt-losenord` },
]

// Vad sticker ut? Alla element vars högerkant ligger utanför viewporten, eller
// som i sig är bredare än den.
const HITTA_SPILL = (bredd) => {
  const ut = []
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect()
    if (r.width === 0 && r.height === 0) continue
    const st = getComputedStyle(el)
    if (st.position === 'fixed') continue
    if (r.right > bredd + 1 || r.left < -1 || r.width > bredd + 1) {
      ut.push({
        tagg: el.tagName.toLowerCase(),
        klass: (el.className?.baseVal ?? el.className ?? '').toString().slice(0, 90),
        text: (el.textContent || '').trim().slice(0, 50),
        vanster: Math.round(r.left),
        hoger: Math.round(r.right),
        bredd: Math.round(r.width),
      })
    }
  }
  return {
    scrollWidth: document.documentElement.scrollWidth,
    innerWidth: window.innerWidth,
    element: ut.slice(0, 8),
  }
}

// För små tryckytor: allt klickbart under 40 px i höjd eller bredd.
const SMA_TRYCKYTOR = () => {
  const ut = []
  for (const el of document.querySelectorAll('button, a, input[type=checkbox], [role=button]')) {
    const r = el.getBoundingClientRect()
    if (r.width === 0 || r.height === 0) continue
    if (r.height < 36 || r.width < 36) {
      ut.push({
        tagg: el.tagName.toLowerCase(),
        text: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 34),
        b: Math.round(r.width),
        h: Math.round(r.height),
      })
    }
  }
  return ut.slice(0, 14)
}

mkdirSync(OUT, { recursive: true })
const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  proxy: process.env.HTTPS_PROXY
    ? { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1,::1' }
    : undefined,
})
const ctx = await browser.newContext({
  viewport: { width: BREDD, height: 844 },
  deviceScaleFactor: 1,
  isMobile: true,
  hasTouch: true,
  ignoreHTTPSErrors: true,
})
const page = await ctx.newPage()
const fel = []
page.on('pageerror', (e) => fel.push(String(e)))

const rapport = []
for (const vy of vyer) {
  fel.length = 0
  await page.goto(vy.url, { waitUntil: 'load' })
  await page.evaluate(() => document.fonts.ready).catch(() => {})
  await page.waitForTimeout(400)
  if (vy.klick) {
    await page.click(vy.klick, { timeout: 4000 }).catch((e) => fel.push(`klick misslyckades: ${e.message.split('\n')[0]}`))
    await page.waitForTimeout(400)
  }
  if (vy.klick2) {
    await page.click(vy.klick2, { timeout: 4000 }).catch((e) => fel.push(`klick2 misslyckades: ${e.message.split('\n')[0]}`))
    await page.waitForTimeout(400)
  }
  if (vy.klick3) {
    await page.click(vy.klick3, { timeout: 4000 }).catch((e) => fel.push(`klick3 misslyckades: ${e.message.split('\n')[0]}`))
    await page.waitForTimeout(400)
  }
  await page.screenshot({ path: `${OUT}/${BREDD}-${vy.namn}.png`, fullPage: true })
  const spill = await page.evaluate(HITTA_SPILL, BREDD)
  const sma = await page.evaluate(SMA_TRYCKYTOR)
  rapport.push({ vy: vy.namn, spill, sma, fel: [...fel] })
  skrivUt(rapport[rapport.length - 1])
}

function skrivUt(r) {
  const overflow = r.spill.scrollWidth > r.spill.innerWidth
  console.log(`\n=== ${r.vy} (${BREDD}px) ===`)
  console.log(`  scrollWidth=${r.spill.scrollWidth} innerWidth=${r.spill.innerWidth}${overflow ? '  ⚠ SIDAN SCROLLAR I SIDLED' : ''}`)
  if (r.spill.element.length) {
    console.log('  Element utanför skärmen:')
    for (const e of r.spill.element)
      console.log(`   - <${e.tagg}> [${e.vanster}..${e.hoger}] b=${e.bredd} "${e.text}" .${e.klass}`)
  }
  if (r.sma.length) {
    console.log('  Små tryckytor (<36px):')
    for (const s of r.sma) console.log(`   - <${s.tagg}> ${s.b}x${s.h} "${s.text}"`)
  }
  if (r.fel.length) console.log('  JS-fel:', r.fel)
}

await browser.close()
