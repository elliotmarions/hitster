-- ====================================================================
--  0058  Språkvalet får tre lägen: svenska, utländska, allt
-- --------------------------------------------------------------------
--  Under Språk fanns bara "Svenska". Vill man spela utan svenska låtar –
--  vilket är hela poängen med en internationell omgång – gick det inte:
--  ovald chip betyder "ingen språkgräns", alltså allt inklusive svenskt.
--  Efter 0047 är 43 % av potten svensk, så det märks.
--
--  LÖSNING utan att röra låtväljarna: swedish_mode blir NULLBAR och bär
--  tre lägen i stället för två.
--
--      true   → bara svenska
--      false  → bara utländska
--      null   → ingen språkgräns (allt)
--
--  Poängen med just den formen: _pool_match() behåller sin signatur
--  (boolean), så start_random_track och poll_track_start – som är långa och
--  har byggts på i sju omgångar var – behöver inte skrivas om igen. Bara
--  det lilla filtret och räknaren ändras.
--
--  MIGRERING AV BEFINTLIGA RUM: efter 0057 betydde false "ingen
--  språkgräns". Alla false blir därför null, annars hade varje befintligt
--  rum tyst bytt till "bara utländska". Av samma skäl måste kolumnens
--  DEFAULT bort – ett nytt rum ska starta på allt, inte på utländskt.
--
--  Additiv + idempotent. Kör efter 0057.
-- ====================================================================

-- --- 1. tre lägen i stället för två ---
alter table public.rooms alter column swedish_mode drop not null;
alter table public.rooms alter column swedish_mode drop default;

-- false betydde "ingen språkgräns" efter 0057 – behåll den innebörden.
update public.rooms set swedish_mode = null where swedish_mode = false;

-- --- 2. filtret ---
create or replace function public._pool_match(
  p_track   public.track_pool,
  p_swedish boolean,
  p_bands   jsonb,
  p_genres  jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    -- språk: null = ingen gräns, annars måste sv matcha exakt
    (p_swedish is null or p_track.sv = p_swedish)
    -- åldersspann: union, tom lista = ingen gräns
    and (coalesce(jsonb_array_length(p_bands), 0) = 0 or exists (
          select 1 from jsonb_array_elements(p_bands) b
           where (b ->> 'min' is null or p_track.year >= (b ->> 'min')::int)
             and (b ->> 'max' is null or p_track.year <= (b ->> 'max')::int)))
    -- genrer: union, tom lista = ingen gräns
    and (coalesce(jsonb_array_length(p_genres), 0) = 0
         or public._genre_key(p_track.genre) in (
              select jsonb_array_elements_text(p_genres)))
$$;

-- --- 3. räknaren: default null, inte false ---
create or replace function public.track_pool_selection_count(
  p_swedish boolean default null,
  p_bands   jsonb   default '[]'::jsonb,
  p_genres  jsonb   default '[]'::jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $function$
declare
  v_antal bigint;
begin
  perform public._rate_limit('pool_selection_count', 60, interval '1 minute');
  select count(*) into v_antal from public.track_pool tp
   where public._pool_match(tp, p_swedish, p_bands, p_genres);
  return v_antal;
end;
$function$;

grant execute on function public._pool_match(public.track_pool, boolean, jsonb, jsonb) to anon, authenticated;
grant execute on function public.track_pool_selection_count(boolean, jsonb, jsonb) to authenticated;

notify pgrst, 'reload schema';
