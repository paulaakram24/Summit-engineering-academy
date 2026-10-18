-- SEA Phase 1. No client-controlled roles or public content buckets.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '' check (length(name) <= 120),
  phone text not null default '' check (length(phone) <= 32),
  university text not null default '' check (length(university) <= 160),
  created_at timestamptz not null default now()
);
create table private.account_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student' check (role in ('student','admin')),
  disabled boolean not null default false,
  active_session_id uuid,
  created_at timestamptz not null default now()
);
create table private.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references private.account_access(user_id) on delete cascade,
  token_hash bytea not null,
  label text not null check (length(label) between 1 and 80),
  registered_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(user_id, token_hash)
);
create table private.session_access (
  session_id uuid primary key,
  user_id uuid not null references private.account_access(user_id) on delete cascade,
  device_id uuid not null references private.devices(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index session_access_user_idx on private.session_access(user_id);
create index session_access_device_idx on private.session_access(device_id);
create table private.security_events (
  id bigint generated always as identity primary key,
  actor_id uuid,
  subject_id uuid,
  action text not null,
  occurred_at timestamptz not null default now(),
  details jsonb not null default '{}'
);
alter table public.profiles enable row level security;
alter table private.account_access enable row level security;
alter table private.devices enable row level security;
alter table private.session_access enable row level security;
alter table private.security_events enable row level security;
revoke all on public.profiles from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant update(name,phone,university) on public.profiles to authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

-- Privileged helpers are kept outside the exposed API schema. Every client
-- callable helper verifies auth.uid(), server session, and account state.
create function private.valid_session() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_sid uuid;
begin
  if v_uid is null then raise exception 'authentication_required' using errcode='42501'; end if;
  v_sid := nullif(auth.jwt()->>'session_id','')::uuid;
  if v_sid is null or not exists (
    select 1 from auth.sessions s join auth.users u on u.id=s.user_id
    where s.id=v_sid and s.user_id=v_uid and u.email_confirmed_at is not null
      and (u.banned_until is null or u.banned_until < now())
      and (s.not_after is null or s.not_after > now())
      and not coalesce(u.is_anonymous,false)
  ) then raise exception 'unverified_or_invalid_session' using errcode='42501'; end if;
  return v_sid;
end $$;

create function private.is_active() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from private.account_access a
    join private.session_access x on x.session_id=a.active_session_id and x.user_id=a.user_id
    join private.devices d on d.id=x.device_id and d.user_id=a.user_id
    join auth.sessions s on s.id=x.session_id and s.user_id=a.user_id
    join auth.users u on u.id=a.user_id
    where a.user_id=auth.uid() and not a.disabled
      and a.active_session_id=nullif(auth.jwt()->>'session_id','')::uuid
      and x.ended_at is null and d.revoked_at is null
      and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
      and (u.banned_until is null or u.banned_until < now())
      and (s.not_after is null or s.not_after > now())
  );
$$;

create function private.get_access_context() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_sid uuid := private.valid_session(); v_result jsonb;
begin
  if not exists (select 1 from private.session_access where session_id=v_sid and user_id=auth.uid()) then
    raise exception 'session_not_registered' using errcode='42501';
  end if;
  if not private.is_active() then raise exception 'session_replaced' using errcode='42501'; end if;
  select jsonb_build_object('role',a.role,'device_id',x.device_id) into v_result
    from private.account_access a join private.session_access x on x.session_id=a.active_session_id
    where a.user_id=auth.uid();
  return v_result;
end $$;

create function private.register_device(p_device_token text, p_label text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_sid uuid := private.valid_session();
  v_account private.account_access; v_device private.devices; v_metadata jsonb;
begin
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$'
     or p_label is null or length(trim(p_label)) not between 1 and 80 then
    raise exception 'invalid_device' using errcode='22023';
  end if;
  insert into private.account_access(user_id) values(v_uid) on conflict do nothing;
  -- One row lock serializes device counts, concurrent sign-ins and logout.
  select * into v_account from private.account_access where user_id=v_uid for update;
  if v_account.disabled then raise exception 'account_disabled' using errcode='42501'; end if;
  if exists(select 1 from private.session_access where session_id=v_sid and ended_at is not null) then
    raise exception 'session_replaced' using errcode='42501';
  end if;
  if v_account.active_session_id is not null and v_account.active_session_id <> v_sid
     and exists(select 1 from auth.sessions where id=v_account.active_session_id
                and user_id=v_uid and (not_after is null or not_after > now())) then
    raise exception 'active_session_exists' using errcode='42501';
  end if;
  select * into v_device from private.devices
    where user_id=v_uid and token_hash=sha256(convert_to(p_device_token,'UTF8'));
  if found then
    if v_device.revoked_at is not null then raise exception 'device_revoked' using errcode='42501'; end if;
  else
    if (select count(*) from private.devices where user_id=v_uid and revoked_at is null) >= 2 then
      raise exception 'device_limit' using errcode='42501';
    end if;
    insert into private.devices(user_id,token_hash,label)
      values(v_uid,sha256(convert_to(p_device_token,'UTF8')),trim(p_label)) returning * into v_device;
  end if;
  if exists(select 1 from private.session_access where session_id=v_sid and device_id<>v_device.id) then
    raise exception 'session_device_mismatch' using errcode='42501';
  end if;
  if v_account.active_session_id is not null and v_account.active_session_id<>v_sid then
    update private.session_access set ended_at=now() where session_id=v_account.active_session_id;
  end if;
  select raw_user_meta_data into v_metadata from auth.users where id=v_uid;
  insert into public.profiles(id,name,phone,university)
    values(v_uid,left(coalesce(v_metadata->>'name',v_metadata->>'full_name',''),120),
      left(coalesce(v_metadata->>'phone',''),32),left(coalesce(v_metadata->>'university',''),160))
    on conflict do nothing;
  insert into private.session_access(session_id,user_id,device_id) values(v_sid,v_uid,v_device.id)
    on conflict do nothing;
  update private.account_access set active_session_id=v_sid where user_id=v_uid;
  if v_account.active_session_id is distinct from v_sid then
    insert into private.security_events(actor_id,subject_id,action,details)
      values(v_uid,v_uid,'session_started',jsonb_build_object('device_id',v_device.id));
  end if;
  return private.get_access_context();
end $$;

create function private.end_session() returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_sid uuid := private.valid_session();
begin
  perform 1 from private.account_access where user_id=v_uid for update;
  update private.session_access set ended_at=coalesce(ended_at,now()) where session_id=v_sid and user_id=v_uid;
  update private.account_access set active_session_id=null where user_id=v_uid and active_session_id=v_sid;
  insert into private.security_events(actor_id,subject_id,action) values(v_uid,v_uid,'session_ended');
end $$;

create function public.register_device(p_device_token text,p_label text) returns jsonb
language sql security invoker set search_path='' as $$ select private.register_device(p_device_token,p_label); $$;
create function public.get_access_context() returns jsonb
language sql stable security invoker set search_path='' as $$ select private.get_access_context(); $$;
create function public.end_session() returns void
language sql security invoker set search_path='' as $$ select private.end_session(); $$;

revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_active(), private.register_device(text,text), private.get_access_context(), private.end_session() to authenticated;
revoke all on function public.register_device(text,text), public.get_access_context(), public.end_session() from public,anon;
grant execute on function public.register_device(text,text), public.get_access_context(), public.end_session() to authenticated;

create policy profiles_read_own on public.profiles for select to authenticated
  using(id=(select auth.uid()) and (select private.is_active()));
create policy profiles_update_own on public.profiles for update to authenticated
  using(id=(select auth.uid()) and (select private.is_active()))
  with check(id=(select auth.uid()) and (select private.is_active()));

-- Phase 1 creates closed buckets only. Upload/download policies arrive with
-- their owning feature, not broad 'authenticated' access.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
  ('course-materials','course-materials',false,52428800,array['application/pdf','image/jpeg','image/png']),
  ('payment-receipts','payment-receipts',false,10485760,array['image/jpeg','image/png','application/pdf']),
  ('assignment-submissions','assignment-submissions',false,52428800,array['application/pdf','image/jpeg','image/png']);
