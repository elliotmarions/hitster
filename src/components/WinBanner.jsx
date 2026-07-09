import NeonButton from './ui/NeonButton.jsx'
import Confetti from './Confetti.jsx'

// Visas när en eller flera enheter fyllt en hel rad/kolumn/diagonal.
// winnerNames: array med vinnarnamn (>1 = oavgjort).
export default function WinBanner({
  winnerNames = [],
  isMe,
  teamMode = false,
  isHost,
  onPlayAgain,
  onBackToLobby,
  busy,
}) {
  const tie = winnerNames.length > 1
  const listNames = (names) =>
    names.length <= 1
      ? names[0] || ''
      : names.slice(0, -1).join(', ') + ' och ' + names[names.length - 1]

  const heading = tie ? 'Oavgjort!' : 'Låtsnurran!'
  const message = tie
    ? isMe
      ? `Oavgjort mellan ${listNames(winnerNames)} – ni är med!`
      : `Oavgjort mellan ${listNames(winnerNames)}!`
    : isMe
      ? teamMode
        ? `Ert lag ${winnerNames[0] || ''} vann! 🪩`.replace('  ', ' ')
        : 'Du vann! 🪩'
      : `${winnerNames[0] || (teamMode ? 'Ett lag' : 'Någon')} vann!`

  return (
    <div
      className="panel relative overflow-hidden p-6 text-center"
      style={{ borderColor: '#ffc93c', boxShadow: '0 0 44px -10px #ffc93c' }}
    >
      <Confetti />
      <div className="relative z-10">
        <p className="label" style={{ color: '#ffc93c' }}>
          {tie ? 'Oavgjort' : 'Vinst'}
        </p>
        <h2
          className="wordmark mt-2 text-4xl sm:text-5xl"
          style={{ textShadow: '0 0 4px #fff, 0 0 16px #ffc93c, 0 0 42px #ff2e9a' }}
        >
          {heading}
        </h2>
        <p className="mt-3 font-display text-xl text-cream">{message}</p>
        <p className="mt-1 text-sm text-muted">
          {tie
            ? `${winnerNames.length} ${teamMode ? 'lag' : 'spelare'} fyllde en rad samtidigt.`
            : teamMode
              ? 'Fyllde en hel rad eller kolumn.'
              : 'En hel rad eller kolumn ifylld.'}
        </p>

        <div className="mt-5 flex flex-wrap justify-center gap-3">
          {isHost ? (
            <>
              <NeonButton onClick={onPlayAgain} disabled={busy}>
                🔁 Spela igen
              </NeonButton>
              <NeonButton variant="outline" neon="#22e6e6" onClick={onBackToLobby} disabled={busy}>
                Till lobbyn
              </NeonButton>
            </>
          ) : (
            <p className="text-sm text-muted">Väntar på att värden startar om…</p>
          )}
        </div>
      </div>
    </div>
  )
}
