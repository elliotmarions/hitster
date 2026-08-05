-- =====================================================================
--  LÅTSNURRAN – Facit måste vara låten som spelas
--
--  BUGG: ibland spelades en helt annan låt än den facit visade. Orsaken satt
--  i titelvillkoret i poll_track_start (senast satt i 0057):
--
--      and (x.tn = v_clean or x.tn !~ v_junk_tn)
--
--  Andra grenen ställer INGET krav på titeln – bara att träffen inte ser ut
--  som en remix/karaoke. Alltså: vilken som helst av artistens låtar dög.
--  Sorteringen gjorde det värre i stället för bättre:
--
--      order by (case when tn = v_clean then 0 when tn like v_clean||'%' then 1
--                     else 2 end), length(tn)
--
--  Saknades rätt titel bland träffarna föll allt ner i hink 2, och där valdes
--  artistens KORTASTE låttitel. iTunes relevansordning kastades alltså bort
--  precis i det läge där den var det enda som fanns kvar att lita på.
--
--  Felet fanns i BÅDA potterna, inte bara den svenska. Mätning mot skarpa
--  iTunes-svar med exakt samma urvals- och sorteringslogik:
--    svensk pott (0047):   2 fel facit av 48 spelade rundor
--    utländsk pott (0043): 1 fel facit av 27 spelade rundor
--  Verifierade fel: "RID MIG SOM EN DALAHÄST/Rasmus Gozzi" spelade "Fake Taxi",
--  "Visor I Tiden/Carl-Einar Häckner" spelade "Äldre", "No Flockin'/Kodak
--  Black" spelade "Walk". Gemensamt: artisten stämmer, låten gör det inte –
--  precis vad ett artistfilter utan titelfilter ger.
--
--  ÅTGÄRD 1 – titeln måste matcha. Normaliserad jämförelse (gemener,
--  skiljetecken → mellanslag) och sedan lika ELLER prefix åt något håll på
--  HEL ordgräns. Prefix behövs åt båda hållen för legitima varianter:
--    "Heaven" → "Heaven (feat. Do)"        (iTunes har tillägget)
--    "Vincero (Album Version)" → "Vincero" (potten har tillägget)
--  Ordgränsen (' %') hindrar att "Walk" matchar "Walking in Memphis".
--
--  ÅTGÄRD 2 – artistvillkoret var en delsträngsjämförelse på artistens första
--  ord: `an like '%' || v_word || '%'`. För korta förled är det nästan
--  verkningslöst – "Ted" matchar "Wanted", "M." matchade i praktiken allt.
--  Nu jämförs normaliserat och på hel ordgräns i stället.
--
--  ÅTGÄRD 3 – limit 8 → 25 i iTunes-sökningen. Titelkravet gör urvalet
--  strängare, och rätt titel ligger inte alltid bland de åtta första när
--  artisten har många utgåvor. Fler kandidater kostar bara svarsstorlek och
--  motverkar att fixen i stället ger fler "hittade ingen spelbar låt".
--
--  KONSEKVENS: en låt vars rätta titel inte går att hitta spelas inte alls –
--  servern tar en annan låt (attempts_left = 3, oförändrat). Det är den
--  medvetna avvägningen från 0034, nu tillämpad på titeln också: hellre
--  hoppa över en låt än spela fel låt mot rätt facit.
--
--  Additiv + idempotent. Kör efter 0061.
-- =====================================================================

-- Normalisering för titel- och artistjämförelse: gemener, allt som inte är
-- bokstav/siffra blir mellanslag, dubbla mellanslag bort. Gör att "Don't
-- You Cry", "Dont You Cry" och "Don´t You Cry" jämförs lika. Efter detta
-- finns inga % eller _ kvar, så resultatet är säkert att använda i LIKE.
create or replace function public._norm_title(t text)
returns text language sql immutable as $$
  select trim(regexp_replace(
           regexp_replace(lower(coalesce(t, '')), '[^[:alnum:]]+', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

-- limit 8 → 25 (se ÅTGÄRD 3).
create or replace function public._itunes_search_url(p_term text)
returns text language sql immutable as $$
  select 'https://itunes.apple.com/search?media=music&entity=song&limit=25&country=SE&term='
         || public._urlencode(p_term)
$$;

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
  v_json   jsonb;
  v_track  public.track_pool;
  v_hit    jsonb;
  v_word   text;
  v_clean  text;
  v_ntitle text;
  v_req    bigint;
  v_junk_tn constant text :=
    '\m(remix|karaoke|cover|tribute|instrumental|acoustic|live|nightcore|made famous|originally performed|in the style of|sped|slowed|reverb|8.?bit|lullaby|rockabye|re.?recorded)\M';
  v_junk_cn constant text :=
    '\m(karaoke|tribute|made famous|originally performed|in the style of|nightcore|8.?bit|lullaby|rockabye)\M';
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

  v_hit := null;
  if coalesce(v_status, 0) = 200 and not coalesce(v_timed, false) then
    begin
      v_json := v_body::jsonb;
    exception when others then
      v_json := null;
    end;
    if v_json is not null then
      -- Artistens första ord, normaliserat. Faller tillbaka på hela namnet om
      -- artisten skulle sakna alfanumeriska tecken helt.
      v_word := coalesce(
        nullif(split_part(public._norm_title(coalesce(v_track.artist, '')), ' ', 1), ''),
        public._norm_title(coalesce(v_track.artist, '')));
      v_clean  := lower(public._clean_title(v_track.title));
      v_ntitle := public._norm_title(public._clean_title(v_track.title));

      select x.r into v_hit
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
        -- Titeln MÅSTE matcha: lika, eller prefix åt något håll på ordgräns.
        and v_ntitle <> ''
        and (x.ntn = v_ntitle
             or x.ntn like v_ntitle || ' %'
             or v_ntitle like x.ntn || ' %')
      order by
        (case when x.ntn = v_ntitle then 0
              when x.ntn like v_ntitle || ' %' then 1
              else 2 end),
        length(x.tn)
      limit 1;
    end if;
  end if;

  if v_hit is not null then
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
    where public._pool_match(tp, v_room.swedish_mode, v_room.year_bands, v_room.genres)
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
end $function$;

-- _norm_title anropas bara inifrån SECURITY DEFINER-funktioner och körs som
-- ägaren – ingen klient-grant behövs (jfr säkerhetsnoten i README om att
-- default privileges är återkallade).
grant execute on function public.poll_track_start(uuid) to authenticated;

notify pgrst, 'reload schema';
