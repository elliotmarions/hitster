-- =====================================================================
--  LÅTSNURRAN – Låt bakgrundsjobbet hålla potten varm, inte bara beta den
--
--  LÄGET EFTER 0068 (mätt mot live-DB 2026-08-07): potten är genombetad.
--  9 797 låtar, 0 okontrollerade, 8 443 spelbara, 1 354 ohittbara (13,8 %).
--  Allt kontrollerades under 5–6 augusti. Jobbet har alltså gjort sitt –
--  och kommer aldrig att göra något mer, för `_warm_pool_enqueue` plockar
--  BARA rader med `preview_checked_at is null`.
--
--  PROBLEMET: urvalets två TTL:er tickar vidare ändå.
--
--    7 dagar   start_random_track släpper in ohittbara låtar igen
--              (`preview_checked_at < now() - interval '7 days'`).
--              ~12 aug börjar de 1 354 kosta två bomanrop var MITT I SPELET
--              igen – precis den väntan 0067 byggdes för att ta bort – och
--              sedan varje vecka, eftersom bara spelandet markerar om dem.
--
--    30 dagar  cacheträffen kräver färsk kontroll. Hela potten kontrollerades
--              inom samma dygn, så omkring 4–5 sept blir CACHEN KALL PÅ EN
--              GÅNG och varje låtstart går tillbaka till live-uppslag.
--
--  Båda hålen har samma orsak och samma fix: jobbet måste titta på rader det
--  redan tittat på. Nu plockar enqueue tre sorters kandidater, äldst först:
--
--    aldrig kontrollerad          – nytillskott i potten (nulls first)
--    ohittbar äldre än 6 dagar    – provas om FÖRE spelets 7-dagarsgräns
--    cachad äldre än 25 dagar     – förnyas FÖRE spelets 30-dagarsgräns
--
--  Marginalerna (1 dygn respektive 5 dygn) är valda så att jobbet hinner
--  först. Vid 6 låtar/min = 8 640/dygn tar en full omgång av 9 797 rader
--  drygt ett dygn, alltså väl inom 5-dygnsmarginalen även om alla 8 443
--  cachade förfaller samma dag (vilket de gör, eftersom de betades samma dag).
--
--  Takten är OFÖRÄNDRAD – 6 nya per minut, plus eventuella steg 2-omtag, med
--  marginal under Apples ~20/min. Live-trafiken går fortfarande före
--  (pending_tracks pausar enqueue helt) och transportfel markerar aldrig.
--
--  Jobbet tystnar inte längre av sig självt, men det blir heller aldrig
--  högljutt: när inget förfallit matchar villkoret noll rader och funktionen
--  returnerar 0.
--
--  ---------------------------------------------------------------------
--  DESSUTOM: BAKGRUNDSJOBBET VAR ÖPPET FÖR VEM SOM HELST.
--
--  Kontroll av live-DB visade att `_warm_pool_enqueue` och
--  `_warm_pool_collect` hade EXECUTE för anon och authenticated. 0023 satte
--  `alter default privileges ... revoke execute on functions from public`,
--  men den inställningen är sedan dess ÅTERSTÄLLD av plattformen – i
--  `pg_default_acl` står numera `postgres=X anon=X authenticated=X
--  service_role=X` för funktioner igen. Allt som skapats efter det är
--  alltså anropbart av vilken gäst som helst.
--
--  För just de här två är det illa: de är SECURITY DEFINER, saknar
--  `_rate_limit`, och `p_batch` styrs av anroparen –
--  `select _warm_pool_enqueue(100000)` hade lagt hundratusen utgående
--  anrop i pg_net-kön och bränt hela IP:ns kvot hos Apple. Här återkallas
--  rättigheten och batchen tvingas in i intervallet 0–12 oavsett anropare.
--  Cron påverkas inte; jobben körs som ägaren (postgres).
--
--  ÖVRIGA funktioner som skapats efter 0023 har samma öppna default och
--  behöver en egen genomgång – de flesta är ofarliga (rena hjälpfunktioner)
--  eller skyddade av interna auth.uid()-kontroller, men listan bör städas.
--  ---------------------------------------------------------------------
--
--  Additiv + idempotent. Kör efter 0068.
-- =====================================================================

-- Ordningen "äldst först" ska vara en indexskanning, inte en sortering av
-- hela potten varje minut. nulls first matchar order by nedan.
create index if not exists track_pool_checked_at_idx
  on public.track_pool (preview_checked_at nulls first);

create or replace function public._warm_pool_enqueue(p_batch int default 6)
returns int
language plpgsql security definer set search_path = public
as $function$
declare
  v_n   int := 0;
  v_t   record;
  v_req bigint;
  -- Taket är hårt: anroparen får aldrig sätta en batch som spränger
  -- Apples ~20/min, oavsett vad som skickas in.
  v_batch int := least(greatest(coalesce(p_batch, 6), 0), 12);
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
     where not exists (select 1 from public.pool_warm_queue q where q.pool_id = tp.id)
       and (
            -- aldrig kontrollerad
            tp.preview_checked_at is null
            -- ohittbar: prova om före spelets 7-dagarsgräns
         or (tp.preview_url is null
             and tp.preview_checked_at < now() - interval '6 days')
            -- cachad: förnya före spelets 30-dagarsgräns
         or (tp.preview_url is not null
             and tp.preview_checked_at < now() - interval '25 days')
       )
     order by tp.preview_checked_at asc nulls first
     limit v_batch
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

-- Ingen grant: funktionerna körs bara av pg_cron som ägare, aldrig av
-- klienter. Plattformens default-privilegier delar ut EXECUTE till anon och
-- authenticated på nytt (se noten överst), så återkallandet måste vara
-- uttryckligt och stå EFTER create or replace.
revoke all on function public._warm_pool_enqueue(int) from public, anon, authenticated;
revoke all on function public._warm_pool_collect()    from public, anon, authenticated;

notify pgrst, 'reload schema';
