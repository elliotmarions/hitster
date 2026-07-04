import NeonButton from './ui/NeonButton.jsx'

// Visas för alla när någon fyllt en hel rad/kolumn.
export default function WinBanner({ winnerName, isMe, isHost, onPlayAgain, onBackToLobby, busy }) {
  return (
    <div
      className="panel relative overflow-hidden p-6 text-center"
      style={{ borderColor: '#ffc93c', boxShadow: '0 0 44px -10px #ffc93c' }}
    >
      <p className="label" style={{ color: '#ffc93c' }}>
        Vinst
      </p>
      <h2
        className="wordmark mt-2 text-4xl sm:text-5xl"
        style={{ textShadow: '0 0 4px #fff, 0 0 16px #ffc93c, 0 0 42px #ff2e9a' }}
      >
        Hitster!
      </h2>
      <p className="mt-3 font-display text-xl text-cream">
        {isMe ? 'Du vann! 🪩' : `${winnerName || 'Någon'} fyllde en rad!`}
      </p>

      <div className="mt-5 flex flex-wrap justify-center gap-3">
        {isHost ? (
          <>
            <NeonButton onClick={onPlayAgain} disabled={busy}>
              Spela igen
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
  )
}
