-- Hosted version 20261019015308. Retirement is irreversible, preventing cleanup/reattach races.
create table private.course_cover_assets (
  path text primary key,
  course_id uuid not null references public.courses(id),
  created_by uuid not null references auth.users(id),
  state text not null default 'uploading' check(state in ('uploading','attached','retired','cleaned')),
  created_at timestamptz not null default now(),
  check(path ~ ('^' || course_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$'))
);
create index course_cover_assets_course_idx on private.course_cover_assets(course_id,state,created_at);
create index course_cover_assets_creator_idx on private.course_cover_assets(created_by);
alter table private.course_cover_assets enable row level security;
revoke all on private.course_cover_assets from public,anon,authenticated;
alter table public.courses drop constraint courses_cover_path_check;
alter table public.courses add constraint courses_cover_path_check check(cover_path is null or
  cover_path ~ ('^' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$'));
-- No direct cover_path UPDATE grant: attachment goes through validated RPCs only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('course-covers','course-covers',false,3145728,array['image/png']);

create function private.cover_storage_allowed(p_path text,p_action text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.is_active() and exists (
   select 1 from private.course_cover_assets a join public.courses c on c.id=a.course_id
   where a.path=p_path and case p_action
     when 'insert' then private.is_admin() and a.created_by=auth.uid() and a.state='uploading'
       and a.created_at>now()-interval '1 hour' and c.deleted_at is null
     when 'read' then private.is_admin() or (a.state='attached' and c.cover_path=a.path
       and c.status='published' and c.deleted_at is null)
     when 'delete' then private.is_admin() and a.state in ('retired','cleaned')
       and not exists(select 1 from public.courses r where r.cover_path=a.path)
     else false end
 );
$$;
revoke all on function private.cover_storage_allowed(text,text) from public,anon,authenticated;
grant execute on function private.cover_storage_allowed(text,text) to authenticated;
create policy course_covers_read on storage.objects for select to authenticated
using(bucket_id='course-covers' and private.cover_storage_allowed(name,'read'));
create policy course_covers_insert on storage.objects for insert to authenticated
with check(bucket_id='course-covers' and private.cover_storage_allowed(name,'insert'));
create policy course_covers_delete on storage.objects for delete to authenticated
using(bucket_id='course-covers' and private.cover_storage_allowed(name,'delete'));

create function private.prepare_course_cover(p_course_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_path text;
begin
 if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
 perform 1 from public.courses where id=p_course_id and deleted_at is null for update;
 if not found then raise exception 'course_unavailable' using errcode='42501'; end if;
 if (select count(*) from private.course_cover_assets where course_id=p_course_id and state='uploading'
     and created_at>now()-interval '1 hour')>=5 then
   raise exception 'cover_upload_limit' using errcode='42501';
 end if;
 v_path:=p_course_id::text || '/' || gen_random_uuid()::text || '.png';
 insert into private.course_cover_assets(path,course_id,created_by) values(v_path,p_course_id,auth.uid());
 insert into private.security_events(actor_id,subject_id,action,details)
 values(auth.uid(),auth.uid(),'cover_upload_prepared',jsonb_build_object('course_id',p_course_id,'path',v_path));
 return jsonb_build_object('path',v_path);
end;
$$;

create function private.attach_course_cover(p_course_id uuid,p_path text,p_expected_previous_path text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_course public.courses; v_asset private.course_cover_assets;
begin
 if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
 select * into v_course from public.courses where id=p_course_id and deleted_at is null for update;
 if not found then raise exception 'course_unavailable' using errcode='42501'; end if;
 if p_path is not null and v_course.cover_path=p_path then return to_jsonb(v_course); end if;
 if v_course.cover_path is distinct from p_expected_previous_path then
   raise exception 'cover_changed' using errcode='40001';
 end if;
 if p_path is not null then
   select * into v_asset from private.course_cover_assets where path=p_path and course_id=p_course_id for update;
   if not found or v_asset.state<>'uploading' or v_asset.created_by<>auth.uid()
     or v_asset.created_at<=now()-interval '1 hour' then
     raise exception 'cover_unavailable' using errcode='42501';
   end if;
   if not exists(select 1 from storage.objects where bucket_id='course-covers' and name=p_path
     and metadata->>'mimetype'='image/png' and case when metadata->>'size' ~ '^[0-9]+$'
       then (metadata->>'size')::numeric between 1 and 3145728 else false end) then
     raise exception 'cover_upload_invalid' using errcode='42501';
   end if;
 end if;
 if v_course.cover_path is not null then
   update private.course_cover_assets set state='retired' where path=v_course.cover_path and state='attached';
 end if;
 if p_path is not null then update private.course_cover_assets set state='attached' where path=p_path; end if;
 update public.courses set cover_path=p_path where id=p_course_id returning * into v_course;
 return to_jsonb(v_course);
end;
$$;

create function private.abandon_course_cover(p_course_id uuid,p_path text) returns void
language plpgsql security definer set search_path='' as $$
declare v_changed integer;
begin
 if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
 perform 1 from public.courses where id=p_course_id for update;
 update private.course_cover_assets set state='retired' where path=p_path and course_id=p_course_id and state='uploading';
 get diagnostics v_changed=row_count;
 if v_changed=1 then insert into private.security_events(actor_id,subject_id,action,details)
 values(auth.uid(),auth.uid(),'cover_upload_abandoned',jsonb_build_object('course_id',p_course_id,'path',p_path)); end if;
 -- An attached object can never be retired through abandon, including after a lost response.
end;
$$;

create function private.list_retired_course_covers(p_course_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_paths jsonb;
begin
 if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
 perform 1 from public.courses where id=p_course_id for update;
 with stale as (
   select path from private.course_cover_assets where course_id=p_course_id
     and state='uploading' and created_at<=now()-interval '1 hour' order by created_at,path limit 20 for update
 ), changed as (
   update private.course_cover_assets a set state='retired' from stale s where a.path=s.path returning a.path
 ) insert into private.security_events(actor_id,subject_id,action,details)
 select auth.uid(),auth.uid(),'cover_upload_expired',jsonb_build_object('course_id',p_course_id,'path',path) from changed;
 select coalesce(jsonb_agg(path),'[]'::jsonb) into v_paths from (
   select a.path from private.course_cover_assets a where a.course_id=p_course_id and
   (a.state='retired' or (a.state='cleaned' and exists(select 1 from storage.objects o
      where o.bucket_id='course-covers' and o.name=a.path))) order by a.created_at,a.path limit 20
 ) q;
 return v_paths;
end;
$$;

create function private.finish_course_cover_cleanup(p_course_id uuid,p_path text) returns void
language plpgsql security definer set search_path='' as $$
declare v_changed integer;
begin
 if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
 perform 1 from public.courses where id=p_course_id for update;
 if exists(select 1 from storage.objects where bucket_id='course-covers' and name=p_path) then
   raise exception 'cover_cleanup_pending' using errcode='42501';
 end if;
 update private.course_cover_assets set state='cleaned' where course_id=p_course_id and path=p_path and state='retired';
 get diagnostics v_changed=row_count;
 if v_changed=1 then insert into private.security_events(actor_id,subject_id,action,details)
 values(auth.uid(),auth.uid(),'cover_cleanup_finished',jsonb_build_object('course_id',p_course_id,'path',p_path)); end if;
 -- Retain a tombstone: retired/cleaned paths can never be uploaded or attached again.
end;
$$;

create function public.prepare_course_cover(p_course_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.prepare_course_cover(p_course_id); $$;
create function public.attach_course_cover(p_course_id uuid,p_path text,p_expected_previous_path text) returns jsonb
language sql security invoker set search_path='' as $$ select private.attach_course_cover(p_course_id,p_path,p_expected_previous_path); $$;
create function public.abandon_course_cover(p_course_id uuid,p_path text) returns void
language sql security invoker set search_path='' as $$ select private.abandon_course_cover(p_course_id,p_path); $$;
create function public.list_retired_course_covers(p_course_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.list_retired_course_covers(p_course_id); $$;
create function public.finish_course_cover_cleanup(p_course_id uuid,p_path text) returns void
language sql security invoker set search_path='' as $$ select private.finish_course_cover_cleanup(p_course_id,p_path); $$;
do $$ declare v_sig text; begin
 foreach v_sig in array array['prepare_course_cover(uuid)','attach_course_cover(uuid,text,text)',
   'abandon_course_cover(uuid,text)','list_retired_course_covers(uuid)','finish_course_cover_cleanup(uuid,text)'] loop
   execute 'revoke all on function private.' || v_sig || ' from public,anon,authenticated';
   execute 'revoke all on function public.' || v_sig || ' from public,anon,authenticated';
   execute 'grant execute on function private.' || v_sig || ' to authenticated';
   execute 'grant execute on function public.' || v_sig || ' to authenticated';
 end loop;
end $$;
