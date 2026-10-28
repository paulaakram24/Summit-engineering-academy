-- Actual private upload staging only. Uploaded means QUARANTINED, never clean,
-- ready, attached, published or downloadable. No existing bucket is changed.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('material-upload-quarantine','material-upload-quarantine',false,20971520,array['application/pdf','text/plain']);

-- Match the client basename/extension rules and Dart Unicode-whitespace stem trim.
-- PostgreSQL text cannot contain NUL. C1 controls are explicitly denied here too.
create function private.material_upload_file_name_valid(p_name text,p_type text) returns boolean
language sql immutable security invoker set search_path='' as $$
  select coalesce(char_length(p_name) between 5 and 160
    and p_name collate "C" !~ ('['||chr(1)||'-'||chr(31)||chr(127)||'-'||chr(159)||']')
    and strpos(p_name,'/')=0 and strpos(p_name,chr(92))=0
    and length(btrim(left(p_name,char_length(p_name)-4),
      U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'))>0
    and ((p_type='application/pdf' and lower(right(p_name,4) collate "C")='.pdf')
      or (p_type='text/plain' and lower(right(p_name,4) collate "C")='.txt')),false);
$$;

create table private.material_file_uploads (
  asset_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  material_id uuid not null references public.session_materials(id) on delete restrict,
  session_id uuid not null references public.course_sessions(id) on delete restrict,
  course_id uuid not null references public.courses(id) on delete restrict,
  expected_revision bigint not null check(expected_revision>0),
  operation_id uuid not null,
  request_hash bytea not null check(octet_length(request_hash)=32),
  path text not null unique,
  file_name text not null,
  content_type text not null check(content_type in ('application/pdf','text/plain')),
  byte_length bigint not null check(byte_length between 1 and 20971520),
  state text not null default 'reserved' check(state in ('reserved','uploaded')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '1 hour'),
  uploaded_at timestamptz,
  unique(actor_id,operation_id),
  check(private.material_upload_file_name_valid(file_name,content_type)),
  check((state='reserved' and uploaded_at is null) or (state='uploaded' and uploaded_at is not null)),
  check(path=material_id::text||'/'||asset_id::text||case content_type when 'application/pdf' then '.pdf' else '.txt' end)
);
create index material_file_uploads_actor_idx on private.material_file_uploads(actor_id,state,expires_at);
create index material_file_uploads_material_idx on private.material_file_uploads(material_id,created_at desc,asset_id desc);
create index material_file_uploads_session_idx on private.material_file_uploads(session_id);
create index material_file_uploads_course_idx on private.material_file_uploads(course_id);
alter table private.material_file_uploads enable row level security;
revoke all on private.material_file_uploads from public,anon,authenticated,service_role;

create function private.guard_material_file_upload() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='DELETE' then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  if (new.asset_id,new.actor_id,new.material_id,new.session_id,new.course_id,new.expected_revision,
      new.operation_id,new.request_hash,new.path,new.file_name,new.content_type,new.byte_length,new.created_at,new.expires_at)
    is distinct from
     (old.asset_id,old.actor_id,old.material_id,old.session_id,old.course_id,old.expected_revision,
      old.operation_id,old.request_hash,old.path,old.file_name,old.content_type,old.byte_length,old.created_at,old.expires_at)
    or old.state<>'reserved' or new.state<>'uploaded' or new.uploaded_at is null then
    raise exception 'material_upload_unavailable' using errcode='42501';
  end if;
  return new;
end;
$$;
create trigger material_file_upload_identity before update or delete on private.material_file_uploads
  for each row execute function private.guard_material_file_upload();

create function private.material_file_upload_status(p_row private.material_file_uploads) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('asset_id',p_row.asset_id,'material_id',p_row.material_id,'file_name',p_row.file_name,
    'content_type',p_row.content_type,'byte_length',p_row.byte_length,'state',p_row.state);
$$;

create function private.material_file_upload_insert_allowed(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.is_admin() and exists(
    select 1 from private.material_file_uploads a
    join public.session_materials m on m.id=a.material_id and m.session_id=a.session_id
    join public.course_sessions s on s.id=a.session_id and s.course_id=a.course_id
    join public.courses c on c.id=a.course_id
    where a.path=p_path and a.actor_id=auth.uid() and a.state='reserved' and a.expires_at>now()
      and m.revision=a.expected_revision and m.deleted_at is null and s.deleted_at is null and c.deleted_at is null
      and (m.kind='file' or (m.kind='pdf' and a.content_type='application/pdf'))
  );
$$;
-- INSERT only: Storage performs its upload authorization probe before binary
-- metadata exists. Bucket limits enforce MIME/size; completion compares metadata.
-- No SELECT, UPDATE, DELETE, upsert, signed URL or preview policy is introduced.
create policy material_upload_quarantine_insert on storage.objects for insert to authenticated
  with check(bucket_id='material-upload-quarantine' and private.material_file_upload_insert_allowed(name));

create function private.prepare_material_file_upload(p_material_id uuid,p_expected_revision bigint,
  p_file_name text,p_content_type text,p_byte_length bigint,p_operation_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_hash bytea; v_asset private.material_file_uploads;
  v_material public.session_materials; v_course_id uuid; v_asset_id uuid;
begin
  if not private.is_admin() then raise exception 'material_upload_access_required' using errcode='42501'; end if;
  -- Serialize actor-wide reservation cap and idempotency before the existing
  -- course -> session -> material lock order. No mutable operation placeholder.
  perform 1 from private.account_access where user_id=v_uid for update;
  if not private.is_admin() then raise exception 'material_upload_access_required' using errcode='42501'; end if;
  if p_operation_id is null then raise exception 'invalid_material_upload_input' using errcode='22023'; end if;
  v_hash:=sha256(convert_to(jsonb_build_array('material-file-upload-v1',p_material_id,p_expected_revision,
    p_file_name,p_content_type,p_byte_length)::text,'UTF8'));
  select * into v_asset from private.material_file_uploads where actor_id=v_uid and operation_id=p_operation_id;
  if found and v_asset.request_hash is distinct from v_hash then
    raise exception 'material_upload_operation_reused' using errcode='42501';
  end if;
  if p_material_id is null or p_expected_revision is null or p_expected_revision<1
    or not private.material_upload_file_name_valid(p_file_name,p_content_type)
    or p_content_type is null or p_content_type not in ('application/pdf','text/plain')
    or p_byte_length is null or p_byte_length not between 1 and 20971520 then
    raise exception 'invalid_material_upload_input' using errcode='22023';
  end if;
  select * into v_material from public.session_materials where id=p_material_id;
  if not found then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  begin
    perform private.lock_material_parent(v_material.session_id);
  exception when insufficient_privilege then
    raise exception 'material_upload_unavailable' using errcode='42501';
  end;
  select * into v_material from public.session_materials where id=p_material_id for update;
  if v_material.deleted_at is not null then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  if v_material.revision<>p_expected_revision then raise exception 'material_upload_conflict' using errcode='42501'; end if;
  if v_material.kind not in ('pdf','file') or (v_material.kind='pdf' and p_content_type<>'application/pdf') then
    raise exception 'invalid_material_upload_input' using errcode='22023';
  end if;
  if v_asset.asset_id is not null then
    if v_asset.state='reserved' and v_asset.expires_at<=now() then
      raise exception 'material_upload_unavailable' using errcode='42501';
    end if;
    return jsonb_build_object('asset_id',v_asset.asset_id,'path',v_asset.path,'state',v_asset.state);
  end if;
  if (select count(*) from private.material_file_uploads where actor_id=v_uid and state='reserved' and expires_at>now())>=20
    or (select count(*) from private.material_file_uploads where material_id=p_material_id and state='reserved' and expires_at>now())>=5 then
    raise exception 'material_upload_limit' using errcode='42501';
  end if;
  select course_id into v_course_id from public.course_sessions where id=v_material.session_id;
  v_asset_id:=gen_random_uuid();
  insert into private.material_file_uploads(asset_id,actor_id,material_id,session_id,course_id,expected_revision,
    operation_id,request_hash,path,file_name,content_type,byte_length)
  values(v_asset_id,v_uid,p_material_id,v_material.session_id,v_course_id,p_expected_revision,p_operation_id,v_hash,
    p_material_id::text||'/'||v_asset_id::text||case p_content_type when 'application/pdf' then '.pdf' else '.txt' end,
    p_file_name,p_content_type,p_byte_length) returning * into v_asset;
  insert into private.security_events(actor_id,subject_id,action,details)
    values(v_uid,v_uid,'material_file_upload_prepared',jsonb_build_object('asset_id',v_asset_id,'material_id',p_material_id));
  return jsonb_build_object('asset_id',v_asset_id,'path',v_asset.path,'state',v_asset.state);
end;
$$;

create function private.read_material_file_upload(p_asset_id uuid,p_material_id uuid,p_list boolean) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_asset private.material_file_uploads; v_material public.session_materials; v_result jsonb;
begin
  if not private.is_admin() then raise exception 'material_upload_access_required' using errcode='42501'; end if;
  if p_list is null or (p_list and p_material_id is null) or (not p_list and p_asset_id is null) then
    raise exception 'invalid_material_upload_input' using errcode='22023';
  end if;
  if not p_list then
    select * into v_asset from private.material_file_uploads where asset_id=p_asset_id;
    if not found then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
    p_material_id:=v_asset.material_id;
  end if;
  select m.* into v_material from public.session_materials m
    join public.course_sessions s on s.id=m.session_id join public.courses c on c.id=s.course_id
    where m.id=p_material_id and m.deleted_at is null and s.deleted_at is null and c.deleted_at is null;
  if not found then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  if p_list then
    select coalesce(jsonb_agg(private.material_file_upload_status(a::private.material_file_uploads) order by a.created_at desc,a.asset_id desc),'[]'::jsonb)
    into v_result from (select * from private.material_file_uploads where material_id=p_material_id
      order by created_at desc,asset_id desc limit 20) a;
    return v_result;
  end if;
  return private.material_file_upload_status(v_asset);
end;
$$;

create function private.complete_material_file_upload(p_asset_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_asset private.material_file_uploads; v_material public.session_materials;
begin
  if not private.is_admin() then raise exception 'material_upload_access_required' using errcode='42501'; end if;
  perform 1 from private.account_access where user_id=v_uid for update;
  if not private.is_admin() then raise exception 'material_upload_access_required' using errcode='42501'; end if;
  if p_asset_id is null then raise exception 'invalid_material_upload_input' using errcode='22023'; end if;
  select * into v_asset from private.material_file_uploads where asset_id=p_asset_id and actor_id=v_uid;
  if not found then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  begin
    perform private.lock_material_parent(v_asset.session_id);
  exception when insufficient_privilege then
    raise exception 'material_upload_unavailable' using errcode='42501';
  end;
  select * into v_material from public.session_materials where id=v_asset.material_id for update;
  select * into v_asset from private.material_file_uploads where asset_id=p_asset_id for update;
  if v_material.deleted_at is not null then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  if v_material.revision<>v_asset.expected_revision then raise exception 'material_upload_conflict' using errcode='42501'; end if;
  -- Repeat completion is status reconciliation only; no second audit/update.
  if v_asset.state='uploaded' then return private.material_file_upload_status(v_asset); end if;
  if v_asset.expires_at<=now() then raise exception 'material_upload_unavailable' using errcode='42501'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='material-upload-quarantine' and o.name=v_asset.path
    and o.metadata->>'mimetype'=v_asset.content_type
    and case when o.metadata->>'size' ~ '^[0-9]{1,8}$' then (o.metadata->>'size')::bigint=v_asset.byte_length else false end) then
    raise exception 'material_upload_unavailable' using errcode='42501';
  end if;
  update private.material_file_uploads set state='uploaded',uploaded_at=now() where asset_id=p_asset_id returning * into v_asset;
  insert into private.security_events(actor_id,subject_id,action,details)
    values(v_uid,v_uid,'material_file_upload_completed',jsonb_build_object('asset_id',p_asset_id,'material_id',v_asset.material_id));
  return private.material_file_upload_status(v_asset);
end;
$$;

create function public.prepare_material_file_upload(p_material_id uuid,p_expected_revision bigint,p_file_name text,
  p_content_type text,p_byte_length bigint,p_operation_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select private.prepare_material_file_upload(p_material_id,p_expected_revision,p_file_name,p_content_type,p_byte_length,p_operation_id);
$$;
create function public.get_material_file_upload(p_asset_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.read_material_file_upload(p_asset_id,null,false); $$;
create function public.list_material_file_uploads(p_material_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.read_material_file_upload(null,p_material_id,true); $$;
create function public.complete_material_file_upload(p_asset_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.complete_material_file_upload(p_asset_id); $$;

revoke all on function private.material_upload_file_name_valid(text,text),private.guard_material_file_upload(),private.material_file_upload_status(private.material_file_uploads),
  private.material_file_upload_insert_allowed(text),private.prepare_material_file_upload(uuid,bigint,text,text,bigint,uuid),
  private.read_material_file_upload(uuid,uuid,boolean),private.complete_material_file_upload(uuid),
  public.prepare_material_file_upload(uuid,bigint,text,text,bigint,uuid),public.get_material_file_upload(uuid),
  public.list_material_file_uploads(uuid),public.complete_material_file_upload(uuid) from public,anon,authenticated,service_role;
grant execute on function private.material_file_upload_insert_allowed(text),private.prepare_material_file_upload(uuid,bigint,text,text,bigint,uuid),
  private.read_material_file_upload(uuid,uuid,boolean),private.complete_material_file_upload(uuid),
  public.prepare_material_file_upload(uuid,bigint,text,text,bigint,uuid),public.get_material_file_upload(uuid),
  public.list_material_file_uploads(uuid),public.complete_material_file_upload(uuid) to authenticated;
