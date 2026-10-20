-- Enabled server-owned Admin accounts: unlimited registered devices/parallel admissions.
-- Students: <=2 unrevoked devices and exactly the active_session_id admission.
-- No data backfill, Auth settings, public RPC signatures, table grants or policies change.
create or replace function private.is_active() returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists (
    select 1 from private.account_access a
    join private.session_access x on x.user_id=a.user_id
      and x.session_id=nullif(auth.jwt()->>'session_id','')::uuid
    join private.devices d on d.id=x.device_id and d.user_id=a.user_id
    join auth.sessions s on s.id=x.session_id and s.user_id=a.user_id
    join auth.users u on u.id=a.user_id
    where a.user_id=auth.uid() and not a.disabled
      and x.ended_at is null and d.revoked_at is null
      and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
      and (u.banned_until is null or u.banned_until<now())
      and (s.not_after is null or s.not_after>now())
      and (a.role='admin' or (a.role='student' and a.active_session_id=x.session_id
        and (select count(*) from private.devices owned
          where owned.user_id=a.user_id and owned.revoked_at is null)<=2))
  );
$$;

create or replace function private.get_access_context() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_sid uuid:=private.valid_session(); v_result jsonb;
begin
  if not exists(select 1 from private.session_access where session_id=v_sid and user_id=auth.uid()) then
    raise exception 'session_not_registered' using errcode='42501';
  end if;
  if not private.is_active() then raise exception 'session_replaced' using errcode='42501'; end if;
  -- Each admin receives its own device context; never follow another session's pointer.
  select jsonb_build_object('role',a.role,'device_id',x.device_id) into v_result
    from private.account_access a join private.session_access x on x.user_id=a.user_id
      and x.session_id=v_sid where a.user_id=auth.uid();
  return v_result;
end;
$$;

create or replace function private.register_device(p_device_token text,p_label text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_sid uuid:=private.valid_session();
  v_account private.account_access; v_device private.devices; v_metadata jsonb;
  v_device_count bigint; v_inserted integer;
begin
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$'
     or p_label is null or length(trim(p_label)) not between 1 and 80 then
    raise exception 'invalid_device' using errcode='22023';
  end if;
  insert into private.account_access(user_id) values(v_uid) on conflict do nothing;
  -- Serializes admissions/logout/role updates and the student device count for this user.
  select * into v_account from private.account_access where user_id=v_uid for update;
  if v_account.disabled then raise exception 'account_disabled' using errcode='42501'; end if;
  if exists(select 1 from private.session_access where session_id=v_sid and ended_at is not null) then
    raise exception 'session_replaced' using errcode='42501';
  end if;
  if v_account.role='student' then
    select count(*) into v_device_count from private.devices where user_id=v_uid and revoked_at is null;
    -- Former admins with excess registrations must explicitly remediate devices first.
    -- No arbitrary installation is auto-revoked or silently grandfathered into student access.
    if v_device_count>2 then raise exception 'device_limit' using errcode='42501'; end if;
    if v_account.active_session_id is not null and v_account.active_session_id<>v_sid
       and exists(select 1 from auth.sessions where id=v_account.active_session_id
         and user_id=v_uid and (not_after is null or not_after>now())) then
      raise exception 'active_session_exists' using errcode='42501';
    end if;
  end if;
  select * into v_device from private.devices
    where user_id=v_uid and token_hash=sha256(convert_to(p_device_token,'UTF8'));
  if found then
    if v_device.revoked_at is not null then raise exception 'device_revoked' using errcode='42501'; end if;
  else
    if v_account.role='student' and v_device_count>=2 then
      raise exception 'device_limit' using errcode='42501';
    end if;
    insert into private.devices(user_id,token_hash,label)
      values(v_uid,sha256(convert_to(p_device_token,'UTF8')),trim(p_label)) returning * into v_device;
  end if;
  if exists(select 1 from private.session_access where session_id=v_sid and device_id<>v_device.id) then
    raise exception 'session_device_mismatch' using errcode='42501';
  end if;
  if v_account.role='student' and v_account.active_session_id is not null
     and v_account.active_session_id<>v_sid then
    update private.session_access set ended_at=coalesce(ended_at,now())
      where session_id=v_account.active_session_id and user_id=v_uid and ended_at is null;
  end if;
  -- Editable metadata is used only for initial profile text, never authorization.
  select raw_user_meta_data into v_metadata from auth.users where id=v_uid;
  insert into public.profiles(id,name,phone,university)
    values(v_uid,left(coalesce(v_metadata->>'name',v_metadata->>'full_name',''),120),
      left(coalesce(v_metadata->>'phone',''),32),left(coalesce(v_metadata->>'university',''),160))
    on conflict do nothing;
  insert into private.session_access(session_id,user_id,device_id) values(v_sid,v_uid,v_device.id)
    on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_account.role='student' then
    update private.account_access set active_session_id=v_sid where user_id=v_uid;
  end if;
  -- The pointer is deliberately irrelevant for admins; audit actual new admission only.
  if v_inserted=1 then
    insert into private.security_events(actor_id,subject_id,action,details)
      values(v_uid,v_uid,'session_started',jsonb_build_object('device_id',v_device.id));
  end if;
  return private.get_access_context();
end;
$$;

-- Demotion is not allowed to preserve admin-era parallel admissions or a stale pointer.
-- End admissions, leave registered-device history intact, and require explicit remediation
-- if >2 unrevoked devices remain. The UPDATE row lock serializes with register/logout.
create function private.close_admin_admissions_on_demotion() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_ended integer;
begin
  if old.role='admin' and new.role='student' then
    new.active_session_id:=null;
    update private.session_access set ended_at=now() where user_id=old.user_id and ended_at is null;
    get diagnostics v_ended=row_count;
    insert into private.security_events(actor_id,subject_id,action,details)
      values(auth.uid(),old.user_id,'admin_admissions_ended_on_demotion',
        jsonb_build_object('ended_admissions',v_ended));
  end if;
  return new;
end;
$$;
revoke all on function private.close_admin_admissions_on_demotion() from public,anon,authenticated;
create trigger account_access_admin_demotion before update of role on private.account_access
  for each row execute function private.close_admin_admissions_on_demotion();

-- CREATE OR REPLACE preserves existing signatures/ACLs; restate the narrow client grants.
revoke all on function private.is_active(),private.get_access_context(),private.register_device(text,text)
  from public,anon,authenticated;
grant execute on function private.is_active(),private.get_access_context(),private.register_device(text,text)
  to authenticated;
-- Existing private.end_session (logout-before-registration migration) already ends only
-- auth.uid()/JWT session_id, clears only a matching student pointer, and audits once.
-- It is intentionally retained, including deviceless ended-session tombstones.
