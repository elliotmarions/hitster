import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase.js'
import {
  closeRoomIfHostAbsent,
  leaveRoom,
  removeAbsentPlayer,
  touchLastSeen,
} from '../../lib/rooms.js'
import { startGame, trackPoolSelectionCount } from '../../lib/game.js'
import PlayerList from '../PlayerList.jsx'
import TeamSetup from '../TeamSetup.jsx'
import NeonButton from '../ui/NeonButton.jsx'
import ConfirmDialog from '../ui/ConfirmDialog.jsx'
import CopyButton from '../ui/CopyButton.jsx'
import SwedishFlag from '../ui/SwedishFlag.jsx'
import TeamChat from '../TeamChat.jsx'
import {
  POOL_CATEGORIES,
  TOMT_VAL,
  isSelected,
  selectionEmpty,
  selectionFrom,
  selectionLabel,
  toggleSelection,
} from '../../lib/constants.js'

// Hur länge en spelare får vara borta ur presence innan raden städas bort.
// Marginalen finns för omladdningar och korta tapp – websocket:en försvinner
// direkt när fliken stängs, men den försvinner lika direkt vid en F5.
const FRANVARO_INNAN_RENSNING_MS = 12_000
// Hjärtslaget måste vara rundligt tätare än serverns 45-sekundersgräns i
// close_room_if_host_absent, annars kan en värd som sitter kvar råka se ut
// som borta bara för att ett anrop missade.
const HJARTSLAG_MS = 15_000

