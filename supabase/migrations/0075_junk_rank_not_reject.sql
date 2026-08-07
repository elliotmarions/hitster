-- =====================================================================
--  LÅTSNURRAN – Skräpordsfiltret kastade bort äkta låtar
--
--  Provkörning av städningen (i en tillbakarullad transaktion, innan något
--  hann raderas) visade vad som stod på tur att pensioneras. Bland de första
--  hundra: Clean Bandit "Rockabye", T.I. "Live Your Life", Safri Duo
--  "Played-A-Live". Alla tre finns hos Apple.
--
--  ORSAKEN. Katalogmatchningen i 0072 sållar bort träffar vars titel
--  innehåller ord som "remix", "live", "acoustic", "lullaby", "rockabye" –
--  rimligt när man vill undvika karaokeversioner, men förödande när LÅTEN
--  SJÄLV heter så. "Rockabye" står i listan just för att sålla bort
--  vaggvisecovers, och sållade bort originalet.
--
--  Serverns egen `_itunes_pick` har haft undantaget hela tiden:
--
--      and (x.tn = v_clean or x.tn !~ v_junk_tn)
--
--  – en träff som är EXAKT den sökta titeln godtas oavsett hur den ser ut.
--  Katalogmatchningen ärvde aldrig den raden. Nu görs skräpordet till en
--  RANGORDNING i stället för ett avslag: en ren titel vinner över en
--  "(Live)"-variant, men finns bara den senare tas den.
--
--  Albumnamnet är kvar som hårt avslag, precis som i `_itunes_pick` –
--  karaoke- och tributalbum ska aldrig spelas. Clean Bandit klarar sig ändå:
--  singelomslaget heter "Rockabye … - Single" och faller, men samma låt
--  finns på "Speak Your Mind (Deluxe)" som går igenom.
--
--  OMFATTNING: 12 ohittbara rader har en titel som filtret träffar. Bara de
--  artisterna nollställs för ett nytt försök – inte hela potten.
--
--  DESSUTOM: två rader bär filmfranchisens namn i titeln, "James Bond 007 -
--  Skyfall" och "James Bond 007 - GoldenEye", och matchar därför aldrig
--  Apples "Skyfall" och "GoldenEye". Samma sorts städning som 0054 gjorde.
--  En generell regel för text efter " - " byggs INTE: av de nio rader som
--  har ett sådant prefix ger sju bara skräpsvansar ("Main Title", "Live",
--  "Acoustic", "Law & Order"), och en regel som matchar på "Live" hade
--  kunnat para ihop vad som helst.
--
--  Additiv + idempotent. Kör efter 0074.
-- =====================================================================

-- --- 1. matchningen: skräpord rangordnar, avslår inte ------------------
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

    -- ---- steg 2 och 3: matcha ---------------------------------------
    --  Skillnaden mot 0072: skräpordet i titeln flyttat från WHERE till
    --  ORDER BY. En ren titel vinner, en "(Live)"-variant duger i nödfall.
    with kat as (
      select distinct on (public._norm_title(public._clean_title(trackname)))
             public._norm_title(public._clean_title(trackname)) as ntitel,
             previewurl, track_id
      from public._itunes_rows(v_body)
      where lower(collectionname) !~ v_junk_cn
        and public._norm_title(public._clean_title(trackname)) <> ''
      order by public._norm_title(public._clean_title(trackname)),
               (lower(trackname) ~ v_junk_tn),   -- false före true
               length(trackname)
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
      if v_found = 0 and p.cand_ix < coalesce(array_length(p.cand_ids, 1), 0) then
        v_req := net.http_get(url := public._itunes_catalog_url(p.cand_ids[p.cand_ix + 1]),
                              timeout_milliseconds := 6000);
        update public.artist_probe
           set request_id = v_req, cand_ix = p.cand_ix + 1, requested_at = now()
         where artist_key = p.artist_key and sv = p.sv;
      else
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
      update public.artist_probe
         set stage = 0, request_id = null, probed_at = coalesce(probed_at, now()),
             term_probed_at = now(), found = artist_probe.found + v_found
       where artist_key = p.artist_key and sv = p.sv;
    end if;
    v_n := v_n + 1;
  end loop;

  return v_n;
end $function$;

-- --- 2. Bond-titlarna: franchisen är inte låtens namn ------------------
--  Två rader bär filmserien i titeln och matchar därför aldrig Apples
--  "Skyfall" respektive "GoldenEye". Men de är inte samma fall:
--
--    "James Bond 007 - GoldenEye"  Tina Turner  – "Goldeneye" finns REDAN
--                                  i potten (id 3614) och är spelbar.
--                                  Bond-raden är alltså en DUBBLETT.
--    "James Bond 007 - Skyfall"    Adele        – finns bara i den här
--                                  formen. Ska döpas om.
--
--  Att blint döpa om båda spränger det unika dedup-indexet – vilket det
--  också gjorde vid första körningen. Därför avgörs det per rad: krockar
--  det nya namnet med en befintlig rad är raden en dubblett och pensioneras,
--  annars döps den om.

with kandidat as (
  select id, artist, year, sv, genre, preview_checked_at,
         regexp_replace(title, '^James Bond 007 - ', '') as ny_titel
    from public.track_pool
   where title like 'James Bond 007 - %'
), dubblett as (
  select k.* from kandidat k
   where exists (
     select 1 from public.track_pool tp
      where tp.id <> k.id and tp.sv = k.sv
        and public._track_dedup_key(tp.title, tp.artist)
          = public._track_dedup_key(k.ny_titel, k.artist))
), flytt as (
  insert into public.retired_tracks
    (id, title, artist, year, sv, genre, preview_checked_at, reason)
  select d.id, 'James Bond 007 - ' || d.ny_titel, d.artist, d.year, d.sv, d.genre,
         d.preview_checked_at, 'dubblett: samma låt finns redan utan filmseriens namn'
    from dubblett d
  on conflict (id) do nothing
  returning id
)
delete from public.track_pool tp where tp.id in (select id from flytt);

update public.track_pool
   set title = regexp_replace(title, '^James Bond 007 - ', '')
 where title like 'James Bond 007 - %';

-- --- 3. nytt försök för de artister som filtret kan ha drabbat ---------
update public.artist_probe ap
   set probed_at = null, term_probed_at = null, stage = 0, request_id = null,
       cand_ids = '{}', cand_ix = 0
 where exists (
   select 1 from public.track_pool tp
    where tp.preview_url is null
      and tp.sv = ap.sv
      and public._artist_key(tp.artist) = ap.artist_key
      and (lower(public._clean_title(tp.title)) ~
             '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|sped|slowed|reverb|lullaby|rockabye)\M'
           or tp.title in ('Skyfall', 'GoldenEye')));

revoke all on function public._artist_probe_collect() from public, anon, authenticated;

notify pgrst, 'reload schema';
