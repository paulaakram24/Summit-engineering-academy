-- 2.3-A only. Admin authoring; no asset, Storage, signing or student access.
create table public.session_materials (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.course_sessions(id) on delete restrict,
  kind text not null check (kind in ('video','pdf','file','link','assignment')),
  title text not null check (length(trim(title)) between 1 and 160),
  summary text not null default '' check (length(summary)<=10000),
  position integer not null default 0 check (position>=0),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  deleted_at timestamptz,
  revision bigint not null default 1 check (revision>0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,kind),
  check (deleted_at is null or status='archived'),
  -- Metadata is plain catalog-safe text. This is not a general secret detector.
  check (title !~* '(https?://|www\.|<[^>]+>)' and summary !~* '(https?://|www\.|<[^>]+>)'),
  -- No media assets exist in this slice, so media placeholders never publish.
  check (status<>'published' or kind in ('link','assignment'))
);
create index session_materials_order_idx on public.session_materials(session_id,position,id);
create index session_materials_active_order_idx on public.session_materials(session_id,position,id)
  where deleted_at is null;
create index session_materials_creator_idx on public.session_materials(created_by);

create table private.material_payloads (
  material_id uuid primary key,
  kind text not null,
  body_text text not null default '' check (length(body_text)<=10000),
  target_url text check (length(target_url)<=4096),
  foreign key(material_id,kind) references public.session_materials(id,kind) on delete restrict,
  check (kind='assignment' or body_text=''),
  check (kind='link' or target_url is null),
  check (target_url is null or (
    target_url ~ '^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^[:space:]\\<>]*)?$'
    and target_url !~ '[[:cntrl:]]'))
);
create table private.material_operations (
  actor_id uuid not null references auth.users(id),
  operation_id uuid not null,
  request_hash bytea not null check (octet_length(request_hash)=32),
  material_id uuid references public.session_materials(id) on delete restrict,
  result jsonb,
  created_at timestamptz not null default now(),
  primary key(actor_id,operation_id)
);
create index material_operations_material_idx on private.material_operations(material_id);
alter table public.session_materials enable row level security;
alter table private.material_payloads enable row level security;
alter table private.material_operations enable row level security;
revoke all on public.session_materials,private.material_payloads,private.material_operations
  from public,anon,authenticated;
grant select on public.session_materials to authenticated;
create policy session_materials_admin_read on public.session_materials for select to authenticated
  using ((select private.is_admin()));

create function private.guard_material_identity() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if (new.id,new.session_id,new.kind,new.created_by,new.created_at)
     is distinct from (old.id,old.session_id,old.kind,old.created_by,old.created_at) then
    raise exception 'material_identity_immutable' using errcode='22023';
  end if;
  if new.revision<>old.revision+1 then
    raise exception 'material_revision_invalid' using errcode='22023';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function private.guard_material_identity() from public,anon,authenticated;
create trigger session_materials_identity before update on public.session_materials
  for each row execute function private.guard_material_identity();

-- Explicit output allowlist; private bodies/targets never enter mutation results or operations.
create function private.material_descriptor(p_row public.session_materials) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('id',p_row.id,'session_id',p_row.session_id,'kind',p_row.kind,
    'title',p_row.title,'summary',p_row.summary,'position',p_row.position,'status',p_row.status,
    'deleted_at',p_row.deleted_at,'revision',p_row.revision,'created_by',p_row.created_by,
    'created_at',p_row.created_at,'updated_at',p_row.updated_at);
$$;
revoke all on function private.material_descriptor(public.session_materials) from public,anon,authenticated;

-- Owner-only helper. Lock order: operation -> course -> session -> material.
create function private.lock_material_parent(p_session_id uuid) returns void
language plpgsql security invoker set search_path='' as $$
declare v_course_id uuid;
begin
  select course_id into v_course_id from public.course_sessions where id=p_session_id;
  if not found then raise exception 'parent_unavailable' using errcode='42501'; end if;
  perform 1 from public.courses where id=v_course_id and deleted_at is null for update;
  if not found then raise exception 'parent_unavailable' using errcode='42501'; end if;
  perform 1 from public.course_sessions
    where id=p_session_id and course_id=v_course_id and deleted_at is null for update;
  if not found then raise exception 'parent_unavailable' using errcode='42501'; end if;
end;
$$;
revoke all on function private.lock_material_parent(uuid) from public,anon,authenticated;

