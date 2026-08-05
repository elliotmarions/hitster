-- =====================================================================
--  LÅTSNURRAN – Värden får rensa bort en spelare som tappat anslutningen
--
--  Stänger någon fliken låg spelar-raden kvar: lobbyn visade ett spöke som
--  räknades med vid start och fick en egen bricka. leave_room hjälper inte,
--  den raderar bara den EGNA raden och kräver att klienten hinner anropa den.
--
--  Frånvaro syns bara i Realtime Presence, aldrig i Postgres, så servern kan
--  inte avgöra saken själv. Den här RPC:n låter i stället värdens klient –
--  som ser presence – peka ut raden. Servern verifierar det den kan:
--
--    * bara värden i rummet får anropa
--    * bara medan rummet är i lobbyn; mitt i ett spel hänger brickor, svar
--      och lag ihop med spelar-raden, och att rycka bort den vore en helt
--      annan (och farligare) operation
--    * aldrig värden själv – för värden gäller leave_room, som stänger
--      rummet för alla, och det ska inte kunna smyga sig hit
--
--  Additiv + idempotent. Kör efter 0058.
-- =====================================================================

create or replace function public.remove_absent_player(p_room_id uuid, p_player_id uuid)
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
  if v_room.host_user_id <> v_uid then return; end if;
  if v_room.status <> 'lobby' then return; end if;

  delete from public.players
   where id = p_player_id
     and room_id = p_room_id
     and user_id <> v_uid;
end;
$$;

-- ---------------------------------------------------------------------
--  Hjärtslag: "jag är fortfarande här"
-- ---------------------------------------------------------------------
--  0023 tog bort klientens UPDATE-rätt på players, så stämpeln måste gå via
--  en RPC. Kolumnen last_seen_at har funnits sedan 0001 men sattes bara vid
--  anslutning – nu hålls den levande medan man sitter i lobbyn.
create or replace function public.touch_last_seen(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.players
     set last_seen_at = now()
   where room_id = p_room_id
     and user_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
--  Värden försvann → stäng rummet
-- ---------------------------------------------------------------------
--  Värden kan inte städa upp efter sig själv, och remove_absent_player
--  slipper inte in någon annan. Utan den här vägen blir kvarvarande spelare
--  strandsatta i ett rum ingen kan starta – exakt det 0018 löste för det
--  frivilliga utträdet.
--
--  Vem som helst i rummet får anropa, men INTE påstå någonting: klienten
--  säger bara "titta efter", och servern avgör på värdens egen hjärtslags-
--  stämpel. En spelare kan inte göra någon annans stämpel gammal, så det
--  finns inget att ljuga om. Marginalen är rundligt tilltagen mot hjärt-
--  slagets intervall så att en omladdning eller en tunnel aldrig räcker.
create or replace function public.close_room_if_host_absent(p_room_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms;
  v_host_seen timestamptz;
begin
  if v_uid is null then return false; end if;

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then return false; end if;
  if v_room.status <> 'lobby' then return false; end if;

  -- Bara medlemmar i rummet får ens fråga.
  if not exists (
    select 1 from public.players
     where room_id = p_room_id and user_id = v_uid
  ) then
    return false;
  end if;

  select last_seen_at into v_host_seen
    from public.players
   where room_id = p_room_id and user_id = v_room.host_user_id;

  -- Ingen värd-rad kvar, eller en stämpel som stått stilla för länge.
  if v_host_seen is not null and v_host_seen > now() - interval '45 seconds' then
    return false;
  end if;

  update public.rooms
     set status = 'finished',
         ended_reason = 'host_left',
         winner_player_id = null,
         winner_team_id = null
   where id = p_room_id;
  return true;
end;
$$;

-- 0023 slog av default-PUBLIC på nya funktioner; utan de här raderna hade
-- ingen kunnat anropa dem.
grant execute on function public.remove_absent_player(uuid, uuid) to authenticated;
grant execute on function public.touch_last_seen(uuid) to authenticated;
grant execute on function public.close_room_if_host_absent(uuid) to authenticated;

notify pgrst, 'reload schema';
