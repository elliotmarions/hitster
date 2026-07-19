-- =====================================================================
--  LÅTSNURRAN – Låtval + facit helt server-side (inte ens värden ser)
--
--  Tidigare valde VÄRDENS webbläsare låten ur en JS-pott, slog upp preview-
--  klippet hos iTunes och skickade in facit via start_track → facit låg i
--  rounds.current_track_meta som alla medlemmar (och värden själv) kunde läsa
--  via API:et MEDAN låten spelade. Nu:
--
--   - Låtpotten bor i tabellen track_pool (RLS utan policyer → oläsbar
--     för klienter; bara SECURITY DEFINER-funktionerna når den).
--   - Servern väljer låt och gör iTunes-uppslaget själv via pg_net.
--   - Facit sparas i round_tracks, vars RLS öppnas FÖRST när rundan
--     avslöjats (answers_revealed). Ingen klient – inte ens värdens –
--     kan se titel/artist/år innan dess.
--
--  pg_net är asynkront (svaret hämtas av en bakgrundsarbetare EFTER att
--  transaktionen committat), så flödet är tvådelat:
--   1. start_random_track: väljer låt (undviker repriser i rummet), skjuter
--      iväg iTunes-sökningen, sparar en rad i pending_tracks och returnerar.
--   2. poll_track_start: värdens klient pollar (~400 ms). När svaret finns
--      parsas det server-side → rundan får preview-URL:en + facit skrivs i
--      round_tracks → alla klienter startar via realtiden som vanligt.
--      Ingen träff → provar bredare sökterm, sedan ny låt (max 5 låtar).
--
--  Sökninglogiken speglar gamla previewApi.js: städad titel + artist först,
--  rå titel + artist sen; träff där artistnamnet matchar föredras.
--
--  Gamla start_track DROPPAS (skrev facit i läsbar kolumn). Kolumnen
--  rounds.current_track_meta behålls tills vidare för pågående rundor
--  (grade-fallback) men skrivs aldrig mer.
--
--  OBS (0023): default privileges ger INTE PUBLIC execute längre → varje ny
--  funktion får explicit grant här. Idempotent. Kör efter 0023.
-- =====================================================================

create extension if not exists pg_net;

-- ====================================================================
--  Tabeller
-- ====================================================================

-- Låtpotten. Inga policyer/grants → bara servern (definer-funktioner) läser.
-- Fylls av 0025_track_pool_data.sql. sv=true → svenska potten.
create table if not exists public.track_pool (
  id     serial primary key,
  title  text not null,
  artist text not null,
  year   int  not null,
  sv     boolean not null default false
);
alter table public.track_pool enable row level security;