create function private.mutate_session_material(
  p_action text,p_material_id uuid,p_session_id uuid,p_kind text,p_title text,p_summary text,
  p_position integer,p_status text,p_body_text text,p_target_url text,
  p_expected_revision bigint,p_operation_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_row public.session_materials;
  v_operation private.material_operations;
  v_session_id uuid;
  v_hash bytea;
  v_result jsonb;
begin
  if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  if p_action is null or p_action not in ('create','update','delete','restore') or p_operation_id is null then
    raise exception 'invalid_material_input' using errcode='22023';
  end if;
  -- The unexposed helper is granted for wrappers, so validate even direct helper invocation.
  if p_action='create' then
    if p_material_id is not null or p_session_id is null or p_expected_revision is not null
       or p_kind is null or p_kind not in ('video','pdf','file','link','assignment')
       or p_status is distinct from 'draft' then
      raise exception 'invalid_material_input' using errcode='22023';
    end if;
    v_session_id:=p_session_id;
  else
    if p_material_id is null or p_session_id is not null or p_kind is not null
       or p_expected_revision is null or p_expected_revision<1 then
      raise exception 'invalid_material_input' using errcode='22023';
    end if;
    if p_action in ('delete','restore') and
       (p_title is not null or p_summary is not null or p_position is not null or p_status is not null
        or p_body_text is not null or p_target_url is not null) then
      raise exception 'invalid_material_input' using errcode='22023';
    end if;
    select session_id into v_session_id from public.session_materials where id=p_material_id;
    if not found then raise exception 'material_unavailable' using errcode='42501'; end if;
  end if;

  -- A digest of canonical typed arguments, never a stored copy of protected payloads.
  v_hash:=sha256(convert_to(jsonb_build_array(p_action,p_material_id,p_session_id,p_kind,p_title,
    p_summary,p_position,p_status,p_body_text,p_target_url,p_expected_revision)::text,'UTF8'));
  insert into private.material_operations(actor_id,operation_id,request_hash)
    values(auth.uid(),p_operation_id,v_hash) on conflict(actor_id,operation_id) do nothing;
  select * into strict v_operation from private.material_operations
    where actor_id=auth.uid() and operation_id=p_operation_id for update;
  if v_operation.request_hash is distinct from v_hash then
    raise exception 'material_operation_reused' using errcode='22023';
  end if;
  -- Reauthorize current parent state even on a cached retry. No replay resurrects content.
  perform private.lock_material_parent(v_session_id);
  if v_operation.result is not null then return v_operation.result; end if;

  if p_action<>'create' then
    select * into v_row from public.session_materials where id=p_material_id for update;
    if not found then raise exception 'material_unavailable' using errcode='42501'; end if;
    if v_row.revision<>p_expected_revision then
      raise exception 'material_changed' using errcode='40001';
    end if;
    if (p_action='restore' and v_row.deleted_at is null)
       or (p_action in ('update','delete') and v_row.deleted_at is not null) then
      raise exception 'material_unavailable' using errcode='42501';
    end if;
  end if;

  if p_action in ('create','update') then
    if p_title is null or length(trim(p_title)) not between 1 and 160
       or p_summary is null or length(p_summary)>10000
       or p_title ~* '(https?://|www\.|<[^>]+>)' or p_summary ~* '(https?://|www\.|<[^>]+>)'
       or p_position is null or p_position<0
       or p_status is null or p_status not in ('draft','published','archived')
       or p_body_text is null or length(p_body_text)>10000 then
      raise exception 'invalid_material_input' using errcode='22023';
    end if;
    if p_action='create' then v_row.kind:=p_kind; end if;
    if (v_row.kind<>'assignment' and p_body_text<>'')
       or (v_row.kind<>'link' and p_target_url is not null)
       or (p_target_url is not null and (length(p_target_url)>4096
         or p_target_url !~ '^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^[:space:]\\<>]*)?$'
         or p_target_url ~ '[[:cntrl:]]')) then
      raise exception 'invalid_material_payload' using errcode='22023';
    end if;
    if p_status='published' and (v_row.kind in ('video','pdf','file')
       or (v_row.kind='link' and p_target_url is null)
       or (v_row.kind='assignment' and length(trim(p_body_text))=0)) then
      raise exception 'material_not_ready' using errcode='22023';
    end if;
    if p_action='create' then
      insert into public.session_materials(session_id,kind,title,summary,position)
        values(v_session_id,p_kind,trim(p_title),p_summary,p_position) returning * into v_row;
      insert into private.material_payloads(material_id,kind,body_text,target_url)
        values(v_row.id,v_row.kind,p_body_text,p_target_url);
    else
      update public.session_materials set title=trim(p_title),summary=p_summary,position=p_position,
        status=p_status,revision=revision+1 where id=v_row.id returning * into v_row;
      update private.material_payloads set body_text=p_body_text,target_url=p_target_url
        where material_id=v_row.id;
      if not found then raise exception 'material_unavailable' using errcode='42501'; end if;
    end if;
  elsif p_action='delete' then
    update public.session_materials set status='archived',deleted_at=now(),revision=revision+1
      where id=v_row.id returning * into v_row;
  else
    update public.session_materials set status='draft',deleted_at=null,revision=revision+1
      where id=v_row.id returning * into v_row;
  end if;

  v_result:=private.material_descriptor(v_row);
  insert into private.security_events(actor_id,subject_id,action,details)
    values(auth.uid(),auth.uid(),'material_' || p_action,jsonb_build_object(
      'entity','session_materials','id',v_row.id,'session_id',v_row.session_id,
      'status',v_row.status,'deleted',v_row.deleted_at is not null,'revision',v_row.revision));
  update private.material_operations set material_id=v_row.id,result=v_result
    where actor_id=auth.uid() and operation_id=p_operation_id;
  return v_result;
end;
$$;

create function private.get_admin_material_detail(p_material_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_admin() then raise exception 'admin_required' using errcode='42501'; end if;
  -- Read-only authoring detail includes deleted items/parents for recovery, never delivery.
  -- One statement snapshot keeps revision and protected payload consistent.
  select jsonb_build_object('descriptor',private.material_descriptor(m),
    'body_text',p.body_text,'target_url',p.target_url) into v_result
    from public.session_materials m join private.material_payloads p on p.material_id=m.id
    where m.id=p_material_id;
  if not found then raise exception 'material_unavailable' using errcode='42501'; end if;
  return v_result;
end;
$$;

create function public.create_session_material(p_session_id uuid,p_kind text,p_title text,
  p_summary text,p_position integer,p_body_text text,p_target_url text,p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.mutate_session_material('create',null,p_session_id,p_kind,p_title,p_summary,
    p_position,'draft',p_body_text,p_target_url,null,p_operation_id);
$$;
create function public.update_session_material(p_material_id uuid,p_expected_revision bigint,
  p_title text,p_summary text,p_position integer,p_status text,p_body_text text,p_target_url text,
  p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.mutate_session_material('update',p_material_id,null,null,p_title,p_summary,
    p_position,p_status,p_body_text,p_target_url,p_expected_revision,p_operation_id);
$$;
create function public.delete_session_material(p_material_id uuid,p_expected_revision bigint,
  p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.mutate_session_material('delete',p_material_id,null,null,null,null,null,null,
    null,null,p_expected_revision,p_operation_id);
$$;
create function public.restore_session_material(p_material_id uuid,p_expected_revision bigint,
  p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.mutate_session_material('restore',p_material_id,null,null,null,null,null,null,
    null,null,p_expected_revision,p_operation_id);
$$;
create function public.get_admin_material_detail(p_material_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.get_admin_material_detail(p_material_id);
$$;

revoke all on function private.mutate_session_material(text,uuid,uuid,text,text,text,integer,text,text,text,bigint,uuid),
  private.get_admin_material_detail(uuid) from public,anon,authenticated;
grant execute on function private.mutate_session_material(text,uuid,uuid,text,text,text,integer,text,text,text,bigint,uuid),
  private.get_admin_material_detail(uuid) to authenticated;
revoke all on function public.create_session_material(uuid,text,text,text,integer,text,text,uuid),
  public.update_session_material(uuid,bigint,text,text,integer,text,text,text,uuid),
  public.delete_session_material(uuid,bigint,uuid),public.restore_session_material(uuid,bigint,uuid),
  public.get_admin_material_detail(uuid) from public,anon,authenticated;
grant execute on function public.create_session_material(uuid,text,text,text,integer,text,text,uuid),
  public.update_session_material(uuid,bigint,text,text,integer,text,text,text,uuid),
  public.delete_session_material(uuid,bigint,uuid),public.restore_session_material(uuid,bigint,uuid),
  public.get_admin_material_detail(uuid) to authenticated;
