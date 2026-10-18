-- Logout must win even if an initial registration request arrives later.
-- A session ended before device registration has a tombstone but no device.
alter table private.session_access alter column device_id drop not null;
alter table private.session_access add constraint session_requires_device_or_ended
  check (device_id is not null or ended_at is not null);

create or replace function private.end_session() returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_sid uuid := private.valid_session(); v_changed integer;
begin
  insert into private.account_access(user_id) values(v_uid) on conflict do nothing;
  perform 1 from private.account_access where user_id=v_uid for update;
  insert into private.session_access(session_id,user_id,ended_at)
    values(v_sid,v_uid,now())
    on conflict(session_id) do update set ended_at=now()
    where private.session_access.user_id=v_uid and private.session_access.ended_at is null;
  get diagnostics v_changed = row_count;
  update private.account_access set active_session_id=null
    where user_id=v_uid and active_session_id=v_sid;
  if v_changed=1 then
    insert into private.security_events(actor_id,subject_id,action)
      values(v_uid,v_uid,'session_ended');
  end if;
end $$;
