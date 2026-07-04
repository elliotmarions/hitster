// Liten palett för att ge varje spelare en egen neonprick (bara kosmetiskt).
const DOTS = ['#22e6e6', '#ff2e9a', '#b6ff3c', '#ffc93c', '#b14dff', '#ff4d9d']

export default function PlayerList({ players, currentUserId }) {
  if (!players.length) {
    return (
      <p className="text-muted text-sm py-6 text-center">
        Inga spelare än – dela rumskoden så någon kan hoppa in.
      </p>
    )
  }

  return (
    <ul className="space-y-2">
      {players.map((p, i) => {
        const isMe = p.user_id === currentUserId
        const dot = DOTS[i % DOTS.length]
        return (
          <li
            key={p.id}
            className="panel-inset flex items-center gap-3 px-3.5 py-2.5"
          >
            <span
              className="h-2.5 w-2.5 shrink-0 rounded-full anim-pulse"
              style={{ background: dot, color: dot }}
            />
            <span className="font-display truncate text-cream">{p.display_name}</span>

            <span className="ml-auto flex items-center gap-1.5">
              {p.is_host && (
                <span className="chip" style={{ '--neon': '#ffc93c' }}>
                  ★ Värd
                </span>
              )}
              {isMe && (
                <span className="chip" style={{ '--neon': '#22e6e6' }}>
                  Du
                </span>
              )}
            </span>
          </li>
        )
      })}
    </ul>
  )
}
