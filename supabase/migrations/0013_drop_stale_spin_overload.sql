-- =====================================================================
--  HITSTER BINGO ONLINE – Ta bort gammal spin_wheel-överlagring
--
--  Live-DB:n har en kvarlämnad variant spin_wheel(uuid, text, jsonb) från
--  en tidig design där snurr och låtstart var ihopkopplade. Sedan 0003/0005
--  är flödet frikopplat och den enda korrekta signaturen är spin_wheel(uuid).
--  Med båda kvar blir klientens anrop tvetydigt (PostgREST PGRST203) → snurr
--  slutar fungera. Droppa den gamla. Finns den inte är detta en no-op.
--
--  Idempotent. Kör efter 0012.
-- =====================================================================

drop function if exists public.spin_wheel(uuid, text, jsonb);

notify pgrst, 'reload schema';
