import { useState } from 'react'
import { CATEGORIES, ERASE_CATEGORIES } from '../lib/constants'
import NeonButton from './ui/NeonButton.jsx'
import TrackReveal from './TrackReveal.jsx'

/**
 * Svarsfas: så fort låten börjat spela skriver varje enhet (lag i lagläge,
 * annars varje spelare) sitt svar och LÅSER IN det – man behöver inte vänta ut
 * klippet. När alla låst (round.answers_revealed) tystnar låten och allas svar
 * + facit visas samtidigt.
 *
 * Props:
 *   round    – senaste rundan (answers_revealed, locked_count)
 *   facitMeta – facit {name, artist, year} (från round_tracks, null före reveal)
 *   answers  – round_answers för rummet (RLS: bara mitt eget tills avslöjat)
 *   players  – rummets spelare
 *   teams    – rummets lag (lagläge)
 *   teamMode – spelar vi i lag?
 *   myUnitId – mitt lag-id (lagläge) eller mitt player-id (solo)
 *   me       – min player-rad
 *   isHost   – visar "Visa svar nu"-knappen
 *   busy     – knappar disablade under pågående RPC
 *   clipPlaying – låten låter fortfarande (styr bara hjälptexterna)
 *   eraseRuleOn – suddregeln påslagen i rummet (styr bonusrutan)
 *   onLock   – (text, bonusYear) => void
 *   onReveal – () => void
 */
