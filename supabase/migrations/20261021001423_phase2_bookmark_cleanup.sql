-- Explicit own-account action only; no hidden identifiers or material/access grants.
-- Keep false tombstones and advance revisions to reject delayed pre-cleanup saves.
create function public.clear_unavailable_course_bookmarks() returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_cleared bigint;
begin
  if not private.is_active() then
    raise exception 'bookmark_access_required' using errcode='42501';
  end if;

  update private.course_bookmarks b set saved=false,revision=b.revision+1
  where b.owner_id=auth.uid() and b.saved=true and not exists (
    select 1 from public.courses c
    where c.id=b.course_id and c.status='published' and c.deleted_at is null
  );
  get diagnostics v_cleared=row_count;
  return jsonb_build_object('cleared_count',v_cleared::integer);
exception when numeric_value_out_of_range then
  -- The integer expression can overflow before the existing BEFORE UPDATE guard.
  -- This exception block rolls back the entire update, never a partial cleanup.
  raise exception 'bookmark_state_conflict' using errcode='42501';
end;
$$;
revoke all on function public.clear_unavailable_course_bookmarks() from public,anon,authenticated;
grant execute on function public.clear_unavailable_course_bookmarks() to authenticated;
