-- ====================================================================
--  0029  Åldersgrupp: kolumn-grant för year_min / year_max
-- --------------------------------------------------------------------
--  Säkerhetshärdningen (0023) återkallade UPDATE på public.rooms och gav
--  bara tillbaka (erase_rule_enabled, team_mode, swedish_mode). När
--  åldersgruppsfönstret (0026_age_group_window) la till year_min/year_max
--  glömdes de kolumnerna i grant:en → värdens skrivning nekades tyst och
--  lobbyn hoppade tillbaka till "Blandat".
--
--  Här utökas grant:en så värden får sätta årsfönstret. Radbegränsningen
--  (bara värdens eget rum) ligger kvar i policyn rooms_update_host.
-- ====================================================================

grant update (year_min, year_max) on public.rooms to authenticated;
