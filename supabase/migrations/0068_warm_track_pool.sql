-- =====================================================================
--  LÅTSNURRAN – Beta av potten i bakgrunden i stället för mitt i festen
--
--  MÄTNING (svenska potten, serverns egen strikta matchning, skarpa svar):
--
--      Rap/Hiphop 2015+   missar 17/22 = 77 %  → 36 % av rundorna faller
--      Pop 2015+          missar  2/22 =  9 %  →  0,0 %
--      Allt före 2005     missar  4/22 = 18 %  →  0,1 %
--
--  Missarna är alltså inte utspridda utan koncentrerade till modern svensk
--  hiphop, som är streamingfödd och aldrig sålts som köpmusik hos Apple.
--  Ingen matchningsfix hjälper – låtarna finns inte. Kontrollerat: en tredje
--  sökning på bara titeln räddade 1 av 17, en fjärde på bara artisten 0.
--
--  0067 lär sig detta, men bara av låtar någon faktiskt drar – alltså mitt
--  under spel, med två bomanrop och några sekunders väntan som pris. Här
--  flyttas inlärningen till ett bakgrundsjobb i stället.
--
--  JOBBET. Två pg_cron-steg varje minut, eftersom pg_net är asynkront:
--    enqueue  – plockar 6 ALDRIG KONTROLLERADE låtar och skickar sökningen
--    collect  – läser färdiga svar, sparar preview-URL eller markerar ohittbar
--
--  Takten är satt efter Apples tak (~20 anrop/min): 6 nya per minut plus
--  eventuella steg 2-omtag ≈ 12, med marginal kvar åt spelet. Potten
--  (~6 000 låtar) är genomgången på ungefär ett dygn, sedan tystnar jobbet
--  av sig självt – det finns inget okontrollerat kvar att göra.
--
--  LIVE-TRAFIKEN GÅR FÖRE: finns en rad i pending_tracks pausar enqueue helt.
--  Ingen ska vänta på sin låtstart för att potten värms.
--
--  TRANSPORTFEL MARKERAR ALDRIG. Ett 403 eller en timeout säger inget om
--  låten; kö-raden slängs bara och låten provas igen ett annat varv.
--
--  STÄNGS AV med:
--      select cron.unschedule('warm-pool-enqueue');
--      select cron.unschedule('warm-pool-collect');
--
--  Dessutom lyfts matchningen ut ur poll_track_start till _itunes_pick, så
--  att spelet och bakgrundsjobbet använder EXAKT samma regler. Två kopior
--  hade garanterat glidit isär, och det är den sortens glid som gav fel
--  facit från början.
--
--  Additiv + idempotent. Kör efter 0067.
-- =====================================================================

-- --- 1. matchningen som egen funktion --------------------------------
--  Returnerar preview-URL:en för bästa godkända träff, annars null.
--  Reglerna är oförändrade sedan 0062: artist på ordgräns, inget
--  karaoke/remix-skräp, och titeln MÅSTE matcha (lika eller prefix åt
--  något håll på hel ordgräns).
create or replace function public._itunes_pick(p_body text, p_title text, p_artist text)
returns text
language plpgsql
immutable
set search_path = public
as $function$
declare
  v_json   jsonb;
  v_word   text;
  v_clean  text;
  v_ntitle text;
  v_url    text;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
begin
  begin
    v_json := p_body::jsonb;
  exception when others then
    return null;
  end;
  if v_json is null then return null; end if;

  v_word := coalesce(
    nullif(split_part(public._norm_title(coalesce(p_artist, '')), ' ', 1), ''),
    public._norm_title(coalesce(p_artist, '')));
  v_clean  := lower(public._clean_title(p_title));
  v_ntitle := public._norm_title(public._clean_title(p_title));
  if v_ntitle = '' then return null; end if;

  select x.r ->> 'previewUrl' into v_url
  from (
    select r,
           lower(coalesce(r ->> 'trackName', ''))      as tn,
           lower(coalesce(r ->> 'collectionName', '')) as cn,
           public._norm_title(r ->> 'trackName')       as ntn,
           public._norm_title(r ->> 'artistName')      as nan
    from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
    where coalesce(r ->> 'previewUrl', '') like 'https://%'
  ) x
  where (v_word = '' or ' ' || x.nan || ' ' like '% ' || v_word || ' %')
    and x.cn !~ v_junk_cn
    and (x.tn = v_clean or x.tn !~ v_junk_tn)
    and (x.ntn = v_ntitle
         or x.ntn like v_ntitle || ' %'
         or v_ntitle like x.ntn || ' %')
  order by
    (case when x.ntn = v_ntitle then 0
          when x.ntn like v_ntitle || ' %' then 1
          else 2 end),
    length(x.tn)
  limit 1;

  return v_url;
