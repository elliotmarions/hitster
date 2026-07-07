import NeonButton from './ui/NeonButton.jsx'
import Confetti from './Confetti.jsx'

// Visas för alla när ett lag/en spelare fyllt en hel rad/kolumn.
export default function WinBanner({
  winnerName,
  isMe,
  teamMode = false,
  isHost,
  onPlayAgain,
  onBackToLobby,
  busy,
}) {
  // Tydligt vem som vann – lag-anpassat.
  const message = isMe
    ? teamMode
      ? `Ert lag ${winnerName || ''} vann! 🪩`.replace('  ', ' ')
      : 'Du vann! 🪩'
    : `${winnerName || (teamMode ? 'Ett lag' : 'Någon')} vann!`
  return (
    <div
      className="panel relative overflow-hidden p-6 text-center"
      style={{ borderColor: '#ffc93c', boxShadow: '0 0 44px -10px #ffc93c' }}
    >
      <Confetti />
      <div className="relative z-10">
        <p className="label" style={{ color: '#ffc93c' }}>
          Vinst
        </p>
        <h2
          className="wordmark mt-2 text-4xl sm:text-5xl"
          style={{ textShadow: '0 0 4px #fff, 0 0 16px #ffc93c, 0 0 42px #ff2e9a' }}
        >
          Låtsnurran!
        </h2>
        <p className="mt-3 font-display text-xl text-cream">{message}</p>
        <p className="mt-1 text-sm text-muted">
          {teamMode ? 'Fyllde en hel rad eller kolumn.' : 'En hel rad eller kolumn ifylld.'}
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
