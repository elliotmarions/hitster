-- =====================================================================
--  HITSTER BINGO ONLINE – Auto-bedömning av svar + värd-override
--
--  Appen auto-bedömer varje låst svar mot facit på KLIENTEN (år exakt/±3/
--  årtionde samt tolerant textmatch för artist/titel). Auto-domen är
--  deterministisk → alla klienter räknar fram samma ✓/✗.
--
--  Det enda som behöver sparas/synkas är VÄRDENS override när hen inte håller
--  med auto-domen: en nullbar kolumn `override_correct` på round_answers.
--   - null  = använd auto-domen
--   - true  = värden markerar RÄTT
--   - false = värden markerar FEL
--
--  Additiv + idempotent. Kör efter 0008.
-- =====================================================================

alter table public.round_answers
  add column if not exists override_correct boolean;

-- --- RPC: värden överstyr (eller återställer) en bedömning -----------
create or replace function public.override_answer(
  p_room_id uuid,
  p_answer_id uuid,
  p_correct boolean
)
returns public.round_answers
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room public.rooms;
  v_ans  public.round_answers;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then raise exception 'Rummet finns inte'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'Bara värden kan rätta svar'; end if;

  update public.round_answers
    set override_correct = p_correct
    where id = p_answer_id and room_id = p_room_id
    returning * into v_ans;
  if v_ans.id is null then raise exception 'Svaret finns inte'; end if;
  return v_ans;
end;
$$;

grant execute on function public.override_answer(uuid, uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
