-- Saved-for-later references only: never ownership, enrollment, payment or delivery.
-- Private is not an exposed Data API schema; invoker RPCs need narrow table grants.
-- Tombstones may reference UNKNOWN/removed IDs, so course_id intentionally has NO FK.
-- Uniform removals reveal no parent existence; false rows are retained against ABA.
create table private.course_bookmarks (
  owner_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  course_id uuid not null,
  saved boolean not null default false,
  revision integer not null default 0 check(revision>=0),
  primary key(owner_id,course_id)
);
create index course_bookmarks_course_idx on private.course_bookmarks(course_id);
alter table private.course_bookmarks enable row level security;
revoke all on private.course_bookmarks from public,anon,authenticated;
grant select on private.course_bookmarks to authenticated;
grant insert(owner_id,course_id),update(saved,revision) on private.course_bookmarks to authenticated;
create policy course_bookmarks_read_own on private.course_bookmarks for select to authenticated
  using ((select private.is_active()) and owner_id=(select auth.uid()));
create policy course_bookmarks_save_own on private.course_bookmarks for insert to authenticated
  with check ((select private.is_active()) and owner_id=(select auth.uid()) and (not saved or exists (
    select 1 from public.courses c where c.id=course_id and c.status='published' and c.deleted_at is null
  )));
create policy course_bookmarks_edit_own on private.course_bookmarks for update to authenticated
  using ((select private.is_active()) and owner_id=(select auth.uid()))
  with check ((select private.is_active()) and owner_id=(select auth.uid()) and (not saved or exists (
    select 1 from public.courses c where c.id=course_id and c.status='published' and c.deleted_at is null
  )));

create function private.advance_bookmark_revision() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if old.revision=2147483647 then raise exception 'bookmark_state_conflict' using errcode='42501'; end if;
  if new.revision<>old.revision+1 then raise exception 'bookmark_state_conflict' using errcode='42501'; end if;
  return new;
end;
$$;
revoke all on function private.advance_bookmark_revision() from public,anon,authenticated;
create trigger course_bookmarks_revision before update on private.course_bookmarks
  for each row execute function private.advance_bookmark_revision();

create function public.get_course_bookmark(p_course_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'bookmark_access_required' using errcode='42501'; end if;
  if p_course_id is null then raise exception 'invalid_bookmark_input' using errcode='22023'; end if;
  select jsonb_build_object('course_id',c.id,'saved',coalesce(b.saved,false),
    'revision',coalesce(b.revision,0)) into v_result from public.courses c
    left join private.course_bookmarks b on b.owner_id=auth.uid() and b.course_id=c.id
    where c.id=p_course_id and c.status='published' and c.deleted_at is null;
  return v_result;
end;
$$;

create function public.set_course_bookmark(p_course_id uuid,p_saved boolean,p_expected_revision integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_revision integer;
begin
  if not private.is_active() then raise exception 'bookmark_access_required' using errcode='42501'; end if;
  if p_course_id is null or p_saved is null or p_expected_revision is null or p_expected_revision<0 then
    raise exception 'invalid_bookmark_input' using errcode='22023';
  end if;
  if p_saved then
    if not exists(select 1 from public.courses c
      where c.id=p_course_id and c.status='published' and c.deleted_at is null) then
      raise exception 'bookmark_course_unavailable' using errcode='42501';
    end if;
  end if;
  -- Removal does not read the parent. Even unknown UUIDs receive retained false state.
  insert into private.course_bookmarks(owner_id,course_id) values(auth.uid(),p_course_id)
    on conflict(owner_id,course_id) do nothing;
  select revision into strict v_revision from private.course_bookmarks
    where owner_id=auth.uid() and course_id=p_course_id for update;
  if p_expected_revision<>v_revision or v_revision=2147483647 then
    raise exception 'bookmark_state_conflict' using errcode='42501';
  end if;
  update private.course_bookmarks set saved=p_saved,revision=v_revision+1
    where owner_id=auth.uid() and course_id=p_course_id;
  return jsonb_build_object('course_id',p_course_id,'saved',p_saved,'revision',v_revision+1);
end;
$$;

create function public.list_saved_courses(
  p_after_position integer default null,p_after_id uuid default null,p_limit integer default 20
) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'bookmark_access_required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50
     or ((p_after_position is null)<>(p_after_id is null)) or p_after_position<0 then
    raise exception 'invalid_bookmark_input' using errcode='22023';
  end if;
  with candidates as materialized (
    select c.id,c.position,jsonb_build_object('id',c.id,'title',c.title,'description',c.description,
      'instructor',c.instructor,'category',c.category,'level',c.level,
      'price_piasters',c.price_piasters,'position',c.position,'cover_path',c.cover_path) as item
    from private.course_bookmarks b join public.courses c on c.id=b.course_id
    where b.owner_id=auth.uid() and b.saved and c.status='published' and c.deleted_at is null
      and (p_after_position is null or (c.position,c.id)>(p_after_position,p_after_id))
    order by c.position,c.id limit p_limit+1
  ), page as materialized (
    select id,position,item from candidates order by position,id limit p_limit
  ) select jsonb_build_object(
    'items',coalesce((select jsonb_agg(item order by position,id) from page),'[]'::jsonb),
    'has_more',(select count(*)>p_limit from candidates),
    'next_cursor',case when (select count(*)>p_limit from candidates) then
      (select jsonb_build_object('position',position,'id',id) from page order by position desc,id desc limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;

revoke all on function public.get_course_bookmark(uuid),public.set_course_bookmark(uuid,boolean,integer),
  public.list_saved_courses(integer,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_course_bookmark(uuid),public.set_course_bookmark(uuid,boolean,integer),
  public.list_saved_courses(integer,uuid,integer) to authenticated;