export default function AnswerPanel({
  round,
  facitMeta,
  answers,
  players,
  teams = [],
  teamMode = false,
  myUnitId,
  isHost,
  busy,
  clipPlaying = false,
  // Lagläge: bara lagkaptenen får låsa in. Övriga ser vem som svarar och
  // hänvisas till lagchatten. Solo är canAnswer alltid true.
  canAnswer = true,
  answererName = null,
  eraseRuleOn = false,
  onLock,
  onReveal,
  onOverride,
}) {
  const [text, setText] = useState('')
  const [bonus, setBonus] = useState('')
  if (!round) return null

  const unitWord = teamMode ? 'lag' : 'spelare'
  const roundAnswers = answers.filter((a) => a.round_id === round.id)
  const unitIdOf = (a) => (teamMode ? a.team_id : a.player_id)
  const nameOf = (a) =>
    teamMode
      ? teams.find((t) => t.id === a.team_id)?.name || 'Lag'
      : players.find((p) => p.id === a.player_id)?.display_name || 'Spelare'

  const mine = roundAnswers.find((a) => unitIdOf(a) === myUnitId)
  const revealed = Boolean(round.answers_revealed)
  const total = teamMode ? teams.length : players.length
  const locked = round.locked_count ?? 0
  const iLocked = Boolean(mine?.locked)
  const cat = CATEGORIES[round.category]

  // Årtals-kategorier kräver ett HELT fyrsiffrigt årtal (1900–2099) – "67"
  // godtas inte. Speglar serverns facit-regex (?:19|20)\d{2}. Blockerar
  // inlåsning tills formatet stämmer.
  const isYearCat =
    round.category === 'exact_year' ||
    round.category === 'approx_year' ||
    round.category === 'approx_year_1'
  const yearFormatBad = isYearCat && text.trim() !== '' && !/(?:19|20)\d{2}/.test(text)

  // "Före eller efter" – ett binärt val mot ett känt pivot-år (rounds.pivot_year).
  const isBeforeAfter = round.category === 'before_after'
  const pivot = round.pivot_year

  // Bonusruta (0064): är suddregeln på och rundan INTE handlar om årtal får man
  // gissa året vid sidan av. Exakt träff ger ett sudd, oberoende av huvudsvaret.
  // På årtalskategorierna vore rutan en dubblett av svaret – då visas den inte.
  const showBonus = eraseRuleOn && !ERASE_CATEGORIES.includes(round.category)
  const bonusFormatBad = bonus.trim() !== '' && !/^(?:19|20)\d{2}$/.test(bonus.trim())
  // Snyggare etikett för ett före/efter-svar vid avslöjandet.
  const beforeAfterLabel = (val) =>
    val === 'före' ? `Före ${pivot}` : val === 'efter' ? `${pivot} eller senare` : val

  // --- Avslöjat: visa allas svar + facit ---
  if (revealed) {
    const shown = [...roundAnswers].sort((a, b) => nameOf(a).localeCompare(nameOf(b), 'sv'))
    return (
      <section className="panel p-5 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl text-cream">Allas svar</h2>
          <span className="chip" style={{ '--neon': cat?.hex || '#22e6e6' }}>
            {cat?.short || 'Svar'}
          </span>
        </div>

        <div className="grid gap-2 sm:grid-cols-2">
          {shown.map((a) => {
            const isMe = unitIdOf(a) === myUnitId
            // Domen räknas server-side vid avslöjandet (auto_correct); värden kan
            // överstyra (override_correct). Effektiv dom = override ?? auto.
            const overridden = a.override_correct !== null && a.override_correct !== undefined
            const correct = overridden ? a.override_correct : a.auto_correct === true
            const good = '#3ee87b'
            const bad = '#ff4d9d'
            return (
              <div
                key={a.id}
                className="panel-inset p-3"
                style={{ borderColor: correct ? `${good}66` : `${bad}55` }}
              >
                <div className="flex items-center justify-between gap-2">
                  <p className="label" style={{ color: isMe ? '#22e6e6' : undefined }}>
                    {nameOf(a)}
                    {isMe ? (teamMode ? ' (ni)' : ' (du)') : ''}
                  </p>
                  <span className="chip shrink-0" style={{ '--neon': correct ? good : bad }}>
                    {correct ? '✓ Rätt' : '✗ Fel'}
                  </span>
                </div>
                <p className="mt-0.5 font-display text-lg text-cream break-words">
                  {a.answer?.trim() ? (
                    isBeforeAfter ? beforeAfterLabel(a.answer) : a.answer
                  ) : (
                    <span className="text-muted">— inget svar —</span>
                  )}
                </p>

                {/* Bonusgissningen (0064). Visas bara när rutan var i spel och
                    någon faktiskt skrev ett år – tomma rutor är brus. */}
                {a.bonus_year?.trim() && (
                  <p className="mt-1 text-xs">
                    <span className="text-muted">Bonusår: </span>
                    <span style={{ color: a.bonus_correct ? good : bad }}>
                      {a.bonus_year.trim()}
                    </span>
                    {a.bonus_correct && (
                      <span className="text-cream"> · får sudda ett kryss</span>
                    )}
                  </p>
                )}

                {isHost && (
                  <div className="mt-2 flex items-center gap-1.5 text-xs">
                    <span className="text-muted">Rätta:</span>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => onOverride?.(a.id, true)}
                      className="rounded px-1.5 py-0.5"
                      style={{
                        border: `1px solid ${good}`,
                        color: correct ? '#140c22' : good,
                        background: correct ? good : 'transparent',
                      }}
                    >
                      ✓
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => onOverride?.(a.id, false)}
                      className="rounded px-1.5 py-0.5"
                      style={{
                        border: `1px solid ${bad}`,
                        color: !correct ? '#140c22' : bad,
                        background: !correct ? bad : 'transparent',
                      }}
                    >
                      ✗
                    </button>
                    {overridden && (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => onOverride?.(a.id, null)}
                        className="text-muted underline"
                      >
                        auto
                      </button>
                    )}
                  </div>
                )}
                {overridden && <p className="mt-1 text-[10px] text-muted">rättat av värden</p>}
              </div>
            )
          })}
          {shown.length === 0 && <p className="text-sm text-muted">Inga svar registrerades.</p>}
        </div>
        <div className="flex justify-center pt-1">
          {/* Facit hämtas från round_tracks (RLS öppnar den först vid reveal). */}
          <TrackReveal meta={facitMeta} category={round.category} />
        </div>
      </section>
    )
  }

  // --- Inte avslöjat än: en ruta per enhet, din egen är inmatningen ---
  // Vilka enheter som låst kommer från round.locked_units (server, utan att
  // läcka svarstexten). Din egen status speglas även av mine.locked så den
  // känns direkt vid inlåsning.
  const lockedUnits = new Set(round.locked_units || [])
  const units = teamMode
    ? teams.map((t) => ({ id: t.id, name: t.name || 'Lag' }))
    : players.map((p) => ({ id: p.id, name: p.display_name || 'Spelare' }))
  // Låst-läget är MEDVETET blått, inte grönt. Grönt betyder "rätt svar" när
  // facit väl visas, och samma färg i båda lägena fick folk att tro att de
  // redan svarat rätt i det ögonblick de låste in. Blått säger bara "klar –
  // vi väntar på de andra"; först vid avslöjandet blir det grönt eller rosa.
  const lockedHue = '#33a6ff'

  // Bonusrutan ser likadan ut i båda inmatningslägena (fritext och före/efter),
  // så den byggs en gång. Rosa = suddregelns färg, samma som Exakt årtal.
  const bonusField = showBonus ? (
    <div className="panel-inset p-2.5" style={{ borderColor: 'rgba(255,77,157,0.35)' }}>
      <p className="label text-[11px]" style={{ color: '#ff4d9d' }}>
        Bonus: gissa exakt årtal
      </p>
      <input
        className="field mt-1.5 py-1.5 text-center font-display"
        placeholder="t.ex. 1987"
        value={bonus}
        onChange={(e) => setBonus(e.target.value)}
        maxLength={4}
        inputMode="numeric"
        autoCorrect="off"
        autoCapitalize="off"
        autoComplete="off"
        spellCheck={false}
      />
      {bonusFormatBad ? (
        <p className="mt-1 text-[11px] text-magenta">⚠ Skriv hela årtalet, t.ex. 1987.</p>
      ) : (
        <p className="mt-1 text-[11px] text-muted">
          Frivilligt. Exakt rätt år låter dig sudda ett kryss hos någon annan – även om du
          missar rundans egen fråga.
        </p>
      )}
    </div>
  ) : null

  return (
    <section className="panel p-5 space-y-4">
      {/* Kategorin upprepas här, inte bara i banderollen med hjulet: på mobil
          har man scrollat förbi den när man skriver sitt svar, och då är
          "vad var det vi gissade på?" den enda fråga som spelar roll. */}
      <div>
        <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
          <div className="flex items-center gap-2">
            <h2 className="font-display text-xl text-cream">Svar</h2>
            <span className="chip shrink-0" style={{ '--neon': cat?.hex || '#22e6e6' }}>
              {cat?.short || 'Svar'}
            </span>
          </div>
          <span className="text-sm text-muted">
            {locked} av {total} {unitWord} klara
          </span>
        </div>
        {cat?.desc && !isBeforeAfter && (
          <p className="mt-1 text-xs text-muted">{cat.desc}</p>
        )}
      </div>

      <div
        className="grid gap-3"
        style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))' }}
      >
        {units.map((u) => {
          const isMe = u.id === myUnitId
          const unitLocked = lockedUnits.has(u.id) || (isMe && iLocked)
          return (
            <div
              key={u.id}
              className="panel-inset flex flex-col p-3"
              style={{
                borderColor: unitLocked
                  ? `${lockedHue}66`
                  : isMe
                    ? 'rgba(34,230,230,0.4)'
                    : undefined,
                boxShadow: unitLocked ? `0 0 18px -8px ${lockedHue}` : undefined,
              }}
            >
              <div className="flex items-center justify-between gap-2">
                <p className="label truncate" style={{ color: isMe ? '#22e6e6' : undefined }}>
                  {u.name}
                  {isMe ? (teamMode ? ' (ni)' : ' (du)') : ''}
                </p>
                {unitLocked ? (
                  <span className="chip shrink-0" style={{ '--neon': lockedHue }}>
                    Låst
                  </span>
                ) : (
                  <span className="shrink-0 text-xs text-muted">skriver…</span>
                )}
              </div>

              {/* Egen ruta = inmatning; andras = bara status (svaret döljs). */}
              {isMe ? (
                unitLocked ? (
                  <div className="mt-2">
                    <p className="font-display text-lg text-cream break-words">
                      {mine?.answer?.trim() ? (
                        isBeforeAfter ? beforeAfterLabel(mine.answer) : mine.answer
                      ) : mine ? (
                        <span className="text-muted">— inget svar —</span>
                      ) : (
                        /* Låst enligt rundan, men svarsraden har inte nått hit
                           än. Att skriva "inget svar" vore en gissning – och
                           fel gissning: raden finns, den är bara inte framme.
                           Uppstår i lagläge det ögonblick rundans locked_units
                           hinner före svaret genom realtiden. */
                        <span className="text-muted">Svaret är inlåst</span>
                      )}
                    </p>
                    {mine?.bonus_year?.trim() && (
                      <p className="mt-1 text-xs" style={{ color: '#ff4d9d' }}>
                        Bonusår: {mine.bonus_year.trim()}
                      </p>
                    )}
                    <p className="mt-1 text-xs text-muted">
                      {clipPlaying
                        ? `Låten spelar vidare tills alla ${unitWord} låst in…`
                        : `Väntar på att alla ${unitWord} låser in…`}
                    </p>
                  </div>
                ) : !canAnswer ? (
                  /* Lagkamrat utan kaptensbindeln: ingen skrivruta, så två i
                     samma lag inte kapplöper om att låsa olika svar. */
                  <div className="mt-2 flex flex-1 flex-col items-center justify-center gap-1 py-3 text-center">
                    <p className="font-display text-cream">
                      {answererName ? `${answererName} svarar` : 'Lagkaptenen svarar'}
                    </p>
                    <p className="text-xs text-muted">Resonera i lagchatten – kaptenen låser in.</p>
                  </div>
                ) : isBeforeAfter ? (
                  <div className="mt-2 space-y-2">
                    <p className="text-sm text-cream">
                      Släpptes låten <b>före {pivot}</b> eller <b>{pivot} och senare</b>?
                    </p>
                    <div className="grid grid-cols-2 gap-2">
                      {[
                        ['före', `Före ${pivot}`],
                        ['efter', `${pivot} eller senare`],
                      ].map(([val, lbl]) => (
                        <button
                          key={val}
                          type="button"
                          onClick={() => setText(val)}
                          aria-pressed={text === val}
                          className="panel-inset cursor-pointer p-3 text-center font-display text-cream transition"
                          style={{
                            borderColor: text === val ? '#b14dff' : undefined,
                            boxShadow: text === val ? '0 0 18px -8px #b14dff' : undefined,
                          }}
                        >
                          {lbl}
                        </button>
                      ))}
                    </div>
                    {bonusField}
                    <NeonButton
                      onClick={() => onLock(text, bonus.trim())}
                      disabled={
                        busy || (text !== 'före' && text !== 'efter') || bonusFormatBad
                      }
                      className="w-full"
                    >
                      Lås in
                    </NeonButton>
                  </div>
                ) : (
                  <div className="mt-2 space-y-2">
                    {/* Autocorrect MÅSTE vara av: mobiltangentbord skriver
                        annars om låttitlar och artistnamn (ofta utan att man
                        märker det) och man förlorar rundan på en rättstavning
                        man aldrig bad om. */}
                    <textarea
                      className="field min-h-[64px] resize-none"
                      placeholder={
                        isYearCat ? 'Skriv hela årtalet, t.ex. 1967' : cat?.desc || 'Skriv ert svar…'
                      }
                      value={text}
                      onChange={(e) => setText(e.target.value)}
                      maxLength={200}
                      autoFocus
                      autoCorrect="off"
                      autoCapitalize="off"
                      autoComplete="off"
                      spellCheck={false}
                      inputMode={isYearCat ? 'numeric' : 'text'}
                    />
                    {yearFormatBad && (
                      <p className="text-xs text-magenta">
                        ⚠ Skriv hela årtalet, t.ex. <b>1967</b> – inte ”67”.
                      </p>
                    )}
                    {bonusField}
                    <NeonButton
                      onClick={() => onLock(text.trim(), bonus.trim())}
                      disabled={busy || !text.trim() || yearFormatBad || bonusFormatBad}
                      className="w-full"
                    >
                      Lås in
                    </NeonButton>
                  </div>
                )
              ) : (
                <div className="mt-2 flex flex-1 items-center justify-center py-3 text-center">
                  {unitLocked ? (
                    <p className="font-display text-lg" style={{ color: lockedHue }}>
                      Klar!
                    </p>
                  ) : (
                    <p className="text-sm text-muted">Väntar…</p>
                  )}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {isHost && (
        <div className="border-t border-white/10 pt-3 text-center">
          <NeonButton variant="ghost" onClick={onReveal} disabled={busy}>
            Visa svar nu
          </NeonButton>
          <p className="mt-1 text-xs text-muted">
            Värden kan avslöja även om något {unitWord} inte svarat.
          </p>
        </div>
      )}
    </section>
  )
}
