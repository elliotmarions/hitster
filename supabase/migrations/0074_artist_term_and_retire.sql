-- =====================================================================
--  LÅTSNURRAN – Sista chansen per artist, sedan städas potten
--
--  0072 lämnade städningen avstängd med motiveringen att artistkatalogen
--  bara returnerar ett urval, och att Magnus Uggla och Dree Low knappast
--  kunde saknas hos Apple. Den misstanken gick att pröva, och den höll inte.
--
--  MÄTNING (skarpa svar, 2026-08-07/08):
--
--    Magnus Uggla   HELA albumlistan genomsökt – 41 album, 41 uppslag,
--                   varenda låt Apple har på honom – 0 av 6 hittade.
--                   Riktad sökning per låt: 0 titelträffar.
--    Dree Low       28 album, 26 låtar totalt i butiken – 0 av 16.
--
--  Låtarna finns alltså inte. Uggla har hållit sin katalog utanför
--  streamingtjänster förr, och det gäller uppenbarligen Apple också. Det
--  album-uppslag som 0072 väntade på hade inte räddat en enda låt, och är
--  därför inte byggt.
--
--  DÄREMOT gav ett annat anrop utdelning:
--
--      search?term=<artist>&attribute=artistTerm&entity=song&limit=200
--
--  Det är en SÖKNING begränsad till artistnamnet, och den träffar en annan
--  mängd än artistkatalogen. På 18 artister som betningen redan gett upp om
--  hittade den 15 av 86 saknade låtar – 17 % – för ETT anrop per artist.
--  Och inte skräp: Cyndi Lauper "Girls Just Want To Have Fun", Jackson 5
--  "I Want You Back" och "ABC", Sebastian Yatra, Coeur De Pirate.
--
--  Den fungerar dessutom UTAN artist-id, vilket gör den till enda vägen för
--  artister där inget id gick att hitta (Sebastian Yatra hade noll
--  kandidater och fick ändå fyra låtar).
--
--  Nytt steg 3 i betningen alltså, som körs
--    · efter katalogen, och
--    · även när steg 1 inte hittade någon artist alls.
--
--  Kostnad per artist: 1 artistsök + 1–3 kataloger + 1 artistTerm ≈ 3 anrop.
--  Takten sänks därför från 4 till 3 artister i minuten – som mest nio
--  anrop, med marginal under Apples tak.
--
--  STÄDNINGEN SLÅS PÅ. En låt som varken sökningen, artistens katalog eller
--  artistTerm-sökningen kan hitta går inte att spela. Nu finns tre oberoende
--  försök bakom varje beslut, och de raderna flyttas till `retired_tracks`
--  och lämnar potten. Ingenting kastas – titel, artist, år och genre följer
--  med, och en rad kan bäras tillbaka:
--
--      insert into track_pool (title, artist, year, sv, genre)
--      select title, artist, year, sv, genre from retired_tracks where …;
--
--  Additiv + idempotent. Kör efter 0073.
-- =====================================================================

-- --- 1. artistTerm-sökningen -----------------------------------------
create or replace function public._itunes_artist_term_url(p_term text)
returns text language sql immutable set search_path = public as $function$
  select 'https://itunes.apple.com/search?media=music&entity=song&attribute=artistTerm'
         || '&limit=200&country=SE&term=' || public._urlencode(p_term)
$function$;

alter table public.artist_probe
  add column if not exists term_probed_at timestamptz;

-- --- 2. enqueue: nya artister, plus steg 3 åt de redan genomgångna ----
create or replace function public._artist_probe_enqueue(p_batch int default 3)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n     int := 0;
  v_a     record;
  v_req   bigint;
  v_batch int := least(greatest(coalesce(p_batch, 3), 0), 8);
begin
  if exists (select 1 from public.pending_tracks) then
    return 0;
  end if;

  update public.artist_probe
     set stage = 0, request_id = null
   where stage <> 0 and requested_at < now() - interval '5 minutes';

  for v_a in
    select public._artist_key(tp.artist) as artist_key, tp.sv,
           min(tp.artist) as visningsnamn,
           bool_or(ap.probed_at is not null) as redan_katalogprovad
      from public.track_pool tp
      left join public.artist_probe ap
        on ap.artist_key = public._artist_key(tp.artist) and ap.sv = tp.sv
     where tp.preview_url is null
       and public._artist_key(tp.artist) <> ''
       and (ap.artist_key is null
            or (ap.stage = 0
                and (ap.probed_at is null            -- katalogen inte provad
                     or ap.term_probed_at is null    -- artistTerm inte provad
                     or ap.probed_at < now() - interval '90 days')))
     group by 1, 2
     order by count(*) desc, 1
     limit v_batch
  loop
    if v_a.redan_katalogprovad then
      -- Katalogen är redan provad: hoppa direkt till steg 3.
      v_req := net.http_get(url := public._itunes_artist_term_url(v_a.visningsnamn),
                            timeout_milliseconds := 6000);
      update public.artist_probe
         set stage = 3, request_id = v_req, requested_at = now()
       where artist_key = v_a.artist_key and sv = v_a.sv;
    else
      v_req := net.http_get(url := public._itunes_artist_url(v_a.visningsnamn),
                            timeout_milliseconds := 6000);
      insert into public.artist_probe (artist_key, sv, stage, request_id, requested_at)
      values (v_a.artist_key, v_a.sv, 1, v_req, now())
      on conflict (artist_key, sv) do update
        set stage = 1, request_id = excluded.request_id, requested_at = now(),
            cand_ids = '{}', cand_ix = 0;
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 3. collect: tre steg -------------------------------------------
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
  v_namn    text;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
