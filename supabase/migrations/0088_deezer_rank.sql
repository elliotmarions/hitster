-- =====================================================================
--  LÅTSNURRAN – popularitet i låtpotten
--
--  Deezers `rank` (0 till ~1 000 000) mäter hur mycket en låt spelas. Den
--  behövs för Sjung vidare: bara låtar som många kan går att sjunga med i.
--  Värdena fylls av ett skript som slår upp varje låt i Deezers öppna
--  sök-API (ingen nyckel). NULL = inte uppslagen än; 0 = uppslagen men
--  ingen säker träff.
--
--  Idempotent.
-- =====================================================================

alter table public.track_pool
  add column if not exists deezer_rank integer,
  add column if not exists deezer_checked_at timestamptz;

create index if not exists track_pool_deezer_rank_idx
  on public.track_pool (sv, deezer_rank);
