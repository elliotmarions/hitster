-- =====================================================================
--  LÅTSNURRAN – värden väljer svarstiden: 30 s, 45 s eller 1 min
--
--  Rundans klocka har varit hårdkodade 25 sekunder i klienten
--  (TIMER_SECONDS). Servern har aldrig dömt efter klockan – lock_answer
--  släpper in svar ända tills rundan avslöjats – så tiden är en ren
--  rumsinställning som alla klienter läser och räknar likadant från
--  rounds.timer_start_at.
--
--  Standard 30 s. Rum som skapats före den här migrationen får också 30 s,
--  fem sekunder mer än förut.
--
--  Låtklippet är fortfarande 25 sekunder (förhandslyssningarna är inte
--  längre än ~30 s, och 25 s är vad uppspelningen är prövad mot). Är
--  svarstiden längre loopar klippet, synkat mot serverns klocka hos alla.
--
--  Idempotent.
-- =====================================================================

alter table public.rooms
  add column if not exists answer_seconds smallint not null default 30;

alter table public.rooms drop constraint if exists rooms_answer_seconds_check;
alter table public.rooms
  add constraint rooms_answer_seconds_check check (answer_seconds in (30, 45, 60));

-- Lobbyns reglage skrivs direkt av värden (RLS: rooms_update_host), som
-- suddregeln. Kolumnlistan i 0070 är hela skyddet, så den nya kolumnen
-- måste läggas till uttryckligen.
grant update (answer_seconds) on public.rooms to authenticated;
