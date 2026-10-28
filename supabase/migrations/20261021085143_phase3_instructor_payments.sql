-- Setup only. No instructions, paused-request transition, orders, grants or delivery.
-- Course display text/created_by NEVER determines the instructor or receiving number.
create table private.instructor_payment_profiles (
  instructor_id uuid primary key references auth.users(id) on delete restrict,
  recipient_name text not null check(recipient_name=btrim(recipient_name,' ')
    and char_length(recipient_name) between 1 and 160
    and recipient_name !~ ('['||chr(1)||'-'||chr(31)||chr(127)||']')),
  phone_number text not null check(phone_number collate "C" ~ '^\+?[0-9]{7,15}$'),
  method_configuration text not null check(method_configuration in ('instapay_only','instapay_and_vodafone_cash')),
  revision integer not null default 1 check(revision>=1)
);
create table private.instructor_payment_profile_history (
  instructor_id uuid not null references private.instructor_payment_profiles(instructor_id) on delete restrict,
  revision integer not null check(revision>=1),
  recipient_name text not null,
  phone_number text not null,
  method_configuration text not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  primary key(instructor_id,revision)
);
create index instructor_payment_profile_history_actor_idx on private.instructor_payment_profile_history(actor_id);
create table private.course_payment_instructors (
  course_id uuid primary key references public.courses(id) on delete restrict,
  instructor_id uuid not null references private.instructor_payment_profiles(instructor_id) on delete restrict,
  revision integer not null default 1 check(revision>=1)
);
create index course_payment_instructors_instructor_idx on private.course_payment_instructors(instructor_id);
create table private.course_payment_instructor_history (
  course_id uuid not null references private.course_payment_instructors(course_id) on delete restrict,
  revision integer not null check(revision>=1),
  instructor_id uuid not null references private.instructor_payment_profiles(instructor_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  primary key(course_id,revision)
);
create index course_payment_instructor_history_instructor_idx on private.course_payment_instructor_history(instructor_id);
create index course_payment_instructor_history_actor_idx on private.course_payment_instructor_history(actor_id);
alter table private.instructor_payment_profiles enable row level security;
alter table private.instructor_payment_profile_history enable row level security;
alter table private.course_payment_instructors enable row level security;
alter table private.course_payment_instructor_history enable row level security;
revoke all on private.instructor_payment_profiles,private.instructor_payment_profile_history,
  private.course_payment_instructors,private.course_payment_instructor_history from public,anon,authenticated,service_role;
-- No direct client table grants, including histories. These policies are defense in depth.
create policy instructor_payment_profiles_own on private.instructor_payment_profiles for select to authenticated
  using ((select private.is_admin()) and instructor_id=(select auth.uid()));
create policy course_payment_instructors_admin on private.course_payment_instructors for select to authenticated
  using ((select private.is_admin()) and exists(select 1 from public.courses c
    where c.id=course_id and c.deleted_at is null));

create function private.reject_payment_setup_history_change() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  raise exception 'payment_setup_state_conflict' using errcode='42501';
end;
$$;
create trigger instructor_payment_profile_history_immutable before update or delete on private.instructor_payment_profile_history
  for each row execute function private.reject_payment_setup_history_change();
create trigger course_payment_instructor_history_immutable before update or delete on private.course_payment_instructor_history
  for each row execute function private.reject_payment_setup_history_change();

-- Eligibility does NOT require the payee to be currently online/admitted on a device.
-- Caller authorization is separate. This internal lookup has no client EXECUTE grant.
create function private.payment_instructor_eligible(p_instructor_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists(select 1 from private.account_access a join auth.users u on u.id=a.user_id
    join private.instructor_payment_profiles p on p.instructor_id=a.user_id
    where a.user_id=p_instructor_id and a.role='admin' and not a.disabled
      and u.deleted_at is null and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
      and (u.banned_until is null or u.banned_until<=now()));
$$;
create function private.read_payment_setup(p_action text,p_course_id uuid,p_after_id uuid,p_limit integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_admin() then raise exception 'payment_setup_access_required' using errcode='42501'; end if;
  if p_action='profile' then
    select jsonb_build_object('instructor_id',p.instructor_id,'recipient_name',p.recipient_name,
      'phone_number',p.phone_number,'method_configuration',p.method_configuration,'revision',p.revision)
    into v_result from private.instructor_payment_profiles p where p.instructor_id=auth.uid();
  elsif p_action='course' then
    if p_course_id is null then raise exception 'invalid_payment_setup_input' using errcode='22023'; end if;
    if not exists(select 1 from public.courses c where c.id=p_course_id and c.deleted_at is null) then
      raise exception 'payment_setup_target_unavailable' using errcode='42501';
    end if;
    -- Configuration identity only, not instructions or proof of current payee eligibility.
    select jsonb_build_object('course_id',b.course_id,'instructor_id',b.instructor_id,'revision',b.revision)
    into v_result from private.course_payment_instructors b where b.course_id=p_course_id;
  elsif p_action='directory' then
    if p_limit is null or p_limit<1 or p_limit>50 then
      raise exception 'invalid_payment_setup_input' using errcode='22023';
    end if;
    with candidates as materialized (
      select p.instructor_id,btrim(d.name,' ') as display_name
      from private.instructor_payment_profiles p join public.profiles d on d.id=p.instructor_id
      where private.payment_instructor_eligible(p.instructor_id)
        and char_length(btrim(d.name,' ')) between 1 and 120
        and (p_after_id is null or p.instructor_id>p_after_id)
      order by p.instructor_id limit p_limit+1
    ), page as materialized (select * from candidates order by instructor_id limit p_limit)
    select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('instructor_id',instructor_id,
      'display_name',display_name) order by instructor_id) from page),'[]'::jsonb),
      'has_more',(select count(*)>p_limit from candidates),
      'next_cursor',case when (select count(*)>p_limit from candidates) then
        (select jsonb_build_object('instructor_id',instructor_id) from page order by instructor_id desc limit 1) else null end)
    into v_result;
  else raise exception 'invalid_payment_setup_input' using errcode='22023';
  end if;
  return v_result;
