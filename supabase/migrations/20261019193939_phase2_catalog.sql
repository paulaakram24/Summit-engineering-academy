-- Hosted development version 20261019193939; read-only catalog, no table/RLS/Storage/material changes.
create function public.list_catalog_courses(
  p_search text default '',p_category text default null,p_level text default null,
  p_after_position integer default null,p_after_id uuid default null,p_limit integer default 20
) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_search text; v_category text; v_level text; v_result jsonb;
begin
  if not private.is_active() then raise exception 'catalog_access_required' using errcode='42501'; end if;
  if p_search is null or length(btrim(p_search))>100
     or (p_category is not null and length(btrim(p_category))>120)
     or (p_level is not null and length(btrim(p_level))>120)
     or p_limit is null or p_limit not between 1 and 50
     or ((p_after_position is null)<>(p_after_id is null))
     or p_after_position<0 then
    raise exception 'invalid_catalog_input' using errcode='22023';
  end if;
  v_search:=lower(btrim(p_search));
  v_category:=nullif(btrim(p_category),'');
  v_level:=nullif(btrim(p_level),'');
  with candidates as materialized (
    select c.id,c.position,jsonb_build_object('id',c.id,'title',c.title,'description',c.description,
      'instructor',c.instructor,'category',c.category,'level',c.level,
      'price_piasters',c.price_piasters,'position',c.position,'cover_path',c.cover_path) as item
    from public.courses c
    -- Explicit filters also restrict the administrator branch of existing RLS.
    where c.status='published' and c.deleted_at is null
      and (v_search='' or strpos(lower(c.title),v_search)>0
        or strpos(lower(c.instructor),v_search)>0 or strpos(lower(c.category),v_search)>0)
      and (v_category is null or btrim(c.category)=v_category)
      and (v_level is null or btrim(c.level)=v_level)
      and (p_after_position is null or (c.position,c.id)>(p_after_position,p_after_id))
    order by c.position,c.id limit p_limit+1
  ), page as materialized (
    select id,position,item from candidates order by position,id limit p_limit
  ) select jsonb_build_object(
      'items',coalesce((select jsonb_agg(item order by position,id) from page),'[]'::jsonb),
      'has_more',(select count(*)>p_limit from candidates),
      'next_cursor',case when (select count(*)>p_limit from candidates) then
        (select jsonb_build_object('position',position,'id',id) from page order by position desc,id desc limit 1)
        else null end) into v_result;
  return v_result;
end;
$$;

create function public.get_catalog_course(p_course_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'catalog_access_required' using errcode='42501'; end if;
  if p_course_id is null then raise exception 'invalid_catalog_input' using errcode='22023'; end if;
  select jsonb_build_object('id',c.id,'title',c.title,'description',c.description,
    'instructor',c.instructor,'category',c.category,'level',c.level,
    'price_piasters',c.price_piasters,'position',c.position,'cover_path',c.cover_path) into v_result
  from public.courses c where c.id=p_course_id and c.status='published' and c.deleted_at is null;
  -- Missing, draft, archived and deleted IDs have the same unavailable result.
  return v_result;
end;
$$;

create function public.list_catalog_sessions(
  p_course_id uuid,p_after_position integer default null,p_after_id uuid default null,
  p_limit integer default 20
) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'catalog_access_required' using errcode='42501'; end if;
  if p_course_id is null or p_limit is null or p_limit not between 1 and 50
     or ((p_after_position is null)<>(p_after_id is null)) or p_after_position<0 then
    raise exception 'invalid_catalog_input' using errcode='22023';
  end if;
  with candidates as materialized (
    select s.id,s.position,jsonb_build_object('id',s.id,'course_id',s.course_id,
      'session_number',s.session_number,'title',s.title,'description',s.description,
      'price_piasters',s.price_piasters,'position',s.position,'is_free_preview',s.is_free_preview) as item
    from public.course_sessions s join public.courses c on c.id=s.course_id
    where s.course_id=p_course_id and s.status='published' and s.deleted_at is null
      and c.status='published' and c.deleted_at is null
      and (p_after_position is null or (s.position,s.id)>(p_after_position,p_after_id))
    order by s.position,s.id limit p_limit+1
  ), page as materialized (
    select id,position,item from candidates order by position,id limit p_limit
  ) select jsonb_build_object(
      'items',coalesce((select jsonb_agg(item order by position,id) from page),'[]'::jsonb),
      'has_more',(select count(*)>p_limit from candidates),
      'next_cursor',case when (select count(*)>p_limit from candidates) then
        (select jsonb_build_object('position',position,'id',id) from page order by position desc,id desc limit 1)
        else null end) into v_result;
  return v_result;
end;
$$;

create function public.get_catalog_filters() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if not private.is_active() then raise exception 'catalog_access_required' using errcode='42501'; end if;
  with catalog as materialized (
    select btrim(c.category) as category,btrim(c.level) as level from public.courses c
      where c.status='published' and c.deleted_at is null
  ) select jsonb_build_object(
    'categories',coalesce((select jsonb_agg(value order by value collate "C")
      from (select distinct category as value from catalog) choices),'[]'::jsonb),
    'levels',coalesce((select jsonb_agg(value order by value collate "C")
      from (select distinct level as value from catalog) choices),'[]'::jsonb)) into v_result;
  return v_result;
end;
$$;

revoke all on function public.list_catalog_courses(text,text,text,integer,uuid,integer),
  public.list_catalog_sessions(uuid,integer,uuid,integer),public.get_catalog_course(uuid),
  public.get_catalog_filters() from public,anon,authenticated;
grant execute on function public.list_catalog_courses(text,text,text,integer,uuid,integer),
  public.list_catalog_sessions(uuid,integer,uuid,integer),public.get_catalog_course(uuid),
  public.get_catalog_filters() to authenticated;
