-- =====================================================================
--  LÅTSNURRAN – Värden lämnar → spelet avslutas för alla
--
--  Tidigare raderade "Lämna rummet" bara den egna spelar-raden (direkt
--  DELETE mot players). Om VÄRDEN lämnade blev de kvarvarande spelarna
--  strandsatta i ett rum utan värd (ingen kan snurra/starta om).
--
--  Nu går utträdet via RPC:n leave_room: den tar bort den egna spelar-raden,
--  och om det är VÄRDEN som lämnar ett ej-avslutat rum sätts rummet till
--  status='finished' med ended_reason='host_left' → alla kvarvarande klienter
--  ser en liten ruta "Värden lämnade – spelet avslutades". Icke-värdar som
--  lämnar påverkar inte rummet (som förr).
--
--  ended_reason skiljer detta från en vanlig vinst (som lämnar reason=null).
--  Additiv + idempotent. Kör efter 0017.
-- =====================================================================

alter table public.rooms
  add column if not exists ended_reason text;

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then return; end if;
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then return; end if;

  -- Ta bort min egen spelar-rad (om jag är med i rummet).
  delete from public.players where room_id = p_room_id and user_id = v_uid;

  -- Om VÄRDEN lämnar ett rum som inte redan är avslutat: avsluta för alla.
  if v_room.host_user_id = v_uid and v_room.status <> 'finished' then
    update public.rooms
      set status = 'finished',
          ended_reason = 'host_left',
          winner_player_id = null,
          winner_team_id = null
      where id = p_room_id;
  end if;
end;
$$;

notify pgrst, 'reload schema';