end $function$;

-- --- 2. poll_track_start använder samma funktion ----------------------
CREATE OR REPLACE FUNCTION public.poll_track_start(p_room_id uuid)
 RETURNS rounds
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_round public.rounds;
  v_p     public.pending_tracks;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_track  public.track_pool;
  v_url    text;
  v_req    bigint;
  v_bad_net boolean;
begin
  perform public._rate_limit('track_poll', 200, interval '1 minute');
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan starta låten'; end if;

  select * into v_round from public.rounds
    where room_id = p_room_id order by round_number desc limit 1;

  select * into v_p from public.pending_tracks where room_id = p_room_id;
  if v_p.room_id is null then
    if v_round.id is not null and v_round.current_track_id is not null then
      return v_round;
    end if;
    raise exception 'Ingen pågående låtstart';
  end if;

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
    return null;
  end if;

  select * into v_track from public.track_pool where id = v_p.pool_id;

  v_bad_net := coalesce(v_status, 0) <> 200 or coalesce(v_timed, false);
  v_url := null;
  if not v_bad_net then
    v_url := public._itunes_pick(v_body, v_track.title, v_track.artist);
  end if;

  if v_url is not null then
    update public.rounds
      set current_track_id = v_url,
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

    update public.track_pool
      set preview_url = v_url, preview_checked_at = now()
      where id = v_track.id;

    delete from public.pending_tracks where room_id = p_room_id;
    return v_round;
  end if;

  if v_bad_net then
    if v_p.net_retries >= 1 then
      delete from public.pending_tracks where room_id = p_room_id;
      raise exception 'Kunde inte nå musiktjänsten just nu (%) – vänta en stund och försök igen.',
        case when coalesce(v_timed, false) then 'timeout' else 'svar ' || coalesce(v_status, 0)::text end;
    end if;
    v_req := net.http_get(
      url := case when v_p.search_stage = 1
                  then public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist)
                  else public._itunes_search_url(v_track.title || ' ' || v_track.artist) end,
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, net_retries = v_p.net_retries + 1 where room_id = p_room_id;
    return null;
  end if;

  if v_p.search_stage = 1 then
    v_req := net.http_get(
      url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
      timeout_milliseconds := 6000
    );
    update public.pending_tracks
      set request_id = v_req, search_stage = 2, net_retries = 0 where room_id = p_room_id;
    return null;
  end if;

  update public.track_pool
    set preview_url = null, preview_checked_at = now()
    where id = v_p.pool_id;

  if v_p.attempts_left <= 1 then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  select tp.* into v_track from public.track_pool tp
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
      and tp.id <> v_p.pool_id
      and not exists (select 1 from public.round_tracks rt
                      where rt.room_id = p_room_id and rt.pool_id = tp.id)
      and (tp.preview_url is not null
           or tp.preview_checked_at is null
           or tp.preview_checked_at < now() - interval '7 days')
    order by random() limit 1;
  if v_track.id is null then
    delete from public.pending_tracks where room_id = p_room_id;
    raise exception 'Hittade ingen spelbar låt just nu – försök igen.';
  end if;

  if v_track.preview_url is not null
     and v_track.preview_checked_at > now() - interval '30 days' then
    update public.rounds
      set current_track_id = v_track.preview_url,
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

  v_req := net.http_get(
    url := public._itunes_search_url(public._clean_title(v_track.title) || ' ' || v_track.artist),
    timeout_milliseconds := 6000
  );
  update public.pending_tracks
    set request_id = v_req, pool_id = v_track.id,
        attempts_left = v_p.attempts_left - 1, search_stage = 1, net_retries = 0
    where room_id = p_room_id;
  return null;
