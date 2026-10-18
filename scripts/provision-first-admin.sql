-- Run manually from a trusted SQL session ONLY after owner account registration
-- and email verification. Never expose this script as a client RPC.
begin;
do $$
declare v_user uuid; v_disabled boolean; v_changed integer;
begin
  select id into v_user from auth.users
    where lower(email)='bolaakram123@gmail.com' and email_confirmed_at is not null
      and not coalesce(is_anonymous,false)
      and (banned_until is null or banned_until < now());
  if v_user is null then
    raise exception 'Register and verify the owner app account before provisioning';
  end if;
  insert into private.account_access(user_id) values(v_user) on conflict do nothing;
  select disabled into v_disabled from private.account_access where user_id=v_user for update;
  if v_disabled then raise exception 'Owner account is disabled; investigate before granting access'; end if;
  update private.account_access set role='admin' where user_id=v_user and role<>'admin';
  get diagnostics v_changed = row_count;
  if v_changed=1 then
    insert into private.security_events(subject_id,action,details)
      values(v_user,'admin_provisioned','{"source":"owner-approved-bootstrap"}');
  end if;
end $$;
commit;
