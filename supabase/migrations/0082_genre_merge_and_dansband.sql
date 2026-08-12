-- =====================================================================
--  LÅTSNURRAN – genrerna görs om: R&B in i hiphopen, Dance blir EDM,
--  och Dansband/Schlager blir en egen genre
--
--  TRE ÄNDRINGAR, alla i _genre_key() och alltså i vad ETT chip betyder:
--
--   1. R&B slås ihop med Hiphop. R&B-chipet var pottens minsta med god
--      marginal (347 låtar mot hiphopens 1262, och bara 22 svenska) – ett
--      urval som tog slut på en kväll och som dessutom delar artister med
--      hiphopen i praktiken. Nyckeln 'rnb' finns inte längre; R&B-raderna
--      pekar nu på 'hiphop'.
--
--   2. 'dance' byter namn till 'edm'. Bara namnet – exakt samma rader
--      (Dance, Electro, Disco, House, Techno, Elektroniskt).
--
--   3. Ny nyckel 'dansband' för rågenrerna 'Dansband' och 'Schlager'.
--      Strömningstjänsternas genrer känner inte till dansband alls, så
--      etiketten sätts av oss – på samma sätt som 0079 satte Pop/Rock/R&B
--      på före-1970-låtarna. Låtarna kommer i 0083; här läggs nyckeln och
--      de artister som REDAN ligger i potten flyttas över.
--
--  GAMLA RUM. rooms.genres är en jsonb-lista med nycklar, och rum som står
--  och väntar har 'rnb' eller 'dance' i sig. Två saker gör att de inte
--  tappar sitt val: raderna skrivs om här, och _pool_match() översätter
--  gamla nycklar via _genre_alias() – en delad länk som klarar ett rum som
--  skapades innan den här migrationen men startas efter.
--
--  OBS (0073): _genre_key ingår i indexet track_pool_genre_idx. Att ändra
--  en IMMUTABLE funktion bygger inte om indexet, så det reindexeras här –
--  utan det hade raderna legat kvar under sina gamla nycklar i indexet.
--
--  VILKA ARTISTER SOM FLYTTAR (punkt 3): dansbanden och den klassiska
--  schlagern. Melodifestivalen-popen stannar i Pop – Carola, Måns
--  Zelmerlöw, Sanna Nielsen, Martin Stenmarck och Andreas Johnson är pop
--  i allt utom ursprunget, och en låt kan bara ligga i EN genre. Flyttet
--  gäller alltså Vikingarna, Lasse Stefanz, Arvingarna, Barbados, Wizex,
--  Kikki Danielsson, Scotts, Larz-Kristerz, Sannex, Christer Sjögren,
--  Lotta Engberg, Torgny Melins och deras likar.
--
--  Additiv + idempotent. Kör efter 0081.
-- =====================================================================

-- --- 1. nycklarna -----------------------------------------------------
create or replace function public._genre_key(p_genre text)
returns text language sql immutable as $function$
  select case
    when p_genre is null then null
    -- Deezer
    when p_genre = 'Pop' then 'pop'
    when p_genre in ('Rock', 'Alternativmusik', 'Metal') then 'rock'
    when p_genre = 'Rap/Hip Hop' then 'hiphop'
    when p_genre in ('Dance', 'Electro', 'Disco') then 'edm'
    -- R&B ligger numera under hiphop (se huvudet)
    when p_genre in ('R&B', 'Soul & Funk') then 'hiphop'
    -- iTunes
    when p_genre in ('Hiphop/Rap', 'Hiphop', 'Rap', 'Alternative Rap',
                     'Gangsta Rap', 'Undergroundrap', 'Hardcore Rap',
                     'Hip-Hop/Rap') then 'hiphop'
    when p_genre in ('Alternativt', 'Alternative', 'Hårdrock', 'Hard Rock',
                     'Punk') then 'rock'
    when p_genre in ('Elektroniskt', 'Electronic', 'House', 'Techno') then 'edm'
    when p_genre in ('R&B/Soul', 'Soul') then 'hiphop'
    -- vår egen etikett: strömningstjänsterna har ingen
    when p_genre in ('Dansband', 'Schlager') then 'dansband'
    else null
  end
