-- Hosted development version 20261018154932; metadata only, no private media identifiers.
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_active() and exists (
    select 1 from private.account_access where user_id=auth.uid() and role='admin' and not disabled
  );
$$;
revoke all on function private.is_admin() from public,anon,authenticated;
grant execute on function private.is_admin() to authenticated;

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null check(length(trim(title)) between 1 and 160),
  description text not null default '' check(length(description)<=10000),
  instructor text not null check(length(trim(instructor)) between 1 and 160),
  category text not null check(length(trim(category)) between 1 and 120),
  level text not null check(length(trim(level)) between 1 and 120),
  price_piasters integer not null default 0 check(price_piasters>=0),
  position integer not null default 0 check(position>=0),
  status text not null default 'draft' check(status in ('draft','published','archived')),
  deleted_at timestamptz,
  cover_path text check(cover_path is null), -- reserved until controlled uploads exist
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(deleted_at is null or status='archived')
);
create table public.course_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id),
  session_number integer not null check(session_number>0),
  title text not null check(length(trim(title)) between 1 and 160),
  description text not null default '' check(length(description)<=10000),
  price_piasters integer not null default 0 check(price_piasters>=0),
  position integer not null default 0 check(position>=0),
  status text not null default 'draft' check(status in ('draft','published','archived')),
  deleted_at timestamptz,
  is_free_preview boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id,session_number),
  check(deleted_at is null or status='archived')
);
create index courses_order_idx on public.courses(position,id);
create index course_sessions_order_idx on public.course_sessions(course_id,position,id);
create index courses_created_by_idx on public.courses(created_by);
create index course_sessions_created_by_idx on public.course_sessions(created_by);
alter table public.courses enable row level security;
alter table public.course_sessions enable row level security;
revoke all on public.courses,public.course_sessions from public,anon,authenticated;
grant select on public.courses,public.course_sessions to authenticated;
grant insert(title,description,instructor,category,level,price_piasters,position,status),
      update(title,description,instructor,category,level,price_piasters,position,status,deleted_at)
  on public.courses to authenticated;
grant insert(course_id,session_number,title,description,price_piasters,position,status,is_free_preview),
      update(session_number,title,description,price_piasters,position,status,deleted_at,is_free_preview)
  on public.course_sessions to authenticated;

create policy courses_read on public.courses for select to authenticated
using ((select private.is_admin()) or
       ((select private.is_active()) and status='published' and deleted_at is null));
create policy courses_create on public.courses for insert to authenticated
with check ((select private.is_admin()));
create policy courses_edit on public.courses for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));
create policy sessions_read on public.course_sessions for select to authenticated
using ((select private.is_admin()) or
       ((select private.is_active()) and status='published' and deleted_at is null and exists (
         select 1 from public.courses c where c.id=course_id and c.status='published' and c.deleted_at is null
       )));
create policy sessions_create on public.course_sessions for insert to authenticated
with check ((select private.is_admin()) and exists (
  select 1 from public.courses c where c.id=course_id and c.deleted_at is null
));
create policy sessions_edit on public.course_sessions for update to authenticated
using ((select private.is_admin()) and exists (
  select 1 from public.courses c where c.id=course_id and c.deleted_at is null
)) with check ((select private.is_admin()) and exists (
  select 1 from public.courses c where c.id=course_id and c.deleted_at is null
));

create function private.prepare_content_change() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op='UPDATE' then
    if new.deleted_at is not null then new.status := 'archived';
    elsif old.deleted_at is not null then new.status := 'draft';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.prepare_content_change() from public,anon,authenticated;

create function private.audit_content_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Defense in depth: never turn the audit trigger into a role-bypass endpoint.
  if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  insert into private.security_events(actor_id,subject_id,action,details)
    values(auth.uid(),auth.uid(),'content_' || lower(tg_op),
      jsonb_build_object('entity',tg_table_name,'id',new.id,'status',new.status,
                        'deleted',new.deleted_at is not null));
  return new;
end;
$$;
revoke all on function private.audit_content_change() from public,anon,authenticated;
create trigger courses_prepare before insert or update on public.courses
for each row execute function private.prepare_content_change();
create trigger sessions_prepare before insert or update on public.course_sessions
for each row execute function private.prepare_content_change();
create trigger courses_audit after insert or update on public.courses
for each row execute function private.audit_content_change();
create trigger sessions_audit after insert or update on public.course_sessions
for each row execute function private.audit_content_change();
