-- STAGED ONLY. Pending means purchase intent, NOT submitted/received payment.
-- Creation remains CLOSED at both entry points; business choices precede enablement.
-- No payment method/destination, evidence, approval, entitlement or checkout policy.
create table private.pending_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete restrict,
  kind text not null check(kind in ('course','session')),
  course_id uuid not null references public.courses(id) on delete restrict,
  session_id uuid references public.course_sessions(id) on delete restrict,
  course_title_snapshot text not null check(length(course_title_snapshot) between 1 and 160),
  session_title_snapshot text,
  price_piasters integer not null check(price_piasters>=0),
  currency text not null default 'EGP' check(currency='EGP'),
  state text not null default 'pending' check(state='pending'),
  created_at timestamptz not null default now(),
  check((kind='course' and session_id is null and session_title_snapshot is null)
     or (kind='session' and session_id is not null and session_title_snapshot is not null
         and length(session_title_snapshot) between 1 and 160))
);
create index pending_orders_buyer_history_idx on private.pending_orders(buyer_id,created_at desc,id desc);
create index pending_orders_course_idx on private.pending_orders(course_id);
create index pending_orders_session_idx on private.pending_orders(session_id);
create table private.pending_order_operations (
  actor_id uuid not null references auth.users(id) on delete restrict,
  operation_id uuid not null,
  request_hash bytea not null check(octet_length(request_hash)=32),
  order_id uuid not null unique references private.pending_orders(id) on delete restrict,
  result jsonb not null check(jsonb_typeof(result)='object'),
  primary key(actor_id,operation_id)
);
alter table private.pending_orders enable row level security;
alter table private.pending_order_operations enable row level security;
revoke all on private.pending_orders,private.pending_order_operations from public,anon,authenticated,service_role;
grant select on private.pending_orders to authenticated;
create policy pending_orders_read_own on private.pending_orders for select to authenticated
  using ((select private.is_active()) and buyer_id=(select auth.uid()));
create policy pending_order_operations_read_own on private.pending_order_operations for select to authenticated
  using ((select private.is_active()) and actor_id=(select auth.uid()));

-- Both committed order snapshots and completed operation records are append-only.
create function private.reject_pending_order_change() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  raise exception 'order_immutable' using errcode='42501';
end;
$$;
revoke all on function private.reject_pending_order_change() from public,anon,authenticated;
create trigger pending_orders_immutable before update or delete on private.pending_orders
  for each row execute function private.reject_pending_order_change();
create trigger pending_order_operations_immutable before update or delete on private.pending_order_operations
  for each row execute function private.reject_pending_order_change();

