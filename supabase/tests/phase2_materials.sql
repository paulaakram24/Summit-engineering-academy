-- Main runs this ENTIRE file in one privileged connection, with stop-on-error.
-- Requires identity, content, covers and phase2_admin_materials migrations.
-- No hosted calls, Storage objects, actual media or owner-account changes.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';

CREATE TEMP TABLE phase2m_results(name text PRIMARY KEY, outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE phase2m_items(key text PRIMARY KEY,id uuid NOT NULL,operation_id uuid NOT NULL,result jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.phase2m_results,pg_temp.phase2m_items TO authenticated;
GRANT SELECT,INSERT ON pg_temp.phase2m_results TO anon;
GRANT SELECT ON pg_temp.phase2m_items TO anon;

CREATE FUNCTION pg_temp.check_true(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.phase2m_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.expect_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN
    EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  -- Assertions are outside the caught subtransaction; helper failures cannot pass.
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.phase2m_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.mid(p_key text) RETURNS uuid
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$ SELECT id FROM pg_temp.phase2m_items WHERE key=p_key; $helper$;
CREATE FUNCTION pg_temp.mop(p_key text) RETURNS uuid
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$ SELECT operation_id FROM pg_temp.phase2m_items WHERE key=p_key; $helper$;
GRANT EXECUTE ON FUNCTION pg_temp.check_true(text,text),pg_temp.expect_error(text,text,text,text),
  pg_temp.mid(text),pg_temp.mop(text) TO authenticated,anon;

-- Collision-failing fictional fixtures. Never upsert an identity or use real owner data.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f2c0e300-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
  'phase2m-'||n||'@example.invalid',now(),'{"provider":"email","providers":["email"]}'::jsonb,
  '{"name":"Fictional materials fixture","role":"admin","is_admin":true}'::jsonb,false,now(),now()
FROM generate_series(1,3) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f2c0e300-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
  ('f2c0e300-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM generate_series(1,3) n;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000001","session_id":"f2c0e300-0000-4000-8000-000000000101"}';
SELECT pg_temp.check_true('fixture admin metadata is not role authority',$test$ SELECT public.register_device(repeat('a',64),'Materials admin fixture')->>'role'='student' $test$);
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000002","session_id":"f2c0e300-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.check_true('fixture student ignores forged role',$test$ SELECT public.register_device(repeat('b',64),'Materials student fixture')->>'role'='student' $test$);
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000003","session_id":"f2c0e300-0000-4000-8000-000000000103"}';
SELECT public.register_device(repeat('c',64),'Materials second admin fixture');
RESET ROLE;
UPDATE private.account_access SET role='admin'
WHERE user_id IN ('f2c0e300-0000-4000-8000-000000000001','f2c0e300-0000-4000-8000-000000000003');
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000001","session_id":"f2c0e300-0000-4000-8000-000000000101"}';
-- Fixed parents are privileged setup only; content audit still checks the admitted admin.
INSERT INTO public.courses(id,title,instructor,category,level,status)
VALUES('f2c0e300-0000-4000-8000-000000000201','Materials fixture','Fictional','Engineering','1','published');
INSERT INTO public.course_sessions(id,course_id,session_number,title,status,is_free_preview)
VALUES('f2c0e300-0000-4000-8000-000000000301','f2c0e300-0000-4000-8000-000000000201',1,'Materials fixture session','published',true);

SELECT pg_temp.check_true('all three new tables use RLS',$test$ SELECT count(*)=3 AND bool_and(relrowsecurity) FROM pg_class WHERE oid IN ('public.session_materials'::regclass,'private.material_payloads'::regclass,'private.material_operations'::regclass) $test$);
SELECT pg_temp.check_true('private tables have zero client policies',$test$ SELECT count(*)=0 FROM pg_policies WHERE schemaname='private' AND tablename IN ('material_payloads','material_operations') $test$);
SELECT pg_temp.check_true('base table has exactly admin SELECT policy',$test$ SELECT count(*)=1 AND bool_and(cmd='SELECT' AND roles=ARRAY['authenticated']::name[] AND qual LIKE '%private.is_admin()%') FROM pg_policies WHERE schemaname='public' AND tablename='session_materials' $test$);
SELECT pg_temp.check_true('client grants are SELECT only on base and none private',$test$ SELECT has_table_privilege('authenticated','public.session_materials','SELECT') AND NOT has_table_privilege('anon','public.session_materials','SELECT') AND NOT has_table_privilege('authenticated','public.session_materials','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AND NOT has_table_privilege('authenticated','private.material_payloads','SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('authenticated','private.material_operations','SELECT,INSERT,UPDATE,DELETE') $test$);
SELECT pg_temp.check_true('five public wrappers are invoker with empty search path',$test$ SELECT count(*)=5 AND bool_and(NOT prosecdef AND proconfig=ARRAY['search_path=""']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('create_session_material','update_session_material','delete_session_material','restore_session_material','get_admin_material_detail') $test$);
SELECT pg_temp.check_true('all material RPC grants exclude anon and PUBLIC',$test$ SELECT count(*)=7 AND bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname IN ('create_session_material','update_session_material','delete_session_material','restore_session_material','get_admin_material_detail')) OR (n.nspname='private' AND p.proname IN ('mutate_session_material','get_admin_material_detail')) $test$);
SELECT pg_temp.check_true('owner-only material helpers are not directly callable',$test$ SELECT NOT has_function_privilege('authenticated','private.material_descriptor(public.session_materials)','EXECUTE') AND NOT has_function_privilege('authenticated','private.lock_material_parent(uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','private.guard_material_identity()','EXECUTE') $test$);
SELECT pg_temp.check_true('descriptor serializer is STABLE',$test$ SELECT provolatile='s' FROM pg_proc WHERE oid='private.material_descriptor(public.session_materials)'::regprocedure $test$);
SELECT pg_temp.check_true('private buckets and existing Storage policies preserved',$test$ SELECT (SELECT count(*)=3 AND bool_and(NOT public) FROM storage.buckets WHERE id IN ('course-materials','payment-receipts','assignment-submissions')) AND NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname NOT IN ('course_covers_read','course_covers_insert','course_covers_delete')) $test$);
SELECT pg_temp.check_true('base schema has no protected locator or payload fields',$test$ SELECT array_agg(column_name::text ORDER BY ordinal_position)=ARRAY['id','session_id','kind','title','summary','position','status','deleted_at','revision','created_by','created_at','updated_at'] FROM information_schema.columns WHERE table_schema='public' AND table_name='session_materials' $test$);

SET LOCAL ROLE authenticated;
WITH planned AS MATERIALIZED (
  SELECT kind,n,kind||n::text AS key,gen_random_uuid() AS operation_id
  FROM unnest(ARRAY['video','pdf','file','link','assignment']) kind CROSS JOIN generate_series(1,5) n
), made AS MATERIALIZED (
  SELECT key,operation_id,public.create_session_material('f2c0e300-0000-4000-8000-000000000301',kind,key,
    'Catalog safe',n,CASE WHEN kind='assignment' THEN 'CANARY_BODY_'||n::text ELSE '' END,
    CASE WHEN kind='link' THEN 'https://example.invalid/private?token=CANARY_LINK' ELSE NULL END,operation_id) AS result
  FROM planned
) INSERT INTO pg_temp.phase2m_items SELECT key,(result->>'id')::uuid,operation_id,result FROM made;
SELECT pg_temp.check_true('five of each kind coexist in one session',$test$ SELECT count(*)=5 AND min(n)=5 AND max(n)=5 FROM (SELECT kind,count(*) n FROM public.session_materials WHERE session_id='f2c0e300-0000-4000-8000-000000000301' GROUP BY kind) x $test$);
SELECT pg_temp.check_true('create sets draft revision creator and immutable parent',$test$ SELECT count(*)=25 AND bool_and(status='draft' AND revision=1 AND created_by=auth.uid() AND session_id='f2c0e300-0000-4000-8000-000000000301' AND deleted_at IS NULL) FROM public.session_materials WHERE id IN (SELECT id FROM pg_temp.phase2m_items) $test$);
SELECT pg_temp.check_true('twenty-item keyset pages cover ordered list',$test$ WITH first_page AS MATERIALIZED (SELECT position,id FROM public.session_materials WHERE session_id='f2c0e300-0000-4000-8000-000000000301' AND deleted_at IS NULL ORDER BY position,id LIMIT 20), boundary AS (SELECT position,id FROM first_page ORDER BY position DESC,id DESC LIMIT 1), second_page AS (SELECT m.position,m.id FROM public.session_materials m,boundary b WHERE m.session_id='f2c0e300-0000-4000-8000-000000000301' AND m.deleted_at IS NULL AND (m.position,m.id)>(b.position,b.id) ORDER BY m.position,m.id LIMIT 20) SELECT (SELECT count(*) FROM first_page)=20 AND (SELECT count(*) FROM second_page)=5 AND (SELECT count(DISTINCT id) FROM (SELECT id FROM first_page UNION ALL SELECT id FROM second_page) x)=25 $test$);
SELECT pg_temp.check_true('private link returned only in explicit admin detail',$test$ SELECT public.get_admin_material_detail(pg_temp.mid('link1'))->>'target_url'='https://example.invalid/private?token=CANARY_LINK' AND NOT ((SELECT result FROM pg_temp.phase2m_items WHERE key='link1') ?| ARRAY['target_url','body_text','payload','url','path','provider_id']) $test$);
SELECT pg_temp.check_true('assignment body returned only in explicit admin detail',$test$ SELECT public.get_admin_material_detail(pg_temp.mid('assignment1'))->>'body_text'='CANARY_BODY_1' AND NOT ((SELECT result FROM pg_temp.phase2m_items WHERE key='assignment1')::text LIKE '%CANARY_BODY%') $test$);
SELECT pg_temp.check_true('identical create retry returns exact original result',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','link1','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1'))=(SELECT result FROM pg_temp.phase2m_items WHERE key='link1') $test$);
SELECT pg_temp.expect_error('changed create retry rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','Changed','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1')) $test$,'22023','material_operation_reused');
SELECT pg_temp.expect_error('null operation rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'',NULL,NULL) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('blank title rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','   ','',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('oversized title rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file',repeat('x',161),'',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('oversized summary rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','x',repeat('x',10001),0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('negative order rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','x','',-1,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('unknown kind rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','html','x','',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('null kind rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301',NULL,'x','',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('metadata URL rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','https://example.invalid/secret',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('metadata embed rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','<iframe src="private">',0,'',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('body only allowed for assignment',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','video','x','',0,'secret',NULL,gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('target only allowed for link',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','assignment','x','',0,'body','https://example.invalid/',gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('oversized body rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','assignment','x','',0,repeat('x',10001),NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('unsafe target scheme rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'','javascript:alert(1)',gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('target credentials rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'','https://user:pass@example.invalid/',gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('target backslash rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'',E'https://example.invalid/\\secret',gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('target whitespace rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'',E'https://example.invalid/\nsecret',gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('oversized target rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','x','',0,'','https://example.invalid/'||repeat('x',4096),gen_random_uuid()) $test$,'22023','invalid_material_payload');
SELECT pg_temp.expect_error('missing parent rejected',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000999','file','x','',0,'',NULL,gen_random_uuid()) $test$,'42501','parent_unavailable');
SELECT pg_temp.expect_error('missing material detail rejected',$test$ SELECT public.get_admin_material_detail('f2c0e300-0000-4000-8000-000000000999') $test$,'42501','material_unavailable');
SELECT pg_temp.expect_error('unknown status rejected',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'link1','',1,'hidden','','https://example.invalid/',gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('null revision rejected',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),NULL,'link1','',1,'draft','',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('video placeholder cannot publish',$test$ SELECT public.update_session_material(pg_temp.mid('video1'),1,'video1','',1,'published','',NULL,gen_random_uuid()) $test$,'22023','material_not_ready');
SELECT pg_temp.expect_error('PDF placeholder cannot publish',$test$ SELECT public.update_session_material(pg_temp.mid('pdf1'),1,'pdf1','',1,'published','',NULL,gen_random_uuid()) $test$,'22023','material_not_ready');
SELECT pg_temp.expect_error('file placeholder cannot publish',$test$ SELECT public.update_session_material(pg_temp.mid('file1'),1,'file1','',1,'published','',NULL,gen_random_uuid()) $test$,'22023','material_not_ready');
SELECT pg_temp.expect_error('unconfigured link cannot publish',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'link1','',1,'published','',NULL,gen_random_uuid()) $test$,'22023','material_not_ready');
SELECT pg_temp.expect_error('empty assignment cannot publish',$test$ SELECT public.update_session_material(pg_temp.mid('assignment1'),1,'assignment1','',1,'published','   ',NULL,gen_random_uuid()) $test$,'22023','material_not_ready');

-- Update returns descriptor only; retain the operation and its original result for retry tests.
WITH made AS MATERIALIZED (SELECT gen_random_uuid() op), changed AS MATERIALIZED (
  SELECT op,public.update_session_material(pg_temp.mid('link1'),1,'Edited link','Safe edited summary',8,'published','','https://example.invalid/new?token=CANARY_CHANGED',op) result FROM made
) INSERT INTO pg_temp.phase2m_items SELECT 'link_update',(result->>'id')::uuid,op,result FROM changed;
SELECT pg_temp.check_true('configured link publishes with CAS and position',$test$ SELECT status='published' AND revision=2 AND position=8 AND title='Edited link' FROM public.session_materials WHERE id=pg_temp.mid('link1') $test$);
SELECT pg_temp.check_true('update mutation result excludes private target',$test$ SELECT NOT (result::text LIKE '%CANARY_CHANGED%') AND NOT (result ? 'target_url') FROM pg_temp.phase2m_items WHERE key='link_update' $test$);
SELECT pg_temp.check_true('identical update retry is exact original snapshot',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'Edited link','Safe edited summary',8,'published','','https://example.invalid/new?token=CANARY_CHANGED',pg_temp.mop('link_update'))=(SELECT result FROM pg_temp.phase2m_items WHERE key='link_update') $test$);
SELECT pg_temp.expect_error('changed update retry rejected',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'Changed again','Safe edited summary',8,'published','','https://example.invalid/new?token=CANARY_CHANGED',pg_temp.mop('link_update')) $test$,'22023','material_operation_reused');
SELECT pg_temp.expect_error('stale CAS rejects without clobber',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'Stale','',0,'draft','',NULL,gen_random_uuid()) $test$,'40001','material_changed');
SELECT pg_temp.check_true('configured assignment publishes admin state',$test$ SELECT public.update_session_material(pg_temp.mid('assignment1'),1,'Assignment instructions','Catalog safe',1,'published','CANARY_BODY_UPDATED',NULL,gen_random_uuid())->>'status'='published' $test$);
SELECT pg_temp.check_true('archive is explicit CAS update',$test$ SELECT public.update_session_material(pg_temp.mid('assignment1'),2,'Assignment instructions','Catalog safe',1,'archived','CANARY_BODY_UPDATED',NULL,gen_random_uuid())->>'status'='archived' $test$);

WITH made AS MATERIALIZED (SELECT gen_random_uuid() op), changed AS MATERIALIZED (
  SELECT op,public.delete_session_material(pg_temp.mid('link1'),2,op) result FROM made
) INSERT INTO pg_temp.phase2m_items SELECT 'link_delete',(result->>'id')::uuid,op,result FROM changed;
SELECT pg_temp.check_true('soft delete archives and increments revision',$test$ SELECT status='archived' AND deleted_at IS NOT NULL AND revision=3 FROM public.session_materials WHERE id=pg_temp.mid('link1') $test$);
SELECT pg_temp.check_true('identical delete retry does not increment',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),2,pg_temp.mop('link_delete'))=(SELECT result FROM pg_temp.phase2m_items WHERE key='link_delete') AND (SELECT revision=3 FROM public.session_materials WHERE id=pg_temp.mid('link1')) $test$);
SELECT pg_temp.check_true('late create retry returns old snapshot but never resurrects',$test$ SELECT (public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','link1','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1'))->>'revision')::bigint=1 AND (SELECT deleted_at IS NOT NULL AND revision=3 FROM public.session_materials WHERE id=pg_temp.mid('link1')) $test$);
SELECT pg_temp.check_true('late update retry returns old snapshot but never resurrects',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),1,'Edited link','Safe edited summary',8,'published','','https://example.invalid/new?token=CANARY_CHANGED',pg_temp.mop('link_update'))=(SELECT result FROM pg_temp.phase2m_items WHERE key='link_update') AND (SELECT deleted_at IS NOT NULL AND revision=3 FROM public.session_materials WHERE id=pg_temp.mid('link1')) $test$);
SELECT pg_temp.expect_error('deleted material cannot edit',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),3,'x','',0,'draft','',NULL,gen_random_uuid()) $test$,'42501','material_unavailable');
SELECT pg_temp.expect_error('new repeated delete requires restore first',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),3,gen_random_uuid()) $test$,'42501','material_unavailable');
WITH made AS MATERIALIZED (SELECT gen_random_uuid() op), changed AS MATERIALIZED (
  SELECT op,public.restore_session_material(pg_temp.mid('link1'),3,op) result FROM made
) INSERT INTO pg_temp.phase2m_items SELECT 'link_restore',(result->>'id')::uuid,op,result FROM changed;
SELECT pg_temp.check_true('restore always draft with identity and payload preserved',$test$ SELECT m.status='draft' AND m.deleted_at IS NULL AND m.revision=4 AND m.kind='link' AND m.session_id='f2c0e300-0000-4000-8000-000000000301' AND public.get_admin_material_detail(m.id)->>'target_url'='https://example.invalid/new?token=CANARY_CHANGED' FROM public.session_materials m WHERE id=pg_temp.mid('link1') $test$);
SELECT pg_temp.check_true('identical restore retry exact result',$test$ SELECT public.restore_session_material(pg_temp.mid('link1'),3,pg_temp.mop('link_restore'))=(SELECT result FROM pg_temp.phase2m_items WHERE key='link_restore') AND (SELECT revision=4 FROM public.session_materials WHERE id=pg_temp.mid('link1')) $test$);
SELECT pg_temp.expect_error('restore of live material rejected',$test$ SELECT public.restore_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','material_unavailable');
SELECT pg_temp.expect_error('operation cannot cross action boundaries',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),4,pg_temp.mop('link_restore')) $test$,'22023','material_operation_reused');