$function$;

reindex index public.track_pool_genre_idx;

-- --- 2. gamla nycklar i rum som redan finns ---------------------------
--  Ett rum kan ha skapats före den här migrationen och startas efter den.
create or replace function public._genre_alias(p_key text)
returns text language sql immutable set search_path = public as $function$
  select case p_key
    when 'rnb' then 'hiphop'
    when 'dance' then 'edm'
    else p_key
  end
$function$;

-- Kroppen är oförändrad sedan 0057/0058 så när som på aliaset.
create or replace function public._pool_match(
  p_track public.track_pool, p_swedish boolean, p_bands jsonb, p_genres jsonb)
returns boolean
language sql
immutable
set search_path = public
as $function$
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
              select public._genre_alias(g)
                from jsonb_array_elements_text(p_genres) g))
$function$;

-- Och skriv om de rum som står och väntar, så lobbyns chip visar samma
-- sak som filtret faktiskt gör.
update public.rooms
   set genres = (
     select coalesce(jsonb_agg(distinct public._genre_alias(g)), '[]'::jsonb)
       from jsonb_array_elements_text(genres) g)
 where genres::text ~ '"(rnb|dance)"';

-- --- 3. genreräknaren tar med svenska rader ---------------------------
--  Räknaren var byggd för de utländska potterna och filtrerade bort allt
--  svenskt. Dansband/Schlager är nästan uteslutande svenskt och hade
--  därför räknats som noll. (Lobbyn frågar numera
--  track_pool_selection_count för sitt tal; den här är kvar för översikt.)
create or replace function public.track_pool_genre_counts()
returns table(genre text, antal bigint)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public._rate_limit('pool_counts', 20, interval '1 minute');
  return query
    select public._genre_key(tp.genre) as genre, count(*) as antal
      from public.track_pool tp
     where public._genre_key(tp.genre) is not null
     group by 1
     order by 2 desc;
end
$function$;

grant execute on function public.track_pool_genre_counts() to authenticated;

-- --- 4. artisterna som flyttar till dansband/schlager -----------------
--  Exakt artistnamn, eftersom potten skriver artisten som källan gjorde.
--  Raderna behåller allt annat; bara etiketten byts.
--
--  BARA SVENSKA RADER, av två skäl. Dels heter flera av dansbanden samma
--  sak som utländska artister – "Drifters", "Date", "Black Jack" – och
--  potten har The Drifters med "Under the Boardwalk". Dels ligger 71 låtar
--  MEDVETET i båda potterna sedan 0039 (svenska artister som hör hemma i
--  världspotten också, t.ex. Kikki Danielssons "Bra vibrationer"); de
--  systerraderna ska fortsätta vara pop i den utländska potten.
update public.track_pool
   set genre = 'Dansband'
 where sv
   and artist in (
   'Vikingarna', 'Lasse Stefanz', 'Streaplers', 'Sten & Stanley', 'Thorleifs',
   'Wizex', 'Arvingarna', 'Larz-Kristerz', 'Matz Bladhs', 'Flamingokvintetten',
   'Curt Haagers', 'Grönwalls', 'Ingmar Nordströms', 'Scotts', 'Sannex',
   'Titanix', 'Tommys', 'Barbados', 'Donnez', 'Perikles', 'Roland Cedermark',
   'Jontez', 'Lotta Engbergs', 'Christer Sjögren', 'Torgny Melins', 'Fernandoz',
   'Kenneth & The Knutters', 'Rune Rudbergs', 'Highlights', 'Bhonus', 'Zekes',
   'Nickes', 'Kikki Danielsson', 'Elisa Lindström', 'Casanovas', 'Drifters',
   'Date', 'Jive', 'Kellys', 'Berth Idoffs', 'Lotta Engberg', 'Sound Express',
   'Anders Engbergs', 'Junix', 'Black Jack')
   and coalesce(public._genre_key(genre), '') <> 'dansband';