end $function$;

-- --- 3. kö för bakgrundsuppslagen ------------------------------------
create table if not exists public.pool_warm_queue (
  pool_id      uuid primary key references public.track_pool (id) on delete cascade,
  request_id   bigint not null,
  stage        int not null default 1,
  requested_at timestamptz not null default now()
);
alter table public.pool_warm_queue enable row level security;
revoke all on table public.pool_warm_queue from authenticated, anon;

-- Urvalet letar ALDRIG kontrollerade låtar; delvis index gör det billigt
-- även när potten till slut är genomgången och villkoret matchar noll rader.
create index if not exists track_pool_unchecked_idx
  on public.track_pool (id) where preview_checked_at is null;

-- --- 4. enqueue -------------------------------------------------------
create or replace function public._warm_pool_enqueue(p_batch int default 6)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n   int := 0;
  v_t   record;
  v_req bigint;
begin
  -- Live-trafiken går före: pausa helt medan någon startar en låt.
  if exists (select 1 from public.pending_tracks) then
    return 0;
  end if;

  -- Kö-rader som aldrig blev besvarade ska inte blockera låten för alltid.
  delete from public.pool_warm_queue where requested_at < now() - interval '5 minutes';

  for v_t in
    select tp.id, tp.title, tp.artist
      from public.track_pool tp
     where tp.preview_checked_at is null
       and not exists (select 1 from public.pool_warm_queue q where q.pool_id = tp.id)
     order by random()
     limit greatest(p_batch, 0)
  loop
    v_req := net.http_get(
      url := public._itunes_search_url(public._clean_title(v_t.title) || ' ' || v_t.artist),
      timeout_milliseconds := 6000
    );
    insert into public.pool_warm_queue (pool_id, request_id, stage)
    values (v_t.id, v_req, 1)
    on conflict (pool_id) do update
      set request_id = excluded.request_id, stage = 1, requested_at = now();
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 5. collect -------------------------------------------------------
create or replace function public._warm_pool_collect()
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n      int := 0;
  q        record;
  v_status int;
  v_timed  boolean;
  v_body   text;
  v_track  public.track_pool;
  v_url    text;
  v_req    bigint;
begin
  for q in select * from public.pool_warm_queue loop
    select status_code, timed_out, content into v_status, v_timed, v_body
      from net._http_response where id = q.request_id;
    if not found then
      continue;  -- svaret har inte kommit än
    end if;

    select * into v_track from public.track_pool where id = q.pool_id;
    if v_track.id is null then
      delete from public.pool_warm_queue where pool_id = q.pool_id;
      continue;
    end if;

    -- Transportfel säger inget om låten: släpp kön, prova igen ett annat varv.
    if coalesce(v_status, 0) <> 200 or coalesce(v_timed, false) then
      delete from public.pool_warm_queue where pool_id = q.pool_id;
      continue;
    end if;

    v_url := public._itunes_pick(v_body, v_track.title, v_track.artist);

    if v_url is not null then
      update public.track_pool
        set preview_url = v_url, preview_checked_at = now() where id = q.pool_id;
      delete from public.pool_warm_queue where pool_id = q.pool_id;
    elsif q.stage = 1 then
      -- Bredda till råtiteln, precis som spelet gör.
      v_req := net.http_get(
        url := public._itunes_search_url(v_track.title || ' ' || v_track.artist),
        timeout_milliseconds := 6000
      );
      update public.pool_warm_queue
        set request_id = v_req, stage = 2, requested_at = now() where pool_id = q.pool_id;
    else
      update public.track_pool
        set preview_url = null, preview_checked_at = now() where id = q.pool_id;
      delete from public.pool_warm_queue where pool_id = q.pool_id;
    end if;

    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 6. schemalägg ----------------------------------------------------
do $$
begin
  perform cron.unschedule('warm-pool-enqueue');
exception when others then null;
end $$;
do $$
begin
  perform cron.unschedule('warm-pool-collect');
exception when others then null;
end $$;

select cron.schedule('warm-pool-enqueue', '* * * * *', $$select public._warm_pool_enqueue(6)$$);
select cron.schedule('warm-pool-collect', '* * * * *', $$select public._warm_pool_collect()$$);

grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
