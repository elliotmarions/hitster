# 🪩 Låtsnurran

Spela **Låtsnurran** tillsammans på distans – musikquiz-bingo med discokula,
synkade musikklipp och brickor i realtid.

**Kärnidén:** ingen musik streamas mellan deltagarna och ingen behöver logga in.
Appen slumpar en låt ur en inbyggd pott (~3 000 verifierade låtar, eller en svensk
pott i "Svenskt läge"), slår upp ett publikt ~30-sekunders preview-klipp via
iTunes Search och startar **samma klipp hos alla samtidigt** via en synkad
tidsstämpel. Röst/video för häcklandet sköts utanför appen (Discord e.d.).

**Publik version:** https://latsnurran.vercel.app

---

## Spelet i korthet

1. Värden skapar ett rum och delar rumskoden. Alla spelar som gäst (anonym auth).
2. Värden snurrar **discokulan** → en av fem kategorier (årtionde, artist,
   exakt årtal, årtal ±3, låttitel) och trycker **Starta låt**.
3. Alla hör samma klipp och skriver sitt svar – **inlåsningen är öppen redan
   medan låten spelar**. När alla låst stoppas klippet direkt och svaren + facit
   avslöjas, och servern rättar automatiskt (värden kan överstyra).
4. Rätt svar ger **ett kryss** i en matchande ruta på 5×5-brickan. Full rad,
   kolumn eller diagonal vinner – flera vinster i samma runda blir **oavgjort**.
5. Extraregler: **suddregel** (pricka utgivningsåret så får du sudda ett kryss hos en
   motståndare – på kategorier som inte handlar om årtal via en **bonusruta** bredvid
   svaret, där exakt rätt år krävs och räknas oberoende av rundans egen fråga),
   **lagläge** (gemensam bricka + gemensamt svar per lag, plus en **privat lagchatt**
   där laget resonerar utan att motståndarna ser), **svenskt läge** (bara
   svenska låtar) och enkel **statistik** (spelade/vinster/oavgjorda) på `/statistik`.

---

## Teknik

- **Frontend:** React + Vite, Tailwind CSS v4 (UI på svenska)
- **Backend / realtid / auth:** Supabase (Postgres + Realtime + Auth, anonyma gäster)
- **Ljud:** iTunes Search API → publika preview-klipp i ett `<audio>`-element.
  Uppslagen cachas på pott-raden (`track_pool.preview_url`, 30 dagar) och låtar
  som inte går att hitta markeras och hoppas över i 7 dagar (`0066`, `0067`).
  Ett pg_cron-jobb betar av okontrollerade låtar i bakgrunden, 6 per minut, och
  pausar medan någon spelar (`0068`) – potten klassas alltså färdigt utan att
  någon behöver vänta. Stängs av med `select cron.unschedule('warm-pool-enqueue')`
  och `select cron.unschedule('warm-pool-collect')`.

  **Varför det behövs:** ~22 % av den svenska potten finns inte hos iTunes SE,
  och andelen är starkt ojämn – modern svensk hiphop (streamingfödd, aldrig
  såld som köpmusik) missar 77 %, medan pop från samma år missar 9 %. Ingen
  matchningsfix hjälper mot det; potten måste helt enkelt veta vad som går att
  spela.
- **Hosting:** Vercel (`git push` → auto-deploy)

All spellogik är **server-auktoritativ**: snurr, kryss, vinst, svarslåsning och
rättning sker i `SECURITY DEFINER`-RPC:er i Postgres (se `supabase/migrations/`).
Klienten animerar och speglar bara serverns sanning via Realtime.

---

## Kom igång lokalt

### 1. Installera beroenden

```bash
npm install
```

### 2. Sätt upp Supabase

