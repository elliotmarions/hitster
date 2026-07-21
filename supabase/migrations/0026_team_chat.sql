-- =====================================================================
--  LÅTSNURRAN – Lagchatt (privat chatt per lag)
--
--  I lagläge behöver lagkamraterna kunna resonera ("låter som Abba, typ
--  -78?") utan att motståndarna läser med. Varje lag får därför en egen
--  chatt: en rad per meddelande, och RLS släpper bara igenom rader vars
--  team_id matchar det lag DU är placerad i. Motståndare (och värden, om
--  hen spelar i ett annat lag) får inget – inte ens via devtools eller
--  realtidskanalen, som utvärderar samma policy per prenumerant.
--
--  Skrivning sker som vanligt via SECURITY DEFINER-RPC (send_team_message)
--  – ingen insert-policy finns, så klienten kan inte skriva i andras namn
--  eller i ett annat lags chatt.
--
--  author_name är en kopia av spelarnamnet vid skrivtillfället: lämnar
--  någon rummet (players-raden raderas) står historiken kvar läsbar.
--
--  Additiv + idempotent. Kör efter 0025.
-- =====================================================================

create table if not exists public.team_messages (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  team_id     uuid not null references public.teams (id) on delete cascade,
  player_id   uuid references public.players (id) on delete set null,
  user_id     uuid not null references auth.users (id) on delete cascade,
  author_name text not null,
  body        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists team_messages_team_idx on public.team_messages (team_id, created_at);
create index if not exists team_messages_room_idx on public.team_messages (room_id);
create index if not exists team_messages_flood_idx on public.team_messages (user_id, created_at);

-- --- RPC: skicka ett meddelande till mitt lag ------------------------
create or replace function public.send_team_message(p_room_id uuid, p_body text)
returns public.team_messages
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms;
  v_player public.players;
  v_body   text := trim(coalesce(p_body, ''));
  v_recent int;
  v_msg    public.team_messages;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if not v_room.team_mode then raise exception 'Lagchatten finns bara i lagläge'; end if;

  select * into v_player from public.players where room_id = p_room_id and user_id = v_uid;
  if v_player.id is null then raise exception 'Du är inte med i rummet'; end if;
  if v_player.team_id is null then raise exception 'Du är inte i något lag'; end if;

  if v_body = '' then raise exception 'Skriv något först'; end if;
  if length(v_body) > 300 then raise exception 'Meddelandet är för långt (max 300 tecken)'; end if;

  -- Enkel flood-spärr i samma anda som 0023:s övriga gränser.
  select count(*) into v_recent from public.team_messages
    where user_id = v_uid and created_at > now() - interval '10 seconds';
  if v_recent >= 15 then raise exception 'Ta det lugnt – för många meddelanden på kort tid'; end if;

  insert into public.team_messages (room_id, team_id, player_id, user_id, author_name, body)
  values (
    p_room_id,
    v_player.team_id,
    v_player.id,
    v_uid,
    coalesce(nullif(trim(v_player.display_name), ''), 'Spelare'),
    v_body
  )
  returning * into v_msg;

  return v_msg;
end;
$$;

-- --- Row Level Security ----------------------------------------------
alter table public.team_messages enable row level security;

-- Du ser bara meddelanden i DITT lag i DET rummet. (Medlemskapet ligger
-- implicit i players-raden: rätt rum + rätt lag + din user_id.)
drop policy if exists team_messages_select on public.team_messages;
create policy team_messages_select on public.team_messages
  for select to authenticated using (
    exists (
      select 1 from public.players p
      where p.room_id = team_messages.room_id
        and p.user_id = auth.uid()
        and p.team_id = team_messages.team_id
    )
  );
-- (Inga insert/update/delete-policys – all skrivning går via RPC:n ovan.)

-- --- Behörigheter ----------------------------------------------------
-- 0023 återkallade PUBLIC-execute som default → varje ny RPC måste ge
-- rättigheten explicit, annars blir den oanropbar för klienten.
grant select on public.team_messages to authenticated;
grant execute on function public.send_team_message(uuid, text) to authenticated;

-- --- Realtid ---------------------------------------------------------
alter table public.team_messages replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end $$;

notify pgrst, 'reload schema';
