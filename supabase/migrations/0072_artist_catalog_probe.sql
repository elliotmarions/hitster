-- =====================================================================
--  LÅTSNURRAN – Beta potten ARTISTVIS, och städa bort det som ändå inte går
--
--  0071 visade att sökningen är fel verktyg: den missade tio av tio svenska
--  raplåtar som låg i artistens katalog hela tiden. Läkningen där gjordes
--  för hand, för 39 artister. Kvar står 950 ohittbara låtar fördelade på
--  705 artistuppslag – 576 av artisterna har EN enda låt. Det är för mycket
--  för handpåläggning och för lite för att göra en migration per artist.
--
--  Alltså: bakgrundsjobbet får göra det. Två nya cron-steg vid sidan av de
--  gamla, som arbetar per ARTIST i stället för per låt:
--
--    steg 1   search?term=<artist>&entity=musicArtist   → artist-id
--    steg 2   lookup?id=<id>&entity=song&limit=200      → hela katalogen,
--             matchas mot ALLA artistens ohittbara låtar på en gång
--
--  Ett uppslag på fyra artister i minuten kostar som mest åtta anrop – lika
--  mycket som den gamla betningen – och 705 artister är genomgångna på
--  ungefär tre timmar. Sedan tystnar jobbet tills nya ohittbara dyker upp.
--
--  FEL NAMNE ÄR DEN STORA FÄLLAN. Vid handkörningen matchade "Einár" en
--  namne som stavade sig "EINAR" och hade sex låtar i katalogen i stället
--  för rätt artist med 94. Därför sparas upp till tre kandidat-id:n, och
--  ger den första katalogen NOLL träffar provas nästa. Rätt artist känns
--  igen på att låtarna faktiskt matchar – inte på att namnet såg rätt ut.
--
--  STÄDNINGEN. En låt som varken sökningen eller artistens katalog kan
--  hitta går inte att spela, och en opsellbar rad i potten fyller ingen
--  funktion – den tar bara plats i urvalet och kostar bomanrop. Sådana
--  rader flyttas till `retired_tracks` och tas bort ur potten. Ingenting
--  kastas: titel, artist, år och genre följer med, så en rad kan bäras
--  tillbaka den dag Apple får in låten:
--
--      insert into track_pool (title, artist, year, sv, genre)
--      select title, artist, year, sv, genre from retired_tracks where id = …;
--
--  Städningen rör BARA artister som redan är genomgångna (`probed_at`), och
--  först två timmar efteråt – hinner något gå fel i matchningen syns det i
--  potten innan raderna försvinner.
--
--  Additiv + idempotent. Kör efter 0071.
-- =====================================================================

-- --- 1. hjälpare ------------------------------------------------------

-- Huvudartisten, normaliserad: det som står före feat/ft/with/vs och före
-- första kommat, &-tecknet, snedstrecket eller parentesen.
create or replace function public._artist_key(p text)
returns text language sql immutable set search_path = public as $function$
  select public._norm_title(
    regexp_replace(
      regexp_replace(coalesce(p, ''), '\s*(?:feat\.?|ft\.?|with|vs\.?)\s.*$', '', 'i'),
      '\s*[,&/(].*$', ''))
$function$;

create or replace function public._itunes_artist_url(p_term text)
returns text language sql immutable set search_path = public as $function$
  select 'https://itunes.apple.com/search?media=music&entity=musicArtist&limit=8&country=SE&term='
         || public._urlencode(p_term)
$function$;

create or replace function public._itunes_catalog_url(p_artist_id bigint)
returns text language sql immutable set search_path = public as $function$
  select 'https://itunes.apple.com/lookup?entity=song&limit=200&country=SE&id='
         || p_artist_id::text
$function$;

-- Träffarna som rader. Samma svarsform för både search och lookup.
create or replace function public._itunes_rows(p_body text)
returns table (trackname text, artistname text, collectionname text,
               previewurl text, track_id bigint, ar int)
language plpgsql immutable set search_path = public as $function$
declare
  v_json jsonb;
begin
  begin
    v_json := p_body::jsonb;
  exception when others then
    return;
  end;
  if v_json is null then return; end if;

  return query
  select r ->> 'trackName',
         r ->> 'artistName',
         coalesce(r ->> 'collectionName', ''),
         r ->> 'previewUrl',
         nullif(r ->> 'trackId', '')::bigint,
         nullif(left(coalesce(r ->> 'releaseDate', ''), 4), '')::int
  from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
  where coalesce(r ->> 'previewUrl', '') like 'https://%'
    and coalesce(r ->> 'wrapperType', '') = 'track'
    and coalesce(r ->> 'trackName', '') <> '';
end $function$;

