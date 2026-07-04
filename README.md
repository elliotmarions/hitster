# 🪩 Hitster Bingo Online

Spela sällskapsspelet **Hitster Bingo** tillsammans på distans – utan att musiken låter
uselt över video.

**Kärnidén:** ingen musik streamas mellan deltagarna. Varje spelare har sin egen Spotify
Premium, och appen startar **samma låt hos alla samtidigt** via en synkad nedräkning. Alla
hör ren musik från sin egen källa. Video/röst används bara för att umgås – aldrig för ljudet.
Dessutom digitaliseras **discokulan** och **bingobrickorna** så allt synkas i realtid.

---

## Byggstatus (faser)

| Fas | Innehåll | Status |
| --- | --- | --- |
| **1** | Fundament: Vite+React+Tailwind, Supabase, skapa/gå med i rum, lobby i realtid | ✅ **Klar** |
| **2** | Spelplan: digital discokula + bingobrickor med realtidskryss (utan ljud) | ✅ **Klar** |
| 3 | Spotify-inloggning + uppspelning av en låt lokalt | ⏳ Nästa |
| 4 | Synkad start (`PLAY_COUNTDOWN`) + 25 s-timer | ⏳ |
| 5 | Video (WebRTC-mesh), helt avstängbar | ⏳ |

> Denna README uppdateras allteftersom faserna byggs.

---

## Teknik

- **Frontend:** React + Vite
- **Styling:** Tailwind CSS (v4)
- **Backend / realtid / auth:** Supabase (Postgres + Realtime + Auth)
- **Hosting:** Vercel
- **Musik (Fas 3+):** Spotify Web Playback SDK + Web API (Authorization Code with PKCE)
- **Video (Fas 5):** WebRTC peer-to-peer mesh, signalering via Supabase Realtime
- **Språk i UI:t:** svenska

---

## Kom igång lokalt

### 1. Installera beroenden

```bash
npm install
```

### 2. Sätt upp Supabase

1. Skapa ett gratis projekt på [supabase.com](https://supabase.com).
2. Öppna **SQL Editor → New query**, klistra in innehållet i
   [`supabase/migrations/0001_phase1_rooms_players.sql`](supabase/migrations/0001_phase1_rooms_players.sql)
   och tryck **Run**. (Alternativt med Supabase CLI: `supabase db push`.)
3. **Aktivera anonyma inloggningar** (krävs – appen loggar in gäster automatiskt):
   **Authentication → Sign In / Providers → Anonymous sign-ins → På**.
4. *(Valfritt, för kontoinloggning/statistik)* Under **Authentication → URL Configuration**
   lägg till `http://127.0.0.1:5173` (och senare din Vercel-URL) som **Site URL** och
   **Redirect URL**. E-post­inloggning (magisk länk) fungerar direkt på ett hostat projekt.
5. Hämta **Project URL** och **anon/public key** under **Project Settings → API**.

### 3. Miljövariabler

Kopiera mallen och fyll i Supabase-värdena:

```bash
cp .env.example .env.local
```

```dotenv
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOi...
# Spotify behövs först i Fas 3 – kan lämnas tomt nu.
```

### 4. Starta

```bash
npm run dev
```

Öppna **http://127.0.0.1:5173** (eller `localhost:5173`).

> Saknas Supabase-nycklarna visar appen en tydlig setup-ruta i stället för att krascha.

### 5. Testa realtiden 🎉

1. Öppna appen i **två fönster** (t.ex. ett vanligt + ett inkognito, eller två datorer).
2. Skapa ett rum i det ena → du får en **rumskod**.
3. Gå med med samma kod i det andra fönstret.
4. Spelarlistan i lobbyn ska uppdateras **direkt** i båda fönstren. Lämnar någon rummet
   försvinner de live.

---

## Spotify (förbereds i Fas 3)

Du behöver inte göra detta för Fas 1, men för framtiden:

1. Registrera en app på [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard).
2. Lägg in **exakt** denna som *Redirect URI* (Spotify kräver `127.0.0.1`, **inte** `localhost`):
   `http://127.0.0.1:5173/callback`. I produktion: `https://<din-vercel-domän>/callback`.
3. Kopiera **Client ID** till `VITE_SPOTIFY_CLIENT_ID` i `.env.local`.
4. Scopes som kommer användas: `streaming`, `user-read-email`, `user-read-private`,
   `user-modify-playback-state`, `user-read-playback-state`.

> ⚠️ Web Playback SDK kräver **Spotify Premium** och en **desktop-webbläsare**. På mobil
> går det att se spelplan/brickor/video, men musiken måste startas i den egna Spotify-appen.

---

## Deploy till Vercel

1. Pusha repot till GitHub och importera det i Vercel (framework upptäcks som **Vite**).
2. Lägg in miljövariablerna (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, m.fl.) under
   **Settings → Environment Variables**.
3. `vercel.json` sköter SPA-routing så att djuplänkar (t.ex. `/rum/ABCD1`) fungerar.
4. Uppdatera **Supabase Site URL** och **Spotify Redirect URI** till din Vercel-domän.

---

## Projektstruktur

```
hitster-bingo-online/
├─ src/
│  ├─ lib/            supabase-klient, spelkonstanter (kategorier/färger), rum-RPC:er
│  ├─ context/        AuthContext – anonym gäst + valfri kontoinloggning
│  ├─ hooks/          useRoom – rum + spelare i realtid
│  ├─ components/     AppShell, DiscoBall, PlayerList, AccountBadge, ui/*
│  ├─ pages/          LandingPage (skapa/gå med), LobbyPage (lobby)
│  ├─ index.css       designsystem: neonpalett, typsnitt, animationer
│  └─ main.jsx        router + providers
├─ supabase/migrations/   SQL-migrationer (en per fas)
├─ .env.example
└─ vercel.json
```

---

## Design & viktiga principer

- **Estetik:** 80-tals synthwave/nattklubb – midnattssvart bas, neon per kategori
  (guld = årtiondet, magenta = artisten, cyan = exakt årtal, lime = årtal ±3 år, lila = låttiteln).
  Typsnitt: Monoton (logga), Righteous (rubriker), Space Grotesk (brödtext).
- **Ingen ljudöverföring via WebRTC – någonsin.** Musik spelas alltid lokalt via varje
  spelares egen Spotify. WebRTC (Fas 5) bär bara video/röst.
- **Inloggning:** man spelar direkt som **gäst**. Vill man spara statistik kan man logga in
  med e-post – kontot länkas till samma id så statistiken följer med från gäst → konto.
- **Säkerhet:** Row Level Security är på. Bara ett rums medlemmar kan läsa/skriva dess data;
  att skapa/gå med sker via `SECURITY DEFINER`-funktioner i databasen.
