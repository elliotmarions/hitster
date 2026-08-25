// Mockade hooks för mobil-harnessen. Ingår aldrig i produktionsbygget.
import { useCallback, useState } from 'react'
import { categoryOrderFor } from '../src/lib/constants.js'

const params = () => new URLSearchParams(window.location.search)

export const scenario = () => params().get('v') || 'lobby'

const ROOM = {
  id: 'r1',
  code: 'DISCO7',
  name: 'Fredagsmyset hos Elliot & Sara',
  status: 'playing',
  host_user_id: 'u-me',
  erase_rule_enabled: true,
  team_mode: false,
  swedish_mode: true,
  year_bands: [
    { min: 1965, max: 1974 },
    { min: 1985, max: 1994 },
    { min: 2005, max: null },
  ],
  genres: ['pop', 'rock', 'hiphop', 'edm', 'dansband'],
  categories: null,
  year_min: 1965,
  year_max: null,
  winner_round_id: null,
  ended_reason: null,
}

function grid(room, filled = 6) {
  const order = categoryOrderFor(room)
  const celler = []
  for (let i = 0; i < 25; i++) {
    celler.push({ category: order[i % 5], filled: i < filled, round: null })
  }
  return celler
}

export function useGame() {
  const v = scenario()
  const revealed = v === 'spel-facit'
  const round = {
    id: 'rd1',
    room_id: 'r1',
    round_number: 4,
    category: params().get('kat') || 'artist',
    current_track_id: 't1',
    timer_start_at: new Date(Date.now() - 6000).toISOString(),
    answers_revealed: revealed,
    locked_count: revealed ? 4 : 2,
    pivot_year: 1994,
    state: 'ready',
  }
  const cards = [
    { id: 'c1', room_id: 'r1', player_id: 'p1', team_id: null, grid: grid(ROOM, 7), has_won: false },
    { id: 'c2', room_id: 'r1', player_id: 'p2', team_id: null, grid: grid(ROOM, 4), has_won: false },
    { id: 'c3', room_id: 'r1', player_id: 'p3', team_id: null, grid: grid(ROOM, 9), has_won: false },
    { id: 'c4', room_id: 'r1', player_id: 'p4', team_id: null, grid: grid(ROOM, 2), has_won: false },
    { id: 'c5', room_id: 'r1', player_id: 'p5', team_id: null, grid: grid(ROOM, 5), has_won: false },
  ]
  const answers = revealed
    ? [
        { id: 'a1', round_id: 'rd1', player_id: 'p1', answer: 'Bruce Springsteen', locked: true, auto_correct: true, override_correct: null },
        { id: 'a2', round_id: 'rd1', player_id: 'p2', answer: 'Creedence Clearwater Revival', locked: true, auto_correct: false, override_correct: null },
        { id: 'a3', round_id: 'rd1', player_id: 'p3', answer: '', locked: true, auto_correct: false, override_correct: null },
        { id: 'a4', round_id: 'rd1', player_id: 'p4', answer: 'Simon & Garfunkel', locked: true, auto_correct: false, override_correct: true },
      ]
    : [{ id: 'a1', round_id: 'rd1', player_id: 'p1', answer: '', locked: false, auto_correct: null, override_correct: null }]
  const facit = revealed
    ? { name: 'Born to Run (Remastered 2005 Version)', artist: 'Bruce Springsteen', year: 1975 }
    : null
  const noop = useCallback(() => {}, [])
  return { round, cards, answers, facit, refetch: noop, optimisticCell: noop, optimisticOverride: noop }
}

export function useSyncedAudio() {
  const [volume, setVolume] = useState(0.8)
  return { ready: true, unlock: () => {}, error: null, volume, setVolume }
}

export function useTeamChat() {
  return {
    messages: [
      { id: 'm1', user_id: 'u-2', author_name: 'Sara', body: 'Låter som något från 80-talet?', created_at: new Date().toISOString() },
      { id: 'm2', user_id: 'u-me', author_name: 'Jag', body: 'Jag gissar Depeche Mode, det där syntljudet är deras', created_at: new Date().toISOString() },
    ],
    loading: false,
    error: null,
    send: async () => true,
  }
}

export { ROOM }
