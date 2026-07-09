-- =====================================================================
--  LÅTSNURRAN – Oavgjort i statistiken (ingen vinst, räknas som oavgjord)
--
--  Vid oavgjort ska INGEN få en vinst – i stället räknas det som en oavgjord
--  match för alla inblandade. Ny kolumn player_stats.games_tied.
--
--  Trigger-logiken görs om så att:
--   1) Vinst krediteras BARA vid själva avgörandet (playing→finished), inte vid
--      senare omfördelning av vinnare i samma finished-tillstånd.
--   2) När vinnarlistan (winner_unit_ids) ändras MEDAN rummet redan är finished
--      (dvs. en medvinnare tillkommer → oavgjort, eller ångrar → tillbaka till
--      ensam vinnare) räknas det om per enhet:
--        len==1 → 'won', len>=2 → 'tied', ur listan → inget.
--      Deltat won/tied appliceras på alla medlemmar i enheten.
--   Detta kör ALDRIG på reset/spela-igen (finished→playing) → win/oavgjort blir
--   permanent historik. Ett lag som blir oavgjort får sin tidigare vinst
--   återtagen (-1 won) och +1 oavgjord i stället.
--
--  Additiv + idempotent. Kör efter 0021.
-- =====================================================================

alter table public.player_stats
  add column if not exists games_tied int not null default 0;

create or replace function public.on_room_stats()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_old  jsonb;
  v_new  jsonb;
  v_on   int;
  v_nn   int;
  v_unit uuid;
  v_oldc text;
  v_newc text;
  v_wd   int;
  v_td   int;
begin
  -- Ny match startad (lobby/finished -> playing): +1 spelad för alla i rummet.
  if new.status = 'playing' and coalesce(old.status, '') <> 'playing' then
    insert into public.player_stats (user_id, games_played)
    select p.user_id, 1 from public.players p where p.room_id = new.id
    on conflict (user_id) do update
      set games_played = public.player_stats.games_played + 1, updated_at = now();
  end if;

  -- Vinst krediteras bara VID avgörandet (playing -> finished), inte vid senare
  -- omfördelning medan rummet redan är finished (det sköts av oavgjort-blocket).
  if coalesce(old.status, '') <> 'finished' then
    -- Solo
    if new.winner_player_id is not null
       and new.winner_player_id is distinct from old.winner_player_id then
      insert into public.player_stats (user_id, games_won)
      select pl.user_id, 1 from public.players pl where pl.id = new.winner_player_id
      on conflict (user_id) do update
        set games_won = public.player_stats.games_won + 1, updated_at = now();
    end if;
    -- Lag
    if new.winner_team_id is not null
       and new.winner_team_id is distinct from old.winner_team_id then
      insert into public.player_stats (user_id, games_won)
      select pl.user_id, 1 from public.players pl where pl.team_id = new.winner_team_id
      on conflict (user_id) do update
        set games_won = public.player_stats.games_won + 1, updated_at = now();
    end if;
  end if;

  -- OAVGJORT: vinnarlistan ändras MEDAN rummet är finished (medvinnare till/från).
  -- Räkna om varje berörd enhets kredit (won/tied/inget) och applicera deltat.
  if new.status = 'finished' and old.status = 'finished'
     and new.winner_unit_ids is distinct from old.winner_unit_ids then
    v_old := coalesce(old.winner_unit_ids, '[]'::jsonb);
    v_new := coalesce(new.winner_unit_ids, '[]'::jsonb);
    v_on := jsonb_array_length(v_old);
    v_nn := jsonb_array_length(v_new);

    for v_unit in
      select distinct (x)::uuid from (
        select jsonb_array_elements_text(v_old) as x
        union
        select jsonb_array_elements_text(v_new) as x
      ) s
    loop
      v_oldc := case when not (v_old ? v_unit::text) then 'none'
                     when v_on = 1 then 'won' else 'tied' end;
      v_newc := case when not (v_new ? v_unit::text) then 'none'
                     when v_nn = 1 then 'won' else 'tied' end;
      v_wd := (case when v_newc = 'won' then 1 else 0 end)
            - (case when v_oldc = 'won' then 1 else 0 end);
      v_td := (case when v_newc = 'tied' then 1 else 0 end)
            - (case when v_oldc = 'tied' then 1 else 0 end);

      if v_wd <> 0 or v_td <> 0 then
        insert into public.player_stats (user_id, games_won, games_tied)
        select m.user_id, greatest(v_wd, 0), greatest(v_td, 0)
        from (
          select pl.user_id from public.players pl
          where (new.team_mode and pl.team_id = v_unit)
             or (not new.team_mode and pl.id = v_unit)
        ) m
        on conflict (user_id) do update
          set games_won  = greatest(0, public.player_stats.games_won + v_wd),
              games_tied = greatest(0, public.player_stats.games_tied + v_td),
              updated_at = now();
      end if;
    end loop;
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