end;
$$;
create function private.save_my_instructor_payment_profile(
  p_recipient_name text,p_phone_number text,p_method_configuration text,p_expected_revision integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_name text:=btrim(p_recipient_name,' '); v_revision integer; v_row private.instructor_payment_profiles;
begin
  if not private.is_admin() then raise exception 'payment_setup_access_required' using errcode='42501'; end if;
  perform 1 from private.account_access where user_id=v_uid for update;
  if not private.is_admin() then raise exception 'payment_setup_access_required' using errcode='42501'; end if;
  if v_name is null or char_length(v_name) not between 1 and 160
     or v_name ~ ('['||chr(1)||'-'||chr(31)||chr(127)||']')
     or p_phone_number is null or p_phone_number collate "C" !~ '^\+?[0-9]{7,15}$'
     or p_method_configuration is null or p_method_configuration not in ('instapay_only','instapay_and_vodafone_cash')
     or p_expected_revision is null or p_expected_revision<0 then
    raise exception 'invalid_payment_setup_input' using errcode='22023';
  end if;
  select revision into v_revision from private.instructor_payment_profiles where instructor_id=v_uid for update;
  v_revision:=coalesce(v_revision,0);
  if v_revision<>p_expected_revision or v_revision=2147483647 then
    raise exception 'payment_setup_state_conflict' using errcode='42501';
  end if;
  insert into private.instructor_payment_profiles(instructor_id,recipient_name,phone_number,method_configuration,revision)
    values(v_uid,v_name,p_phone_number,p_method_configuration,v_revision+1)
    on conflict(instructor_id) do update set recipient_name=excluded.recipient_name,phone_number=excluded.phone_number,
      method_configuration=excluded.method_configuration,revision=excluded.revision returning * into v_row;
  insert into private.instructor_payment_profile_history(instructor_id,revision,recipient_name,phone_number,method_configuration,actor_id)
    values(v_uid,v_row.revision,v_row.recipient_name,v_row.phone_number,v_row.method_configuration,v_uid);
  insert into private.security_events(actor_id,subject_id,action,details)
    values(v_uid,v_uid,'instructor_payment_profile_saved',jsonb_build_object('instructor_id',v_uid,'revision',v_row.revision));
  return jsonb_build_object('instructor_id',v_uid,'recipient_name',v_row.recipient_name,'phone_number',v_row.phone_number,
    'method_configuration',v_row.method_configuration,'revision',v_row.revision);
end;
$$;
create function private.set_course_payment_instructor(p_course_id uuid,p_instructor_id uuid,p_expected_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_revision integer;
begin
  if not private.is_admin() then raise exception 'payment_setup_access_required' using errcode='42501'; end if;
  -- Both account rows in UUID order, BEFORE course/profile/binding locks. Profile saves
  -- take their own account first too. Recheck actor after waiting, never trust JWT metadata.
  perform 1 from private.account_access where user_id in(v_uid,p_instructor_id) order by user_id for update;
  if not private.is_admin() then raise exception 'payment_setup_access_required' using errcode='42501'; end if;
  if p_course_id is null or p_expected_revision is null or p_expected_revision<0 then
    raise exception 'invalid_payment_setup_input' using errcode='22023';
  end if;
  if not private.payment_instructor_eligible(p_instructor_id) then
    raise exception 'payment_setup_target_unavailable' using errcode='42501';
  end if;
  -- Exclusive parent lock also serializes an ABSENT binding across different actors.
  perform 1 from public.courses where id=p_course_id and deleted_at is null for update;
  if not found then raise exception 'payment_setup_target_unavailable' using errcode='42501'; end if;
  select revision into v_revision from private.course_payment_instructors where course_id=p_course_id for update;
  v_revision:=coalesce(v_revision,0);
  if v_revision<>p_expected_revision or v_revision=2147483647 then
    raise exception 'payment_setup_state_conflict' using errcode='42501';
  end if;
  insert into private.course_payment_instructors(course_id,instructor_id,revision)
    values(p_course_id,p_instructor_id,v_revision+1)
    on conflict(course_id) do update set instructor_id=excluded.instructor_id,revision=excluded.revision;
  insert into private.course_payment_instructor_history(course_id,revision,instructor_id,actor_id)
    values(p_course_id,v_revision+1,p_instructor_id,v_uid);
  insert into private.security_events(actor_id,subject_id,action,details)
    values(v_uid,p_instructor_id,'course_payment_instructor_set',
      jsonb_build_object('course_id',p_course_id,'instructor_id',p_instructor_id,'revision',v_revision+1));
  return jsonb_build_object('course_id',p_course_id,'instructor_id',p_instructor_id,'revision',v_revision+1);
end;
$$;

create function public.get_my_instructor_payment_profile() returns jsonb
language sql stable security invoker set search_path='' as $$
  select private.read_payment_setup('profile',null,null,null);
$$;
create function public.save_my_instructor_payment_profile(
  p_recipient_name text,p_phone_number text,p_method_configuration text,p_expected_revision integer
) returns jsonb language sql security invoker set search_path='' as $$
  select private.save_my_instructor_payment_profile(p_recipient_name,p_phone_number,p_method_configuration,p_expected_revision);
$$;
create function public.get_course_payment_instructor(p_course_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select private.read_payment_setup('course',p_course_id,null,null);
$$;
create function public.set_course_payment_instructor(p_course_id uuid,p_instructor_id uuid,p_expected_revision integer) returns jsonb
language sql security invoker set search_path='' as $$
  select private.set_course_payment_instructor(p_course_id,p_instructor_id,p_expected_revision);
$$;
create function public.list_payment_instructors(p_after_id uuid default null,p_limit integer default 20) returns jsonb
language sql stable security invoker set search_path='' as $$
  select private.read_payment_setup('directory',null,p_after_id,p_limit);
$$;

revoke all on function private.reject_payment_setup_history_change(),private.payment_instructor_eligible(uuid),
  private.read_payment_setup(text,uuid,uuid,integer),private.save_my_instructor_payment_profile(text,text,text,integer),
  private.set_course_payment_instructor(uuid,uuid,integer),public.get_my_instructor_payment_profile(),
  public.save_my_instructor_payment_profile(text,text,text,integer),public.get_course_payment_instructor(uuid),
  public.set_course_payment_instructor(uuid,uuid,integer),public.list_payment_instructors(uuid,integer)
  from public,anon,authenticated,service_role;
-- Guarded helpers alone receive client execution for the invoker wrappers.
grant execute on function private.read_payment_setup(text,uuid,uuid,integer),
  private.save_my_instructor_payment_profile(text,text,text,integer),private.set_course_payment_instructor(uuid,uuid,integer),
  public.get_my_instructor_payment_profile(),public.save_my_instructor_payment_profile(text,text,text,integer),
  public.get_course_payment_instructor(uuid),public.set_course_payment_instructor(uuid,uuid,integer),
  public.list_payment_instructors(uuid,integer) to authenticated;