SELECT pg_temp.expect_error('admin direct insert denied',$test$ INSERT INTO public.session_materials(session_id,kind,title) VALUES('f2c0e300-0000-4000-8000-000000000301','file','bypass') $test$,'42501','permission denied for table session_materials');
SELECT pg_temp.expect_error('admin direct parent reassignment denied',$test$ UPDATE public.session_materials SET session_id='f2c0e300-0000-4000-8000-000000000999' WHERE id=pg_temp.mid('link1') $test$,'42501','permission denied for table session_materials');
SELECT pg_temp.expect_error('admin direct kind reassignment denied',$test$ UPDATE public.session_materials SET kind='video' WHERE id=pg_temp.mid('link1') $test$,'42501','permission denied for table session_materials');
SELECT pg_temp.expect_error('admin direct payload SELECT denied',$test$ SELECT * FROM private.material_payloads $test$,'42501','permission denied for table material_payloads');
SELECT pg_temp.expect_error('admin direct payload UPDATE denied',$test$ UPDATE private.material_payloads SET target_url='https://example.invalid/forged' WHERE material_id=pg_temp.mid('link1') $test$,'42501','permission denied for table material_payloads');
SELECT pg_temp.expect_error('admin direct operations SELECT denied',$test$ SELECT * FROM private.material_operations $test$,'42501','permission denied for table material_operations');
SELECT pg_temp.expect_error('admin permanent DELETE denied',$test$ DELETE FROM public.session_materials WHERE id=pg_temp.mid('link1') $test$,'42501','permission denied for table session_materials');
SELECT pg_temp.expect_error('direct helper cannot change parent or kind',$test$ SELECT private.mutate_session_material('update',pg_temp.mid('link1'),'f2c0e300-0000-4000-8000-000000000301','video','x','',0,'draft','',NULL,4,gen_random_uuid()) $test$,'22023','invalid_material_input');
SELECT pg_temp.expect_error('direct helper cannot publish on create',$test$ SELECT private.mutate_session_material('create',NULL,'f2c0e300-0000-4000-8000-000000000301','link','x','',0,'published','','https://example.invalid/',NULL,gen_random_uuid()) $test$,'22023','invalid_material_input');