-- --- 2. kön ----------------------------------------------------------
create table if not exists public.artist_probe (
  artist_key   text    not null,
  sv           boolean not null,
  stage        int     not null default 0,   -- 0 = vilande, 1 = artistsök ute, 2 = katalog ute
  request_id   bigint,
  cand_ids     bigint[] not null default '{}',
  cand_ix      int     not null default 0,
  found        int     not null default 0,
  probed_at    timestamptz,                  -- satt när artisten är färdigbehandlad
  requested_at timestamptz,
  primary key (artist_key, sv)
);
alter table public.artist_probe enable row level security;
revoke all on table public.artist_probe from anon, authenticated;

create table if not exists public.retired_tracks (
  id                 int primary key,
  title              text,
  artist             text,
  year               int,
  sv                 boolean,
  genre              text,
  preview_checked_at timestamptz,
  retired_at         timestamptz not null default now(),
  reason             text
);
alter table public.retired_tracks enable row level security;
revoke all on table public.retired_tracks from anon, authenticated;

-- --- 3. enqueue: plocka artister med ohittbara låtar ------------------
create or replace function public._artist_probe_enqueue(p_batch int default 4)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n     int := 0;
  v_a     record;
  v_req   bigint;
  v_batch int := least(greatest(coalesce(p_batch, 4), 0), 8);
begin
  -- Live-trafiken går före.
  if exists (select 1 from public.pending_tracks) then
    return 0;
  end if;

  -- Uppslag som aldrig besvarades ska inte låsa artisten för alltid.
  update public.artist_probe
     set stage = 0, request_id = null
   where stage <> 0 and requested_at < now() - interval '5 minutes';

  for v_a in
    select public._artist_key(tp.artist) as artist_key, tp.sv,
           min(tp.artist) as visningsnamn
      from public.track_pool tp
      left join public.artist_probe ap
        on ap.artist_key = public._artist_key(tp.artist) and ap.sv = tp.sv
     where tp.preview_url is null
       and public._artist_key(tp.artist) <> ''
       and (ap.artist_key is null
            or (ap.stage = 0 and (ap.probed_at is null
                                  or ap.probed_at < now() - interval '90 days')))
     group by 1, 2
     order by count(*) desc, 1
     limit v_batch
  loop
    v_req := net.http_get(
      url := public._itunes_artist_url(v_a.visningsnamn),
      timeout_milliseconds := 6000
    );
    insert into public.artist_probe (artist_key, sv, stage, request_id, requested_at)
    values (v_a.artist_key, v_a.sv, 1, v_req, now())
    on conflict (artist_key, sv) do update
      set stage = 1, request_id = excluded.request_id, requested_at = now(),
          cand_ids = '{}', cand_ix = 0;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 4. collect: läs svaren, läk låtarna ------------------------------
create or replace function public._artist_probe_collect()
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n       int := 0;
  p         record;
  v_status  int;
  v_timed   boolean;
  v_body    text;
  v_json    jsonb;
  v_cands   bigint[];
  v_req     bigint;
  v_found   int;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