export default function LobbyView({
  room,
  players,
  teams,
  me,
  isHost,
  currentUserId,
  presentUserIds,
}) {
  const navigate = useNavigate()
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [confirmLeave, setConfirmLeave] = useState(false)
  const [leaving, setLeaving] = useState(false)
  // "Nej, var för sig" tystar lagfrågan resten av lobbybesöket. Medvetet bara
  // i minnet: en fjärde spelare som dyker upp ska inte väcka frågan igen, men
  // laddar värden om sidan är det rimligt att den ställs på nytt.
  const [lagFraganAvfardad, setLagFraganAvfardad] = useState(false)
  // Antal låtar i exakt den kombination som är vald (språk + år + genre).
  const [selCount, setSelCount] = useState(null)
  // Optimistiskt lager: valet ska synas direkt vid klick, utan att vänta på
  // server-svar + realtidsstuds. Rensas när riktiga room-proppen hunnit ikapp.
  const [optimistic, setOptimistic] = useState(null)
  const roomLink = `${window.location.origin}/rum/${room.code}`

  // När servern speglat tillbaka vårt val (via realtid) matchar room-proppen
  // det optimistiska värdet – då släpper vi övertäckningen.
  useEffect(() => {
    if (!optimistic) return
    const matched = Object.entries(optimistic).every(([k, v]) => room[k] === v)
    if (matched) setOptimistic(null)
  }, [room, optimistic])

  // Det klienten faktiskt renderar: room med ev. pågående val ovanpå.
  const view = optimistic ? { ...room, ...optimistic } : room

  // Hur många låtar det VALDA urvalet ger. De breda räknarna räcker inte när
  // filtren staplas – skärningen mellan "svenska", "20–29 år" och "Pop" går
  // inte att räkna ut ur deras summor, den måste frågas fram.
  //
  // Nyckeln är serialiserad: `val` är ett nytt objekt varje rendering, så en
  // beroendelista på objektet självt hade kört effekten i all oändlighet.
  const val = selectionFrom(view)
  const valNyckel = JSON.stringify(val)
  useEffect(() => {
    let active = true
    setSelCount(null)
    trackPoolSelectionCount(JSON.parse(valNyckel))
      .then((n) => active && setSelCount(n))
      .catch(() => {})
    return () => {
      active = false
    }
  }, [valNyckel])

  // --- Frånvaro: stänger man fliken ska man försvinna ur lobbyn ----------
  //
  // Presence säger vem som är ansluten just NU, men inte hur länge någon
  // varit borta. Kartan håller tidpunkten då en spelare först saknades, så
  // att ett kort tapp inte förväxlas med ett utträde.
  const borttSedan = useRef(new Map())
  // Pågående/misslyckade rensningar per user_id, så att en spelare inte
  // anropas bort var tredje sekund medan raderingen speglas tillbaka. Ett
  // misslyckat anrop får försökas om, men bara ett par gånger: går det inte
  // är det något beständigt fel, och då är en evig loop mot servern fel svar.
  const rensade = useRef(new Map())
  const MAX_FORSOK = 3

  useEffect(() => {
    if (!room?.id) return
    const slag = () => touchLastSeen(room.id).catch(() => {})
    slag()
    const id = setInterval(slag, HJARTSLAG_MS)
    return () => clearInterval(id)
  }, [room?.id])

  useEffect(() => {
    // null betyder "presence har inte synkat än" – att läsa det som "ingen är
    // här" hade rensat bort hela rummet vid varje montering. Saknas jag själv
    // i listan har kanalen inte satt sig, och då är den inte att lita på.
    if (!presentUserIds || !currentUserId || !presentUserIds.has(currentUserId)) return

    const karta = borttSedan.current
    const nu = Date.now()
    for (const p of players) {
      if (presentUserIds.has(p.user_id)) {
        karta.delete(p.user_id)
        rensade.current.delete(p.user_id)
      } else if (!karta.has(p.user_id)) {
        karta.set(p.user_id, nu)
      }
    }
    for (const uid of [...karta.keys()]) {
      if (!players.some((p) => p.user_id === uid)) {
        karta.delete(uid)
        rensade.current.delete(uid)
      }
    }
  }, [presentUserIds, players, currentUserId])

  useEffect(() => {
    if (!room?.id || !presentUserIds || !currentUserId) return
    if (!presentUserIds.has(currentUserId)) return

    const langeBorta = (uid) => {
      const t = borttSedan.current.get(uid)
      return t !== undefined && Date.now() - t >= FRANVARO_INNAN_RENSNING_MS
    }

    const tick = () => {
      if (isHost) {
        // Värden städar bort de andra. Servern kontrollerar att anroparen är
        // värd och att rummet är i lobbyn; klienten bidrar bara med frånvaron.
        for (const p of players) {
          if (p.user_id === currentUserId) continue
          const st = rensade.current.get(p.user_id)
          if (st?.pagar || (st?.n ?? 0) >= MAX_FORSOK) continue
          if (!langeBorta(p.user_id)) continue
          const n = (st?.n ?? 0) + 1
          rensade.current.set(p.user_id, { n, pagar: true })
          // Lyckas anropet raderas raden, realtiden speglar det och effekten
          // ovan städar bort posten härifrån. Bara felvägen behöver hanteras.
          removeAbsentPlayer(room.id, p.id).catch(() =>
            rensade.current.set(p.user_id, { n, pagar: false }),
          )
        }
      } else if (room.host_user_id && langeBorta(room.host_user_id)) {
        // Värden kan inte städa efter sig själv, och ingen annan får radera
        // värdens rad. Servern avgör på värdens hjärtslagsstämpel om rummet
        // ska stängas – klienten ber bara om en kontroll.
        closeRoomIfHostAbsent(room.id).catch(() => {})
      }
    }

    const id = setInterval(tick, 3000)
    return () => clearInterval(id)
  }, [room?.id, room?.host_user_id, isHost, players, presentUserIds, currentUserId])

  async function handleStart() {
    setErr('')
    setBusy(true)
    try {
      await startGame(room.id)
      // rooms.status blir 'playing' → RoomPage byter till spelvyn automatiskt (via realtid)
    } catch (e) {
      setErr(e.message || 'Kunde inte starta spelet.')
      setBusy(false)
    }
  }

  async function handleLeave() {
    setLeaving(true)
    try {
      await leaveRoom(room.id)
    } catch {
      /* navigera bort ändå */
    }
    navigate('/')
  }

  async function toggleErase(e) {
    // Värdens direkta uppdatering tillåts av RLS (rooms_update_host). Realtid speglar till alla.
    await supabase.from('rooms').update({ erase_rule_enabled: e.target.checked }).eq('id', room.id)
  }

  async function setTeamMode(on) {
    // Lagen raderas INTE när lagläget stängs av. Ångrar sig värden och slår på
    // det igen står indelningen kvar; att tömma den vid varje av-slag vore ett
    // tyst dataras för ett klick som lika gärna var en felträff.
    await supabase.from('rooms').update({ team_mode: on }).eq('id', room.id)
  }

  // Skriv ett nytt urval till rummet. year_min/year_max sätts INTE här –
  // en trigger (0057) härleder dem ur year_bands, eftersom åldersläget
  // (hjulet och brickans kategorier) fortfarande läser dem.
  async function skrivVal(patch) {
    setOptimistic((o) => ({ ...o, ...patch }))
    // .select() är inte kosmetik: nekar RLS skrivningen får man INGET error,
    // bara noll rader tillbaka. Utan den här kontrollen skulle det optimistiska
    // lagret aldrig matcha rummet och värden se fel kategori markerad ända tills
    // sidan laddas om – exakt det som hände när year_min/year_max saknades i
    // kolumn-granten (0029).
    const { data, error } = await supabase.from('rooms').update(patch).eq('id', room.id).select()
    if (error || !data?.length) {
      setOptimistic(null) // backa till serverns sanning
      setErr('Kunde inte ändra urvalet – ladda om sidan och försök igen.')
    }
  }

  // Slå en chip av eller på. Union inom dimensionen, snitt mellan dimensioner.
  const onToggle = (cat) => skrivVal(toggleSelection(view, cat))
  const onClearAll = () => skrivVal(TOMT_VAL)

  const tomtVal = selectionEmpty(view)

  // En kategori-knapp – delas av de breda potterna, åldersspannen och genrerna.
  // Chipen visar INTE sin egen pottstorlek: tolv siffror som ändå inte går att
  // addera (dimensionerna snittas) blev bara brus. Den siffra som styr något,
  // urvalets storlek, står samlat under valen.
  function renderCategory(cat) {
    const active = isSelected(view, cat)
    return (
      <button
        key={cat.key}
        type="button"
        disabled={!isHost}
        onClick={() => onToggle(cat)}
        aria-pressed={active}
        className="panel-inset flex cursor-pointer flex-col gap-1 p-3.5 text-left transition disabled:cursor-default disabled:opacity-60"
        style={{
          borderColor: active ? cat.neon : undefined,
          boxShadow: active ? `0 0 22px -8px ${cat.neon}` : undefined,
        }}
      >
        <span className="inline-flex items-center gap-2 font-display text-cream">
          {cat.key === 'sv' && <SwedishFlag size={18} />}
          {cat.label}
        </span>
        {cat.hint && <span className="text-xs text-muted">{cat.hint}</span>}
      </button>
    )
  }

  return (
    <div className="space-y-6">
      <ConfirmDialog
        open={confirmLeave}
        busy={leaving}
        title={isHost ? 'Stäng rummet?' : 'Lämna rummet?'}
        message={
          isHost
            ? 'Du är värd – lämnar du stängs rummet för alla som väntar. Det går inte att ångra.'
            : 'Du tas bort ur rummet. Du kan gå med igen med rumskoden.'
        }
        confirmLabel={isHost ? 'Stäng för alla' : 'Lämna'}
        cancelLabel="Stanna kvar"
        onConfirm={handleLeave}
        onCancel={() => setConfirmLeave(false)}
      />

      {/* Lagfrågan mitt på skärmen i stället för nederst i inställnings-
          panelen: den ställs sällan, kräver ett svar och ska inte behöva
          letas upp. Rutan stängs av att room.team_mode kommer tillbaka via
          realtiden, inte av klicket – misslyckas skrivningen står frågan
          kvar i stället för att tyst försvinna utan verkan. */}
      <ConfirmDialog
        open={isHost && !room.team_mode && players.length >= 3 && !lagFraganAvfardad}
        title="Vill ni spela i lag?"
        message={`Ni är ${players.length} i rummet. I lagläge delar laget bricka och svarar tillsammans – en kapten per lag låser svaret.`}
        confirmLabel="Ja, dela in lag"
        cancelLabel="Nej, var för sig"
        neon="#22e6e6"
        onConfirm={() => setTeamMode(true)}
        onCancel={() => setLagFraganAvfardad(true)}
      />

      <div className="grid gap-6 lg:grid-cols-[1.15fr_0.85fr]">
      <section className="panel p-6 sm:p-8">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="label">Lobby</p>
            <h1 className="mt-1 font-display text-3xl text-cream">{room.name || 'Namnlöst rum'}</h1>
          </div>
          <span className="chip" style={{ '--neon': '#b6ff3c' }}>
            Väntar
          </span>
        </div>

        <div className="mt-6">
          <p className="label mb-2">Rumskod – dela med gänget</p>
          <div className="flex flex-wrap items-center gap-3">
            <div className="code-badge px-5 py-3 text-3xl">{room.code}</div>
            <CopyButton value={room.code} label="Kopiera kod" />
            <CopyButton value={roomLink} label="Kopiera länk" neon="#b14dff" />
          </div>
        </div>

        {/* Urval – fritt multival. Union inom varje rad, snitt mellan raderna:
            "Svenska + 20–29 år + 30–39 år + Pop" = svensk pop ur endera eran. */}
        <div className="mt-6">
          {isHost && !tomtVal && (
            <div className="mb-2 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={onClearAll}
                className="cursor-pointer text-xs text-muted underline hover:text-cream"
              >
                Rensa
              </button>
            </div>
          )}

          <p className="label mb-2 opacity-70">Språk</p>
          <div className="grid grid-cols-2 gap-3">
            {POOL_CATEGORIES.filter((c) => c.group === 'lang').map(renderCategory)}
          </div>

          <p className="label mb-2 mt-4 opacity-70">Ålder</p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {POOL_CATEGORIES.filter((c) => c.group === 'age').map(renderCategory)}
          </div>

          <p className="label mb-2 mt-4 opacity-70">Genre</p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {POOL_CATEGORIES.filter((c) => c.group === 'genre').map(renderCategory)}
          </div>

          {/* Sammanfattning + den enda siffra som betyder något: hur många
              låtar just den här kombinationen faktiskt ger. */}
          <div className="panel-inset mt-4 p-3.5">
            <p className="font-display text-cream">{selectionLabel(view)}</p>
            <p className="mt-0.5 text-xs text-muted">
              {selCount === null
                ? 'Räknar…'
                : `${selCount.toLocaleString('sv-SE')} låtar i urvalet`}
            </p>
          </div>
          {selCount !== null && selCount < 25 && (
            <p className="mt-2 text-xs" style={{ color: '#ff8a3c' }}>
              Tunn pott – {selCount} låtar. Samma låtar börjar återkomma, och med färre än
              25 kan brickan bli svår att fylla.
            </p>
          )}
        </div>

        {/* Regler – av/på */}
        <div className="mt-6">
          <p className="label mb-2">Regler</p>

          {/* Suddregel */}
          <label className="panel-inset flex items-center justify-between gap-4 p-3.5">
            <span>
              <span className="font-display text-cream">Suddregel</span>
              <span className="mt-0.5 block text-xs text-muted">
                På "Exakt årtal": rätt gissning låter dig sudda ett kryss hos en medspelare.
              </span>
            </span>
            <input
              type="checkbox"
              className="h-5 w-5 accent-magenta disabled:opacity-50"
              checked={room.erase_rule_enabled}
              onChange={toggleErase}
              disabled={!isHost}
            />
          </label>
        </div>

        {/* Lagläget frågas fram i stället för att ligga som en kryssruta bland
            reglerna. Med två spelare är lag meningslöst – ett lag per person –
            så frågan dyker upp först när en tredje spelare kommit in. Bara
            värden ser den: det är värden som kan svara, och en fråga man inte
            kan besvara är bara brus för de andra. */}
        {isHost && room.team_mode && (
          <div className="panel-inset mt-6 flex flex-wrap items-center justify-between gap-3 p-3.5">
            <span>
              <span className="font-display text-cream">Ni spelar i lag</span>
              <span className="mt-0.5 block text-xs text-muted">
                Dela in lagen under Spelare. Laget delar bricka, och kaptenen
                låser svaret.
              </span>
            </span>
            <button
              type="button"
              onClick={() => setTeamMode(false)}
              className="cursor-pointer text-xs text-muted underline hover:text-cream"
            >
              Spela var för sig
            </button>
          </div>
        )}

        {err && <p className="mt-4 text-sm text-magenta">{err}</p>}

        <div className="mt-6 flex flex-wrap items-center gap-3">
          {isHost ? (
            <NeonButton onClick={handleStart} disabled={busy}>
              {busy ? 'Startar…' : 'Starta spel'}
            </NeonButton>
          ) : (
            <span className="text-sm text-muted">Väntar på att värden startar spelet…</span>
          )}
          <NeonButton variant="ghost" onClick={() => setConfirmLeave(true)}>
            Lämna rummet
          </NeonButton>
        </div>
      </section>

      <section className="panel p-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">Spelare</h2>
          <span className="chip" style={{ '--neon': '#22e6e6' }}>
            {players.length} i rummet
          </span>
        </div>
        <div className="mt-4">
          <PlayerList players={players} currentUserId={currentUserId} />
        </div>

        {/* Lagindelningen hör hemma här, inte längst ner på sidan: det är
            samma personer man delar in som står i listan ovanför, och att
            behöva scrolla förbi hela inställningspanelen mellan namnen och
            lagen gjorde en enkel sak onödigt omständlig. */}
        {room.team_mode && (
          <div className="mt-6 border-t border-white/10 pt-5">
            <TeamSetup room={room} players={players} teams={teams} isHost={isHost} />
          </div>
        )}
      </section>
      </div>

      {/* Lagchatten finns redan i lobbyn så laget kan snacka ihop sig innan start. */}
      <TeamChat room={room} me={me} teams={teams} />
    </div>
  )
}