begin
  for p in select * from public.artist_probe where stage in (1, 2, 3) loop
    select status_code, timed_out, content into v_status, v_timed, v_body
      from net._http_response where id = p.request_id;
    if not found then
      continue;
    end if;

    if coalesce(v_status, 0) <> 200 or coalesce(v_timed, false) then
      update public.artist_probe set stage = 0, request_id = null
       where artist_key = p.artist_key and sv = p.sv;
      v_n := v_n + 1;
      continue;
    end if;

    -- Namnet att söka på, hämtat ur potten.
    select min(tp.artist) into v_namn from public.track_pool tp
     where tp.preview_url is null and tp.sv = p.sv
       and public._artist_key(tp.artist) = p.artist_key;

    -- ---- steg 1: välj artist-id ------------------------------------
    if p.stage = 1 then
      begin
        v_json := v_body::jsonb;
      exception when others then
        v_json := null;
      end;

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

      -- Ingen artist? artistTerm behöver inget id – gå direkt till steg 3.
      if v_cands is null or array_length(v_cands, 1) is null then
        v_req := net.http_get(url := public._itunes_artist_term_url(coalesce(v_namn, p.artist_key)),
                              timeout_milliseconds := 6000);
        update public.artist_probe
           set stage = 3, request_id = v_req, requested_at = now(), probed_at = now()
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

    -- ---- steg 2 och 3: matcha svaret mot artistens ohittbara låtar ---
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

    if p.stage = 2 then
      -- Noll träffar och fler kandidat-id kvar? Då var det fel namne.
      if v_found = 0 and p.cand_ix < coalesce(array_length(p.cand_ids, 1), 0) then
        v_req := net.http_get(url := public._itunes_catalog_url(p.cand_ids[p.cand_ix + 1]),
                              timeout_milliseconds := 6000);
        update public.artist_probe
           set request_id = v_req, cand_ix = p.cand_ix + 1, requested_at = now()
         where artist_key = p.artist_key and sv = p.sv;
      else
        -- Katalogen färdig. Kvarstår något: sista chansen via artistTerm.
        if exists (select 1 from public.track_pool tp
                    where tp.preview_url is null and tp.sv = p.sv
                      and public._artist_key(tp.artist) = p.artist_key) then
          v_req := net.http_get(url := public._itunes_artist_term_url(coalesce(v_namn, p.artist_key)),
                                timeout_milliseconds := 6000);
          update public.artist_probe
             set stage = 3, request_id = v_req, requested_at = now(),
                 probed_at = now(), found = artist_probe.found + v_found
           where artist_key = p.artist_key and sv = p.sv;
        else
          update public.artist_probe
             set stage = 0, request_id = null, probed_at = now(),
                 term_probed_at = now(), found = artist_probe.found + v_found
           where artist_key = p.artist_key and sv = p.sv;
        end if;
      end if;
    else
      -- steg 3 klart: artisten är färdigbehandlad.
      update public.artist_probe
         set stage = 0, request_id = null, probed_at = coalesce(probed_at, now()),
             term_probed_at = now(), found = artist_probe.found + v_found
       where artist_key = p.artist_key and sv = p.sv;
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 4. städningen kräver att ALLA TRE försöken är gjorda -------------
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
       and tp.preview_checked_at is not null      -- 1. sökningen har provat
       and ap.probed_at is not null               -- 2. artistkatalogen har provat
       and ap.term_probed_at is not null          -- 3. artistTerm har provat
       and ap.term_probed_at < now() - interval '2 hours'
     limit least(greatest(coalesce(p_batch, 50), 0), 500)
  ), flytt as (
    insert into public.retired_tracks
      (id, title, artist, year, sv, genre, preview_checked_at, reason)
    select id, title, artist, year, sv, genre, preview_checked_at,
           'ingen träff hos Apple: sökning, artistkatalog och artistTerm har alla provats'
      from klara
    on conflict (id) do nothing
    returning id
  )
  delete from public.track_pool tp where tp.id in (select id from flytt);

  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- --- 5. schemalägg ---------------------------------------------------
do $$ begin perform cron.unschedule('artist-probe-enqueue'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('retire-unplayable');    exception when others then null; end $$;

select cron.schedule('artist-probe-enqueue', '* * * * *', $$select public._artist_probe_enqueue(3)$$);
select cron.schedule('retire-unplayable',   '*/5 * * * *', $$select public._retire_unplayable(50)$$);

revoke all on function public._itunes_artist_term_url(text)  from public, anon, authenticated;
revoke all on function public._artist_probe_enqueue(int)     from public, anon, authenticated;
revoke all on function public._artist_probe_collect()        from public, anon, authenticated;
revoke all on function public._retire_unplayable(int)        from public, anon, authenticated;

notify pgrst, 'reload schema';
