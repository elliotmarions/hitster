-- ====================================================================
--  0055  Räknare för den kombinerade pottvalen
-- --------------------------------------------------------------------
--  Svenskt läge går nu att kombinera med åldersspann och genre i lobbyn.
--  Servern klarade det redan – start_random_track AND:ar sv, årsfönster
--  och genre som tre oberoende villkor – men UI:t behandlade dem som ett
--  enda val.
--
--  Med kombinationer blir potten inte längre självklar: "Svenska" är 282
--  låtar och "20–29 år" tusentals, men skärningen dem emellan är 90. Och
--  vissa kombinationer är nästan tomma. Värden måste kunna se antalet
--  INNAN spelet startar, annars upptäcks en tom pott först när snurren
--  går i taket.
--
--  Därför den här: samma filter som start_random_track, men bara count.
--  Potten förblir oläsbar för klienter – bara siffran lämnar servern.
--
--  Egen rate limit-hink (60/min, mot pool_counts 20/min) eftersom lobbyn
--  räknar om vid varje klick i kategorilistan.
--
--  Idempotent. Kör efter 0054.
-- ====================================================================

create or replace function public.track_pool_selection_count(
  p_swedish  boolean default false,
  p_year_min int     default null,
  p_year_max int     default null,
  p_genre    text    default null
)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_antal bigint;
begin
  perform public._rate_limit('pool_selection_count', 60, interval '1 minute');

  -- Exakt samma villkor som start_random_track. Ändras filtret där måste
  -- det ändras här, annars visar lobbyn en siffra spelet inte håller.
  select count(*) into v_antal
    from public.track_pool tp
   where tp.sv = coalesce(p_swedish, false)
     and (p_year_min is null or tp.year >= p_year_min)
     and (p_year_max is null or tp.year <= p_year_max)
     and (p_genre is null or public._genre_key(tp.genre) = p_genre);

  return v_antal;
end
$function$;

grant execute on function public.track_pool_selection_count(boolean, int, int, text) to authenticated;

notify pgrst, 'reload schema';