-- Facit per runda. Läsbar för rummets medlemmar FÖRST när rundan avslöjats.
create table if not exists public.round_tracks (
  round_id   uuid primary key references public.rounds (id) on delete cascade,
  room_id    uuid not null references public.rooms (id) on delete cascade,
  pool_id    int references public.track_pool (id) on delete set null,
  meta       jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists round_tracks_room_idx on public.round_tracks (room_id);
alter table public.round_tracks enable row level security;

drop policy if exists round_tracks_select_revealed on public.round_tracks;
create policy round_tracks_select_revealed on public.round_tracks
  for select to authenticated using (
    public.is_room_member(room_id)
    and exists (select 1 from public.rounds r where r.id = round_id and r.answers_revealed)
  );
grant select on public.round_tracks to authenticated;

-- Pågående iTunes-uppslag (en per rum). Bara servern rör den.
create table if not exists public.pending_tracks (
  room_id       uuid primary key references public.rooms (id) on delete cascade,
  round_id      uuid not null references public.rounds (id) on delete cascade,
  request_id    bigint not null,
  pool_id       int not null references public.track_pool (id) on delete cascade,
  attempts_left int not null default 5,
  search_stage  int not null default 1,
  created_at    timestamptz not null default now()
);
alter table public.pending_tracks enable row level security;

-- ====================================================================
--  Hjälpare: URL-kodning + titelstädning (port av previewApi.js)
-- ====================================================================

create or replace function public._urlencode(p text)
returns text language plpgsql immutable as $$
declare
  b   bytea := convert_to(coalesce(p, ''), 'UTF8');
  res text  := '';
  i   int;
  byt int;
begin
  for i in 0..octet_length(b) - 1 loop
    byt := get_byte(b, i);
    if (byt between 48 and 57) or (byt between 65 and 90) or (byt between 97 and 122)
       or byt in (45, 46, 95, 126) then  -- - . _ ~
      res := res || chr(byt);
    else
      res := res || '%' || upper(lpad(to_hex(byt), 2, '0'));
    end if;
  end loop;
  return res;
end $$;

-- Städar bort brus (remaster/remix/feat/parenteser) för bättre sökträffar.
create or replace function public._clean_title(t text)
returns text language sql immutable as $$
  select trim(
    regexp_replace(
      regexp_replace(coalesce(t, ''),
        '\s*[-–(].*?(remaster|remastered|mono|stereo|version|mix|edit|single|original|feat|ft|with).*$',
        '', 'i'),
      '\s*\(.*?\)\s*$', '')
  )
$$;

create or replace function public._itunes_search_url(p_term text)
returns text language sql immutable as $$
  select 'https://itunes.apple.com/search?media=music&entity=song&limit=8&country=SE&term='
         || public._urlencode(p_term)
$$;

-- ====================================================================
--  Steg 1: värden begär en slumpad låt
-- ====================================================================
create or replace function public.start_random_track(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_track public.track_pool;
  v_req   bigint;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;
  if v_round.id is null then raise exception 'Snurra först – ingen runda att spela'; end if;
  if v_round.current_track_id is not null then raise exception 'Rundan har redan en låt'; end if;

  -- Kasta ev. gammal påbörjad uppslagning (t.ex. efter avbruten polling).
  delete from public.pending_tracks where room_id = p_room_id;

  -- Slumpa en låt ur rätt pott, undvik repriser i rummet (round_tracks minns).
  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    -- Hela potten spelad i det här rummet → tillåt repriser.
    select tp.* into v_track from public.track_pool tp
      where tp.sv = v_room.swedish_mode order by random() limit 1;
  end if;
  if v_track.id is null then raise exception 'Låtpotten är tom'; end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );

  insert into public.pending_tracks (room_id, round_id, request_id, pool_id, attempts_left, search_stage)
  values (p_room_id, v_round.id, v_req, v_track.id, 5, 1);
end $$;

-- ====================================================================
--  Steg 2: värdens klient pollar tills servern satt låten
--  Returnerar rundan när klar, null-rad medan uppslaget pågår.
-- ====================================================================
create or replace function public.poll_track_start(p_room_id uuid)
returns public.rounds
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_p     public.pending_tracks;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_json   jsonb;
  v_track  public.track_pool;
  v_hit    jsonb;
  v_word   text;
  v_req    bigint;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  select * into v_p from public.pending_tracks where room_id = p_room_id;
  if v_p.room_id is null then
    -- Ingen pågående uppslagning: redan klart om rundan fått sin låt.
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  -- Uppslag som hör till en gammal runda: kasta det.
  if v_round.id is null or v_p.round_id <> v_round.id or v_round.current_track_id is not null then
    delete from public.pending_tracks where room_id = p_room_id;
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

  select status_code, timed_out, content into v_status, v_timed, v_body
    from net._http_response where id = v_p.request_id;
  if not found then
    return null;  -- svaret har inte kommit än → klienten pollar igen
  end if;

  select * into v_track from public.track_pool where id = v_p.pool_id;

  -- Tolka svaret; fel/skräp behandlas som "ingen träff".
  v_hit := null;
  if coalesce(v_status, 0) = 200 and not coalesce(v_timed, false) then
    begin
      v_json := v_body::jsonb;
    exception when others then
      v_json := null;
    end;
    if v_json is not null then
      -- Föredra träff där artistnamnet matchar (första ordet, som previewApi.js).
      v_word := lower(split_part(coalesce(v_track.artist, ''), ' ', 1));
      select r into v_hit
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'previewUrl', '') like 'https://%'
          and lower(coalesce(r ->> 'artistName', '')) like '%' || v_word || '%'
        limit 1;
      if v_hit is null then
        select r into v_hit
          from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
          where coalesce(r ->> 'previewUrl', '') like 'https://%'
          limit 1;
      end if;
    end if;
  end if;

  if v_hit is not null then
    -- Träff! Sätt låten på rundan + spara facit bakom reveal-spärren.
    update public.rounds
      set current_track_id = v_hit ->> 'previewUrl',
          state = 'playing',
          timer_start_at = now() + interval '3 seconds'
      where id = v_round.id
      returning * into v_round;

    insert into public.round_tracks (round_id, room_id, pool_id, meta)
    values (v_round.id, p_room_id, v_track.id,
            jsonb_build_object('name', v_track.title, 'artist', v_track.artist,
                               'year', v_track.year::text))
    on conflict (round_id) do update
      set meta = excluded.meta, pool_id = excluded.pool_id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  -- Ingen träff: prova bredare sökterm (rå titel), därefter en annan låt.
  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 4000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2 where room_id = p_room_id;
    return null;
  end if;

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  select tp.* into v_track from public.track_pool tp
    where tp.sv = v_room.swedish_mode
      and tp.id <> v_p.pool_id
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
    order by random() limit 1;
  if v_track.id is null then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 4000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1
    where room_id = p_room_id;
  return null;
end $$;

-- ====================================================================
--  Rättning läser facit ur round_tracks (fallback: gamla kolumnen,
--  för rundor som startats före den här migrationen).
-- ====================================================================
create or replace function public._grade_round(p_round_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.round_answers ra
    set auto_correct = public._judge_answer(r.category, ra.answer,
                                            coalesce(rt.meta, r.current_track_meta))
    from public.rounds r
    left join public.round_tracks rt on rt.round_id = r.id
    where ra.round_id = p_round_id and r.id = p_round_id;
$$;

-- ====================================================================
--  Antal låtar per pott (lobbyns visning) – potten i övrigt är oläsbar.
-- ====================================================================
create or replace function public.track_pool_counts()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('all', count(*) filter (where not sv),
                            'sv',  count(*) filter (where sv))
  from public.track_pool;
$$;

-- ====================================================================
--  Gamla klient-styrda start_track bort (skrev facit i läsbar kolumn).
-- ====================================================================
drop function if exists public.start_track(uuid, text, jsonb);

-- ====================================================================
--  Behörigheter (explicit sedan 0023)
-- ====================================================================
grant execute on function public.start_random_track(uuid) to authenticated;
grant execute on function public.poll_track_start(uuid) to authenticated;
grant execute on function public.track_pool_counts() to authenticated;

-- Supabase ger nya tabeller grants automatiskt (default privileges); RLS utan
-- policy blockerar ändå alla rader, men vi återkallar uttryckligen.
revoke all on table public.track_pool from authenticated, anon;
revoke all on table public.pending_tracks from authenticated, anon;
revoke insert, update, delete on table public.round_tracks from authenticated, anon;

notify pgrst, 'reload schema';
