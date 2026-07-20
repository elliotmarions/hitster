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
3. Alla hör samma klipp, skriver sitt svar och **låser in**. När alla låst
   avslöjas svaren + facit, och servern rättar automatiskt (värden kan överstyra).
4. Rätt svar ger **ett kryss** i en matchande ruta på 5×5-brickan. Full rad,
   kolumn eller diagonal vinner – flera vinster i samma runda blir **oavgjort**.
5. Extraregler: **suddregel** (rätt "exakt årtal" låter dig sudda hos en motståndare),
   **lagläge** (gemensam bricka + gemensamt svar per lag), **svenskt läge** (bara
   svenska låtar) och enkel **statistik** (spelade/vinster/oavgjorda) på `/statistik`.

---

## Teknik

- **Frontend:** React + Vite, Tailwind CSS v4 (UI på svenska)
- **Backend / realtid / auth:** Supabase (Postgres + Realtime + Auth, anonyma gäster)
- **Ljud:** iTunes Search API → publika preview-klipp i ett `<audio>`-element
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
  dolda för andra tills rundan avslöjats; statistik ser bara ägaren.
- **All skrivning via RPC:er.** Klienten har inga direkta INSERT/UPDATE/DELETE-
  rättigheter, med ETT undantag: värden får uppdatera exakt tre regel-kolumner
  på sitt eget rum (`erase_rule_enabled`, `team_mode`, `swedish_mode`) via
  kolumnbegränsad GRANT. Allt annat (inkl. vinnare/status) sätts av servern.
- **Indata-gränser server-side:** visningsnamn ≤ 40, rumsnamn ≤ 60, lagnamn ≤ 40,
  svar ≤ 300 tecken; lagfärg måste vara hex; ljud-URL måste vara `https://` och
  låt-metadata saneras till kända fält. Tak: 30 spelare/rum, 20 lag/rum,
  20 nya rum per värd och timme.
- **Kryptografiska rumskoder** (`gen_random_bytes`, 31⁵ ≈ 28,6 M kombinationer).
- **Funktionsrättigheter:** PUBLIC/anon-execute är återkallat på alla RPC:er
  (bara `authenticated`). OBS för nya migrationer: default privileges är ändrade
  → varje ny funktion måste själv `grant execute ... to authenticated`.
- **HTTP-headers via `vercel.json`:** Content-Security-Policy (ingen extern JS,
  connect bara till Supabase/iTunes), `frame-ancestors 'none'`, nosniff, HSTS.
- **Städning:** pg_cron raderar rum äldre än 30 dagar varje natt (cascade tar
  spelare/rundor/brickor/svar/lag; statistiken behålls).

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
│  ├─ pages/          LandingPage, RoomPage, StatsPage, AuthPage, ResetPasswordPage
│  ├─ data/           låtpotter (lazy-laddade chunkar): tracks.js, swedishTracks.js
│  └─ main.jsx        router + providers
├─ supabase/migrations/   SQL-migrationer i nummerordning (körs med npm run migrate)
├─ scripts/migrate.mjs    kör en migrationsfil i en transaktion mot SUPABASE_DB_URL
├─ .env.example
└─ vercel.json            SPA-routing + säkerhetsheaders (CSP m.m.)
```

---

## Design

80-tals synthwave/nattklubb – midnattssvart bas med neon per kategori
(lila = årtiondet, gul = artisten, rosa = exakt årtal, blå = årtal ±3 år,
grön = låttiteln). Typsnitt: Monoton (logga), Righteous (rubriker),
Space Grotesk (brödtext).