create function public.get_own_order(p_order_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'order_access_required' using errcode='42501'; end if;
  if p_order_id is null then raise exception 'invalid_order_input' using errcode='22023'; end if;
  -- History never joins live content: only the buyer's original safe snapshots.
  select jsonb_build_object('id',o.id,'kind',o.kind,'course_id',o.course_id,'session_id',o.session_id,
    'course_title_snapshot',o.course_title_snapshot,'session_title_snapshot',o.session_title_snapshot,
    'price_piasters',o.price_piasters,'currency',o.currency,'state',o.state,
    'created_at',to_char(o.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
  into v_result from private.pending_orders o where o.id=p_order_id and o.buyer_id=auth.uid();
  return v_result;
end;
$$;

create function public.list_own_orders(
  p_before_created_at timestamptz default null,p_before_id uuid default null,p_limit integer default 20
) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'order_access_required' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>50
     or (p_before_created_at is null)<>(p_before_id is null)
     or (p_before_created_at is not null and not isfinite(p_before_created_at)) then
    raise exception 'invalid_order_input' using errcode='22023';
  end if;
  with candidates as materialized (
    select o.id,o.created_at from private.pending_orders o
    where o.buyer_id=auth.uid() and (p_before_created_at is null
      or (o.created_at,o.id)<(p_before_created_at,p_before_id))
    order by o.created_at desc,o.id desc limit p_limit+1
  ), page as materialized (
    select * from candidates order by created_at desc,id desc limit p_limit
  )
  select jsonb_build_object('items',coalesce((select jsonb_agg(public.get_own_order(id)
      order by created_at desc,id desc) from page),'[]'::jsonb),
    'has_more',(select count(*)>p_limit from candidates),
    'next_cursor',case when (select count(*)>p_limit from candidates) then (
      select jsonb_build_object('created_at',to_char(created_at at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'id',id)
      from page order by created_at asc,id asc limit 1) else null end)
  into v_result;
  return v_result;
end;
$$;

create function private.create_pending_order(p_kind text,p_target_id uuid,p_operation_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_operation private.pending_order_operations;
  v_course public.courses; v_session public.course_sessions; v_course_id uuid;
  v_order_id uuid; v_hash bytea; v_result jsonb;
begin
  if v_uid is null or not private.is_active() then
    raise exception 'order_access_required' using errcode='42501';
  end if;
  -- Lock order: actor account -> course -> session. Serializes actor operations
  -- without a mutable/incomplete ledger row; also serializes role/disable changes.
  select role into v_role from private.account_access where user_id=v_uid for update;
  if not private.is_active() then raise exception 'order_access_required' using errcode='42501'; end if;
  if v_role is distinct from 'student' then raise exception 'order_student_required' using errcode='42501'; end if;
  if p_kind is null or p_kind not in ('course','session') or p_target_id is null or p_operation_id is null then
    raise exception 'invalid_order_input' using errcode='22023';
  end if;
  v_hash:=sha256(convert_to(jsonb_build_array('pending-order-v1',v_uid,p_kind,p_target_id)::text,'UTF8'));
  select * into v_operation from private.pending_order_operations
    where actor_id=v_uid and operation_id=p_operation_id;
  if found then
    if v_operation.request_hash is distinct from v_hash then
      raise exception 'order_operation_reused' using errcode='22023';
    end if;
    -- A retry returns history, not a fresh offer or authorization capability.
    return v_operation.result;
  end if;
  if p_kind='course' then v_course_id:=p_target_id;
  else
    -- Parent membership is already immutable in the content schema.
    select course_id into v_course_id from public.course_sessions where id=p_target_id;
  end if;
  select * into v_course from public.courses where id=v_course_id for share;
  if not found or v_course.status<>'published' or v_course.deleted_at is not null then
    raise exception 'order_target_unavailable' using errcode='42501';
  end if;
  if p_kind='session' then
    select * into v_session from public.course_sessions where id=p_target_id for share;
    if not found or v_session.course_id<>v_course.id or v_session.status<>'published' or v_session.deleted_at is not null then
      raise exception 'order_target_unavailable' using errcode='42501';
    end if;
  end if;
  insert into private.pending_orders(buyer_id,kind,course_id,session_id,course_title_snapshot,
    session_title_snapshot,price_piasters)
  values(v_uid,p_kind,v_course.id,case when p_kind='session' then v_session.id else null end,
    v_course.title,case when p_kind='session' then v_session.title else null end,
    case when p_kind='session' then v_session.price_piasters else v_course.price_piasters end)
  returning id into v_order_id;
  v_result:=public.get_own_order(v_order_id);
  insert into private.pending_order_operations(actor_id,operation_id,request_hash,order_id,result)
    values(v_uid,p_operation_id,v_hash,v_order_id,v_result);
  insert into private.security_events(actor_id,subject_id,action,details)
    values(v_uid,v_uid,'pending_order_created',jsonb_build_object('order_id',v_order_id,'operation_id',p_operation_id));
  -- Distinct operations are NOT a settled repeat-purchase/checkout policy.
  return v_result;
end;
$$;
create function public.create_pending_order(p_kind text,p_target_id uuid,p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.create_pending_order(p_kind,p_target_id,p_operation_id);
$$;

revoke all on function public.get_own_order(uuid),public.list_own_orders(timestamptz,uuid,integer)
  from public,anon,authenticated;
grant execute on function public.get_own_order(uuid),public.list_own_orders(timestamptz,uuid,integer)
  to authenticated;
-- Deliberately NO creation grant. Enabling either entry point is a later reviewed gate.
revoke all on function public.create_pending_order(text,uuid,uuid),private.create_pending_order(text,uuid,uuid)
  from public,anon,authenticated,service_role;