begin
  for p in select * from public.artist_probe where stage in (1, 2) loop
    select status_code, timed_out, content into v_status, v_timed, v_body
      from net._http_response where id = p.request_id;
    if not found then
      continue;  -- svaret har inte kommit än
    end if;

    -- Transportfel säger inget om artisten: släpp och prova ett annat varv.
    if coalesce(v_status, 0) <> 200 or coalesce(v_timed, false) then
      update public.artist_probe set stage = 0, request_id = null
       where artist_key = p.artist_key and sv = p.sv;
      v_n := v_n + 1;
      continue;
    end if;

    -- ---- steg 1: välj artist-id ur sökträffarna ----------------------
    if p.stage = 1 then
      begin
        v_json := v_body::jsonb;
      exception when others then
        v_json := null;
      end;

      -- Exakt namnmatch först, sedan prefix. Högst tre kandidater – rätt
      -- artist avgörs av att katalogen faktiskt matchar låtarna.
      select array_agg(x.aid order by x.rang, x.ord) into v_cands
      from (
        select (r ->> 'artistId')::bigint as aid,
               row_number() over () as ord,
               case when public._norm_title(r ->> 'artistName') = p.artist_key then 0
                    when public._norm_title(r ->> 'artistName') like p.artist_key || ' %' then 1
                    else 2 end as rang
        from jsonb_array_elements(coalesce(v_json -> 'results', '[]'::jsonb)) r
        where coalesce(r ->> 'artistId', '') <> ''
          and (public._norm_title(r ->> 'artistName') = p.artist_key
               or public._norm_title(r ->> 'artistName') like p.artist_key || ' %')
        limit 3
      ) x;

      if v_cands is null or array_length(v_cands, 1) is null then
        update public.artist_probe
           set stage = 0, request_id = null, probed_at = now(), found = 0
         where artist_key = p.artist_key and sv = p.sv;
        v_n := v_n + 1;
        continue;
      end if;

      v_req := net.http_get(url := public._itunes_catalog_url(v_cands[1]),
                            timeout_milliseconds := 6000);
      update public.artist_probe
         set stage = 2, request_id = v_req, cand_ids = v_cands, cand_ix = 1,
             requested_at = now()
       where artist_key = p.artist_key and sv = p.sv;
      v_n := v_n + 1;
      continue;
    end if;

    -- ---- steg 2: matcha katalogen mot artistens ohittbara låtar ------
    with kat as (
      select distinct on (public._norm_title(public._clean_title(trackname)))
             public._norm_title(public._clean_title(trackname)) as ntitel,
             previewurl, track_id
      from public._itunes_rows(v_body)
      where lower(collectionname) !~ v_junk_cn
        and lower(trackname) !~ v_junk_tn
        and public._norm_title(public._clean_title(trackname)) <> ''
      order by public._norm_title(public._clean_title(trackname)), length(trackname)
    )
    update public.track_pool tp
       set preview_url        = k.previewurl,
           itunes_track_id    = k.track_id,
           preview_source     = 'catalog',
           preview_checked_at = now()
      from kat k
     where tp.preview_url is null
       and tp.sv = p.sv
       and public._artist_key(tp.artist) = p.artist_key
       and public._norm_title(public._clean_title(tp.title)) = k.ntitel;
    get diagnostics v_found = row_count;

    -- Noll träffar och fler kandidater kvar? Då var det fel namne.
    if v_found = 0 and p.cand_ix < coalesce(array_length(p.cand_ids, 1), 0) then
      v_req := net.http_get(url := public._itunes_catalog_url(p.cand_ids[p.cand_ix + 1]),
                            timeout_milliseconds := 6000);
      update public.artist_probe
         set request_id = v_req, cand_ix = p.cand_ix + 1, requested_at = now()
       where artist_key = p.artist_key and sv = p.sv;
    else
      update public.artist_probe
         set stage = 0, request_id = null, probed_at = now(),
             found = artist_probe.found + v_found
       where artist_key = p.artist_key and sv = p.sv;
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 5. städningen ---------------------------------------------------
create or replace function public._retire_unplayable(p_batch int default 50)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n int := 0;
begin
  with klara as (
    select tp.id, tp.title, tp.artist, tp.year, tp.sv, tp.genre, tp.preview_checked_at
      from public.track_pool tp
      join public.artist_probe ap
        on ap.artist_key = public._artist_key(tp.artist) and ap.sv = tp.sv
     where tp.preview_url is null
       and tp.preview_checked_at is not null   -- sökningen har provat
       and ap.probed_at is not null            -- katalogen har provat
       and ap.probed_at < now() - interval '2 hours'
     limit least(greatest(coalesce(p_batch, 50), 0), 500)
  ), flytt as (
    insert into public.retired_tracks
      (id, title, artist, year, sv, genre, preview_checked_at, reason)
    select id, title, artist, year, sv, genre, preview_checked_at,
           'ingen träff hos Apple: varken sökning eller artistkatalog'
      from klara
    on conflict (id) do nothing
    returning id
  )
  delete from public.track_pool tp where tp.id in (select id from flytt);

  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- --- 6. schemalägg ---------------------------------------------------
do $$ begin perform cron.unschedule('artist-probe-enqueue'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('artist-probe-collect'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('retire-unplayable');    exception when others then null; end $$;

select cron.schedule('artist-probe-enqueue', '* * * * *', $$select public._artist_probe_enqueue(4)$$);
select cron.schedule('artist-probe-collect', '* * * * *', $$select public._artist_probe_collect()$$);

--  STÄDNINGEN ÄR MEDVETET INTE SCHEMALAGD ÄNNU.
--
--  Den var det i tio minuter, tills de första resultaten kom in: av de
--  artister som hunnit bli klara gav 73 låtar noll katalogträff, och bland
--  dem fanns Dree Low (23 låtar), Magnus Uggla (6) och Bob Hund. Att Magnus
--  Uggla inte skulle finnas hos Apple är inte trovärdigt.
--
--  Orsaken är känd sedan 0071: `lookup?entity=song` returnerar bara ett
--  URVAL per artist, inte hela katalogen – 55 låtar för Dree Low mot 143
--  för Yasin. En miss där bevisar alltså ingenting, och att radera på det
--  underlaget vore fel.
--
--  Funktionen ligger kvar, redo. Den schemaläggs när ett djupare uppslag
--  (artist → album → låtar per album) också har fått säga sitt:
--
--      select cron.schedule('retire-unplayable', '*/5 * * * *',
--                           $q$select public._retire_unplayable(50)$q$);

revoke all on function public._artist_key(text)              from public, anon, authenticated;
revoke all on function public._itunes_artist_url(text)       from public, anon, authenticated;
revoke all on function public._itunes_catalog_url(bigint)    from public, anon, authenticated;
revoke all on function public._itunes_rows(text)             from public, anon, authenticated;
revoke all on function public._artist_probe_enqueue(int)     from public, anon, authenticated;
revoke all on function public._artist_probe_collect()        from public, anon, authenticated;
revoke all on function public._retire_unplayable(int)        from public, anon, authenticated;

notify pgrst, 'reload schema';