-- Parent state guard applies even to cached retries, while detail remains admin-readable.
UPDATE public.course_sessions SET deleted_at=now() WHERE id='f2c0e300-0000-4000-8000-000000000301';
SELECT pg_temp.expect_error('deleted session blocks create',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','x','',0,'',NULL,gen_random_uuid()) $test$,'42501','parent_unavailable');
SELECT pg_temp.expect_error('deleted session blocks update',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),4,'x','',0,'draft','',NULL,gen_random_uuid()) $test$,'42501','parent_unavailable');
SELECT pg_temp.expect_error('deleted session blocks cached create',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','link1','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1')) $test$,'42501','parent_unavailable');
SELECT pg_temp.check_true('admin detail readable for deleted-parent recovery',$test$ SELECT public.get_admin_material_detail(pg_temp.mid('link1'))->>'target_url'='https://example.invalid/new?token=CANARY_CHANGED' $test$);
UPDATE public.course_sessions SET deleted_at=NULL WHERE id='f2c0e300-0000-4000-8000-000000000301';
SELECT pg_temp.check_true('parent restore does not change material state',$test$ SELECT m.revision=4 AND m.status='draft' AND s.status='draft' FROM public.session_materials m JOIN public.course_sessions s ON s.id=m.session_id WHERE m.id=pg_temp.mid('link1') $test$);
SELECT pg_temp.check_true('draft parent permits admin preparation',$test$ SELECT public.update_session_material(pg_temp.mid('file1'),1,'File placeholder','',9,'draft','',NULL,gen_random_uuid())->>'revision'='2' $test$);
UPDATE public.courses SET deleted_at=now() WHERE id='f2c0e300-0000-4000-8000-000000000201';
SELECT pg_temp.expect_error('deleted course blocks create',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','x','',0,'',NULL,gen_random_uuid()) $test$,'42501','parent_unavailable');
SELECT pg_temp.expect_error('deleted course blocks delete',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','parent_unavailable');
SELECT pg_temp.expect_error('deleted course blocks restore',$test$ SELECT public.restore_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','parent_unavailable');
UPDATE public.courses SET deleted_at=NULL WHERE id='f2c0e300-0000-4000-8000-000000000201';

-- Actor-scoped operation UUID: a different admitted admin gets a separate result.
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000003","session_id":"f2c0e300-0000-4000-8000-000000000103"}';
SELECT pg_temp.check_true('same operation ID is isolated per actor',$test$ SELECT (public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','link1','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1'))->>'id')::uuid<>pg_temp.mid('link1') $test$);
RESET ROLE;
-- Privileged trigger checks prove identity immutability beyond the client DML denial.
SELECT pg_temp.expect_error('trigger preserves immutable parent',$test$ UPDATE public.session_materials SET session_id='f2c0e300-0000-4000-8000-000000000999',revision=revision+1 WHERE id=pg_temp.mid('link1') $test$,'22023','material_identity_immutable');
SELECT pg_temp.expect_error('trigger preserves immutable kind',$test$ UPDATE public.session_materials SET kind='assignment',revision=revision+1 WHERE id=pg_temp.mid('link1') $test$,'22023','material_identity_immutable');
SELECT pg_temp.expect_error('trigger preserves immutable creator',$test$ UPDATE public.session_materials SET created_by='f2c0e300-0000-4000-8000-000000000003',revision=revision+1 WHERE id=pg_temp.mid('link1') $test$,'22023','material_identity_immutable');
SELECT pg_temp.expect_error('trigger enforces server revision step',$test$ UPDATE public.session_materials SET title='bypass' WHERE id=pg_temp.mid('link1') $test$,'22023','material_revision_invalid');
SELECT pg_temp.check_true('one payload and completed operation for every create',$test$ SELECT (SELECT count(*) FROM public.session_materials WHERE created_by::text LIKE 'f2c0e300-%')=26 AND (SELECT count(*) FROM private.material_payloads p JOIN public.session_materials m ON m.id=p.material_id WHERE m.created_by::text LIKE 'f2c0e300-%')=26 AND NOT EXISTS(SELECT 1 FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e300-%' AND (material_id IS NULL OR result IS NULL)) $test$);
SELECT pg_temp.check_true('audit events equal successful operations not retries',$test$ SELECT (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e300-%' AND action LIKE 'material_%')=(SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e300-%') AND (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e300-%')=32 $test$);
SELECT pg_temp.check_true('audit and operation results exclude protected canaries',$test$ SELECT NOT EXISTS(SELECT 1 FROM private.security_events WHERE actor_id::text LIKE 'f2c0e300-%' AND action LIKE 'material_%' AND (details::text LIKE '%CANARY_%' OR details ?| ARRAY['body_text','target_url','path','provider_id','request_hash'])) AND NOT EXISTS(SELECT 1 FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e300-%' AND result::text LIKE '%CANARY_%') $test$);
SELECT pg_temp.check_true('descriptor SELECT excludes protected canaries',$test$ SELECT bool_and(to_jsonb(m)::text NOT LIKE '%CANARY_%') FROM public.session_materials m WHERE created_by::text LIKE 'f2c0e300-%' $test$);

-- A deliberately failed outer statement must roll back the already-completed mutation,
-- its payload, operation record AND audit. This helper runs with caller privileges.
CREATE FUNCTION pg_temp.mutate_then_fail() RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM public.create_session_material('f2c0e300-0000-4000-8000-000000000301','assignment','Atomic rollback','',0,'CANARY_ATOMIC',NULL,'f2c0e300-0000-4000-8000-000000000901');
  RAISE EXCEPTION 'fixture_abort' USING ERRCODE='P0001';
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.mutate_then_fail() TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000001","session_id":"f2c0e300-0000-4000-8000-000000000101"}';
SELECT pg_temp.expect_error('atomic mutation abort is caught exactly',$test$ SELECT pg_temp.mutate_then_fail() $test$,'P0001','fixture_abort');
RESET ROLE;
SELECT pg_temp.check_true('aborted operation leaves no row payload audit or operation',$test$ SELECT NOT EXISTS(SELECT 1 FROM public.session_materials WHERE created_by::text LIKE 'f2c0e300-%' AND title='Atomic rollback') AND NOT EXISTS(SELECT 1 FROM private.material_payloads WHERE body_text='CANARY_ATOMIC') AND NOT EXISTS(SELECT 1 FROM private.material_operations WHERE operation_id='f2c0e300-0000-4000-8000-000000000901') AND (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e300-%' AND action LIKE 'material_%')=32 $test$);

-- Seven assertions per authenticated denial scenario, all SECURITY INVOKER.
CREATE FUNCTION pg_temp.assert_material_denied(p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM pg_temp.check_true(p_label||' base invisible',$test$ SELECT count(*)=0 FROM public.session_materials WHERE session_id='f2c0e300-0000-4000-8000-000000000301' $test$);
  PERFORM pg_temp.expect_error(p_label||' detail denied',$test$ SELECT public.get_admin_material_detail(pg_temp.mid('link1')) $test$,'42501','admin_required');
  PERFORM pg_temp.expect_error(p_label||' create denied',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','intrusion','',0,'',NULL,gen_random_uuid()) $test$,'42501','admin_required');
  PERFORM pg_temp.expect_error(p_label||' update denied',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),4,'intrusion','',0,'draft','',NULL,gen_random_uuid()) $test$,'42501','admin_required');
  PERFORM pg_temp.expect_error(p_label||' delete denied',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','admin_required');
  PERFORM pg_temp.expect_error(p_label||' restore denied',$test$ SELECT public.restore_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','admin_required');
  PERFORM pg_temp.expect_error(p_label||' cached retry denied',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','link','link1','Catalog safe',1,'','https://example.invalid/private?token=CANARY_LINK',pg_temp.mop('link1')) $test$,'42501','admin_required');
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.assert_material_denied(text) TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000002","session_id":"f2c0e300-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.assert_material_denied('student forged metadata');
SELECT pg_temp.expect_error('student direct payload read denied',$test$ SELECT * FROM private.material_payloads $test$,'42501','permission denied for table material_payloads');
SELECT pg_temp.expect_error('student direct material UPDATE denied',$test$ UPDATE public.session_materials SET title='intrusion' WHERE id=pg_temp.mid('link1') $test$,'42501','permission denied for table session_materials');

RESET ROLE;
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000001","session_id":"f2c0e300-0000-4000-8000-000000000101"}';
SELECT pg_temp.assert_material_denied('disabled admin');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e300-0000-4000-8000-000000000001';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('revoked admin device');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e300-0000-4000-8000-000000000001';
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f2c0e300-0000-4000-8000-000000000101';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('expired admin Auth session');
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e300-0000-4000-8000-000000000101';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f2c0e300-0000-4000-8000-000000000101';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('ended admin admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e300-0000-4000-8000-000000000101';
-- Administrators use their own admission, not the student-only active pointer.
-- Preserve a distinct missing-admission case, separate from the ended case above.
CREATE TEMP TABLE phase2m_admission_snapshot ON COMMIT DROP AS
SELECT * FROM private.session_access WHERE session_id='f2c0e300-0000-4000-8000-000000000101'
  AND user_id='f2c0e300-0000-4000-8000-000000000001';
DELETE FROM private.session_access WHERE session_id='f2c0e300-0000-4000-8000-000000000101'
  AND user_id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('nonadmitted admin');
RESET ROLE;
INSERT INTO private.session_access SELECT * FROM pg_temp.phase2m_admission_snapshot;
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('unverified admin');
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=now(),banned_until=now()+interval '1 hour' WHERE id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_material_denied('banned admin');
RESET ROLE;
UPDATE auth.users SET banned_until=NULL WHERE id='f2c0e300-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e300-0000-4000-8000-000000000001","session_id":"f2c0e300-0000-4000-8000-000000000999"}';
SELECT pg_temp.assert_material_denied('missing admin Auth session');

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{"role":"anon"}';
SELECT pg_temp.expect_error('anonymous base SELECT denied',$test$ SELECT * FROM public.session_materials $test$,'42501','permission denied for table session_materials');
SELECT pg_temp.expect_error('anonymous create EXECUTE denied',$test$ SELECT public.create_session_material('f2c0e300-0000-4000-8000-000000000301','file','intrusion','',0,'',NULL,gen_random_uuid()) $test$,'42501','permission denied for function create_session_material');
SELECT pg_temp.expect_error('anonymous detail EXECUTE denied',$test$ SELECT public.get_admin_material_detail(pg_temp.mid('link1')) $test$,'42501','permission denied for function get_admin_material_detail');
SELECT pg_temp.expect_error('anonymous update EXECUTE denied',$test$ SELECT public.update_session_material(pg_temp.mid('link1'),4,'intrusion','',0,'draft','',NULL,gen_random_uuid()) $test$,'42501','permission denied for function update_session_material');
SELECT pg_temp.expect_error('anonymous delete EXECUTE denied',$test$ SELECT public.delete_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','permission denied for function delete_session_material');
SELECT pg_temp.expect_error('anonymous restore EXECUTE denied',$test$ SELECT public.restore_session_material(pg_temp.mid('link1'),4,gen_random_uuid()) $test$,'42501','permission denied for function restore_session_material');
RESET ROLE;
SELECT pg_temp.check_true('all denied calls leave fixtures and operation audit intact',$test$ SELECT (SELECT count(*) FROM public.session_materials WHERE created_by::text LIKE 'f2c0e300-%')=26 AND (SELECT revision FROM public.session_materials WHERE id=pg_temp.mid('link1'))=4 AND (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e300-%')=32 AND (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e300-%' AND action LIKE 'material_%')=32 $test$);

-- Count is enforced separately; a partial execution cannot manufacture a PASS report.
DO $count$ BEGIN
  IF (SELECT count(*) FROM pg_temp.phase2m_results)<>163 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 163 material assertions';
  END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',163,
  'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase2_materials_report
FROM pg_temp.phase2m_results;
ROLLBACK;

-- Preflight-safe cleanup: only tables that predate this migration are referenced.
-- Run separately if the tool returns only the final SELECT and hides the report.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f2c0e300-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f2c0e300-%' OR user_id::text LIKE 'f2c0e300-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f2c0e300-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f2c0e300-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f2c0e300-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e300-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f2c0e300-%' OR created_by::text LIKE 'f2c0e300-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM public.course_sessions WHERE id::text LIKE 'f2c0e300-%' OR created_by::text LIKE 'f2c0e300-%') AS reserved_course_sessions_remaining;