1. Skapa ett gratis projekt på [supabase.com](https://supabase.com).
2. Kör migrationerna i `supabase/migrations/` i nummerordning – antingen i
   **SQL Editor**, eller automatiskt med `npm run migrate <fil>` (kräver
   `SUPABASE_DB_URL` i `.env.local`, se `.env.example`).
3. **Aktivera anonyma inloggningar** (krävs – appen loggar in gäster automatiskt):
   **Authentication → Sign In / Providers → Anonymous sign-ins → På**.

   Gästsessionen skapas först när någon **skapar eller går med i ett rum**, inte
   vid sidladdning. Skälet: Supabase strypar anonyma inloggningar till **30 per
   timme och IP-adress** och den gränsen går inte att höja, samtidigt som 70 % av
   gästerna i praktiken aldrig gick med i ett rum. Ett helt gäng på samma wifi
   delar på de 30 platserna, så potten ska inte gå åt till folk som bara tittar.
   All gästinloggning sker därför i `ensureSession()` i `AuthContext`; slår
   spärren till får användaren en begriplig förklaring i stället för ett RPC-fel.
4. **URL Configuration** (krävs för konto, bekräftelsemejl och lösenordsåterställning).
   Under **Authentication → URL Configuration**, sätt **Site URL** till din
   produktions-URL och lägg till dessa som **Redirect URLs**:
   - `http://127.0.0.1:5173` och `http://127.0.0.1:5173/nytt-losenord`
   - `https://latsnurran.vercel.app` och `https://latsnurran.vercel.app/nytt-losenord`

   Saknas `/nytt-losenord` i listan hamnar den som klickar på en
   återställningslänk på startsidan i stället, och kan aldrig byta lösenord.
5. **Bekräftelsemejl** – under **Authentication → Sign In / Providers → Email**
   styr **Confirm email** om nyregistrerade måste klicka i mejlet innan de kan
   logga in från en annan enhet. Appen klarar båda lägena: är det på visas
   "Kolla din mejl", är det av loggas man in direkt.
6. Hämta **Project URL** och **anon/public key** under **Project Settings → API**.

### 3. Miljövariabler

```bash
cp .env.example .env.local
```

```dotenv
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOi...
```

### 4. Starta

```bash
npm run dev
```

Öppna **http://127.0.0.1:5173**. Testa realtiden genom att öppna två fönster
(ett inkognito) och gå med i samma rum.

> Saknas Supabase-nycklarna visar appen en tydlig setup-ruta i stället för att krascha.

---

## Deploy till Vercel

1. Pusha repot till GitHub och importera det i Vercel (framework: **Vite**).
2. Lägg in `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` under
   **Settings → Environment Variables**.
3. `vercel.json` sköter SPA-routing för djuplänkar (t.ex. `/rum/ABCD1`) och
   sätter säkerhetsheaders (CSP m.m. – se nedan).
4. Uppdatera **Supabase Site URL / Redirect URLs** till din Vercel-domän.

---

## Säkerhetsmodell

Härdad i migration `0023_security_hardening.sql` (2026-07-16):

- **RLS på alla tabeller.** Bara ett rums medlemmar kan läsa dess data; svar är
  dolda för andra tills rundan avslöjats; lagchatten (`team_messages`, `0026`) är
  läsbar bara för det egna laget – även över realtidskanalen; statistik ser bara
  ägaren.
- **All skrivning via RPC:er.** Klienten har inga direkta INSERT/UPDATE/DELETE-
  rättigheter, med ETT undantag: värden får uppdatera exakt tre regel-kolumner
  på sitt eget rum (`erase_rule_enabled`, `team_mode`, `swedish_mode`) via
  kolumnbegränsad GRANT. Allt annat (inkl. vinnare/status) sätts av servern.
- **Indata-gränser server-side:** visningsnamn ≤ 40, rumsnamn ≤ 60, lagnamn ≤ 40,
  svar ≤ 300 tecken; lagfärg måste vara hex; ljud-URL måste vara `https://` och
  låt-metadata saneras till kända fält. Tak: 30 spelare/rum, 20 lag/rum,
  20 nya rum per värd och timme.
- **Kryptografiska rumskoder** (`gen_random_bytes`, 31⁵ ≈ 28,6 M kombinationer).
- **Rate limiting per användare** (`0027_rate_limits.sql`): varje RPC börjar med
  `perform public._rate_limit('<hink>', <tak>, interval '1 minute')` som räknar i
  tabellen `rate_limits` (unlogged, oåtkomlig för klienter). Överskridet tak ger
  SQLSTATE `PT429` → HTTP **429 Too Many Requests**. Taken per minut: låtstart 20,
  poll 200, snurr 30, kryss 60, svar 30, chatt 40, rumsskapande 5, rumsanslutning
  15 – plus en global hink på 400/min. En hel spelrunda kostar ~10 anrop, så
  vanligt spelande når aldrig taken. Gamla räknare städas varje timme av pg_cron.
- **Funktionsrättigheter:** PUBLIC/anon-execute är återkallat på alla RPC:er
  (bara `authenticated`). OBS för nya migrationer: default privileges är ändrade
  → varje ny funktion måste själv `grant execute ... to authenticated`.
- **HTTP-headers via `vercel.json`:** Content-Security-Policy (ingen extern JS,
  connect bara till Supabase/iTunes), `frame-ancestors 'none'`, nosniff, HSTS.
- **Städning:** pg_cron raderar rum äldre än 30 dagar varje natt (cascade tar
  spelare/rundor/brickor/svar/lag; statistiken behålls).
- **Samtidighet** (`0028_concurrency_locks.sql`): `lock_answer` låser rundan och
  `mark_cross`/`unmark_cross` låser rummet (`select … for update`) innan de läser
  räkneverk och vinnarlista. Utan låsen läste samtidiga spelare var sin föråldrad
  bild och den som skrev sist vann – sex samtidiga inlåsningar gav `locked_count`
  = 2 och rundan låste sig. Verifierat med sex parallella databasanslutningar.

**Medveten begränsning (rate limiting):** ett PostgREST-anrop är en transaktion,
så ett kastat fel rullar tillbaka även räknarens ökning. Anrop som ändå
misslyckas av annan orsak ("Bara värden kan …") räknas alltså inte – de är
billiga, indexerade uppslag och kräver dessutom ett känt rums-UUID. Undantaget
är `join_room`, där de misslyckade försöken *är* attacken (gissa rumskoder): den
returnerar därför `null` i stället för att kasta, så varje försök räknas. Riktig
kantspärr kräver ett lager framför PostgREST – klienten pratar direkt med
Supabase, inte via Vercel, så `vercel.json` hjälper inte där.

**Medveten begränsning (hederssystem):** facit för pågående runda
(`rounds.current_track_meta`) är tekniskt läsbart för rummets medlemmar via
API:et medan låten spelar, och preview-URL:en avslöjar ändå låten för den som
slår upp den. Att helt stoppa en tekniskt kunnig fuskare kräver server-side-ljud
– medvetet utanför spelets ambition.

---

## Projektstruktur

```
hitster-bingo-online/
├─ src/
│  ├─ lib/            supabase-klient, spelkonstanter, RPC-wrappers, iTunes-sök
│  ├─ context/        AuthContext – anonym gäst + konto (lösenord/magisk länk)
│  ├─ hooks/          useRoom/useGame (realtid), useSyncedAudio (synkat ljud)
│  ├─ components/     spelvyer (lobby/spel), bricka, discokula, svarspanel, ui/*
│  ├─ pages/          LandingPage, RoomPage, ProfilePage, AuthPage, ResetPasswordPage
│  ├─ data/           låtpotter (lazy-laddade chunkar): tracks.js, swedishTracks.js
│  └─ main.jsx        router + providers
├─ supabase/migrations/   SQL-migrationer i nummerordning (körs med npm run migrate)
├─ scripts/migrate.mjs    kör en migrationsfil i en transaktion mot SUPABASE_DB_URL
├─ .env.example
└─ vercel.json            SPA-routing + säkerhetsheaders (CSP m.m.)
```

### Verktyg för låtpotten

Tre skript för att utöka och kontrollera potten. De två sista behöver bara
anon-nyckeln, inte databaslösenordet.

```bash
# Vilka kandidater går att SPELA? Kör dem genom serverns egen matchning
# (_clean_title -> iTunes-sökningen -> _itunes_pick) och släpp bara igenom
# de som ger en preview-URL. Ut kommer rader klara för en insert-migration.
node scripts/check-playable.mjs kandidater.json

# Stämmer årtalen? Prövas mot MusicBrainz (release-group typ Single) och
# Discogs. --detalj visar pressningarna, vilket är det som skiljer
# "källan känner bara en återutgåva" från "vårt år är fel".
node scripts/check-years.mjs latar.json --detalj

# Vad kommer faktiskt upp? Skapar ett riktigt rum, sätter urvalet, spelar
# rundor och läser facit. Flera --span mäter viktningen mellan spann.
node scripts/play-test.mjs --span 1950-1960 --rundor 12
```

---

## Design

80-tals synthwave/nattklubb – midnattssvart bas med neon per kategori
(lila = årtiondet, gul = artisten, rosa = exakt årtal, blå = årtal ±3 år,
grön = låttiteln). Typsnitt: Monoton (logga), Righteous (rubriker),
Space Grotesk (brödtext).
