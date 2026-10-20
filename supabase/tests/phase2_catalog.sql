-- Main executes the whole suite on ONE privileged connection, stop-on-error.
-- Requires deployed 20261019193939_phase2_catalog and existing materials/identity/content/covers.
-- Fixture rollback verification AFTER additive deployment; not atomic schema preflight.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';

CREATE TEMP TABLE catalog_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE catalog_saved(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE catalog_baseline(event_count bigint NOT NULL,operation_count bigint NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.catalog_results,pg_temp.catalog_saved TO authenticated;
GRANT SELECT,INSERT ON pg_temp.catalog_results TO anon;
GRANT SELECT ON pg_temp.catalog_saved TO anon;

CREATE FUNCTION pg_temp.catalog_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.catalog_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.catalog_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.catalog_results VALUES(p_name,'PASS');
END;
$helper$;
-- Query-read helpers must be STABLE: the outer statement must see fixture/page writes.
CREATE FUNCTION pg_temp.catalog_saved(p_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
  SELECT value FROM pg_temp.catalog_saved WHERE key=p_key;
$helper$;
CREATE FUNCTION pg_temp.catalog_keys(p_value jsonb,p_keys text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
  SELECT coalesce(jsonb_typeof(p_value)='object' AND
    (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_value) k)=
    (SELECT array_agg(k ORDER BY k) FROM unnest(p_keys) k),false);
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.catalog_check(text,text),pg_temp.catalog_error(text,text,text,text),
  pg_temp.catalog_saved(text),pg_temp.catalog_keys(jsonb,text[]) TO authenticated,anon;

-- Reserve a searchable namespace without hiding/updating existing academy content.
DO $collision$ BEGIN
  IF EXISTS(SELECT 1 FROM public.courses WHERE strpos(lower(title),'cat4 ')>0
    OR strpos(lower(instructor),'cat4 ')>0 OR strpos(lower(category),'cat4 ')>0
    OR strpos(lower(level),'cat4 ')>0) THEN
    RAISE EXCEPTION 'catalog_fixture_namespace_collision';
  END IF;
END; $collision$;

-- Collision-failing fictional identities only. No real owner is selected for mutation.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f2c0e400-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
  'catalog-'||n::text||'@example.invalid',now(),'{"provider":"email","providers":["email"]}'::jsonb,
  '{"name":"Fictional catalog fixture","role":"admin","is_admin":true}'::jsonb,false,now(),now()
FROM generate_series(1,2) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f2c0e400-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
  ('f2c0e400-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM generate_series(1,2) n;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000001","session_id":"f2c0e400-0000-4000-8000-000000000101"}';
SELECT pg_temp.catalog_check('fixture first user remains student despite forged metadata',$test$ SELECT public.register_device(repeat('a',64),'Catalog admin fixture')->>'role'='student' $test$);
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000002","session_id":"f2c0e400-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.catalog_check('fixture student forged role ignored',$test$ SELECT public.register_device(repeat('b',64),'Catalog student fixture')->>'role'='student' $test$);
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f2c0e400-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000001","session_id":"f2c0e400-0000-4000-8000-000000000101"}';

-- Twenty-five ordered published courses; ties deliberately use ascending UUIDs.
-- Max int32 price/order are genuine valid metadata, not payment/delivery grants.
INSERT INTO public.courses(id,title,description,instructor,category,level,price_piasters,position,status,cover_path)
SELECT ('f2c0e400-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,
  'CAT4 Course '||n::text,CASE WHEN n=23 THEN 'CAT4 description only needle' ELSE 'Catalog fixture description' END,
  CASE WHEN n=24 THEN 'CAT4 Finding Instructor' ELSE 'CAT4 Instructor' END,
  CASE WHEN n=25 THEN 'CAT4 Late' ELSE 'CAT4 Core' END,
  CASE WHEN n=25 THEN 'CAT4 Year2' ELSE 'CAT4 Year1' END,
  CASE WHEN n=25 THEN 2147483647 WHEN n=1 THEN 0 ELSE 10000+n END,
  CASE WHEN n=25 THEN 2147483647 ELSE (n-1)/3 END,'published',
  CASE WHEN n=1 THEN 'f2c0e400-0000-4000-8000-000000000201/f2c0e400-0000-4000-8000-000000000801.png' ELSE NULL END
FROM generate_series(1,25) n;
-- Safe image-reference metadata only: no cover reservation or Storage object is created.
INSERT INTO public.courses(id,title,instructor,category,level,status,deleted_at,position)
VALUES
 ('f2c0e400-0000-4000-8000-000000000226','CAT4 Hidden draft','CAT4 Instructor','CAT4 SecretDraft','CAT4 HiddenYear','draft',NULL,0),
 ('f2c0e400-0000-4000-8000-000000000227','CAT4 Hidden archived','CAT4 Instructor','CAT4 SecretArchived','CAT4 HiddenYear','archived',NULL,0),
 ('f2c0e400-0000-4000-8000-000000000228','CAT4 Hidden deleted','CAT4 Instructor','CAT4 SecretDeleted','CAT4 HiddenYear','archived',now(),0);
INSERT INTO public.courses(id,title,instructor,category,level,status,position)
VALUES
 ('f2c0e400-0000-4000-8000-000000000229','CAT4 rate%literal','CAT4 Instructor','CAT4 Wild','CAT4 Year3','published',100),
 ('f2c0e400-0000-4000-8000-000000000230','CAT4 under_literal','CAT4 Instructor','CAT4 Wild','CAT4 Year3','published',100),
 ('f2c0e400-0000-4000-8000-000000000231',E'CAT4 slash\\literal','CAT4 Instructor','CAT4 Wild','CAT4 Year3','published',100),
 ('f2c0e400-0000-4000-8000-000000000232','CAT4 plainXliteral','CAT4 Instructor','CAT4 Wild','CAT4 Year3','published',100);
INSERT INTO public.course_sessions(id,course_id,session_number,title,description,price_piasters,position,status,is_free_preview)
SELECT ('f2c0e400-0000-4000-8000-'||lpad((500+n)::text,12,'0'))::uuid,
  'f2c0e400-0000-4000-8000-000000000201',CASE WHEN n=25 THEN 2147483647 WHEN n=24 THEN 1 ELSE 100-n END,
  'CAT4 Session '||n::text,'Safe session description',CASE WHEN n=25 THEN 2147483647 ELSE 0 END,
  CASE WHEN n=25 THEN 2147483647 ELSE (n-1)/3 END,'published',n=1
FROM generate_series(1,25) n;
INSERT INTO public.course_sessions(id,course_id,session_number,title,status,deleted_at)
VALUES
 ('f2c0e400-0000-4000-8000-000000000526','f2c0e400-0000-4000-8000-000000000201',126,'CAT4 Draft session','draft',NULL),
 ('f2c0e400-0000-4000-8000-000000000527','f2c0e400-0000-4000-8000-000000000201',127,'CAT4 Archived session','archived',NULL),
 ('f2c0e400-0000-4000-8000-000000000528','f2c0e400-0000-4000-8000-000000000201',128,'CAT4 Deleted session','archived',now()),
 ('f2c0e400-0000-4000-8000-000000000531','f2c0e400-0000-4000-8000-000000000226',1,'CAT4 Hidden-parent session','published',NULL),
 ('f2c0e400-0000-4000-8000-000000000532','f2c0e400-0000-4000-8000-000000000227',1,'CAT4 Hidden-parent session','published',NULL),
 ('f2c0e400-0000-4000-8000-000000000533','f2c0e400-0000-4000-8000-000000000228',1,'CAT4 Hidden-parent session','published',NULL);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.catalog_saved VALUES
 ('assignment',public.create_session_material('f2c0e400-0000-4000-8000-000000000501','assignment','Catalog assignment fixture','Safe summary',0,'CAT4_PRIVATE_BODY_CANARY',NULL,'f2c0e400-0000-4000-8000-000000000901')),
 ('link',public.create_session_material('f2c0e400-0000-4000-8000-000000000501','link','Catalog link fixture','Safe summary',1,'','https://example.invalid/?token=CAT4_PRIVATE_URL_CANARY','f2c0e400-0000-4000-8000-000000000902'));
SELECT public.update_session_material((pg_temp.catalog_saved('assignment')->>'id')::uuid,1,'Catalog assignment fixture','Safe summary',0,'published','CAT4_PRIVATE_BODY_CANARY',NULL,'f2c0e400-0000-4000-8000-000000000903');
SELECT public.update_session_material((pg_temp.catalog_saved('link')->>'id')::uuid,1,'Catalog link fixture','Safe summary',1,'published','','https://example.invalid/?token=CAT4_PRIVATE_URL_CANARY','f2c0e400-0000-4000-8000-000000000904');
RESET ROLE;
INSERT INTO pg_temp.catalog_baseline SELECT
  (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e400-%'),
  (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e400-%');

SELECT pg_temp.catalog_check('exact four catalog functions stable invoker empty search path',$test$ SELECT count(*)=4 AND bool_and(provolatile='s' AND NOT prosecdef AND proconfig=ARRAY['search_path=""']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('list_catalog_courses','list_catalog_sessions','get_catalog_course','get_catalog_filters') $test$);
SELECT pg_temp.catalog_check('only authenticated has client catalog EXECUTE',$test$ SELECT count(*)=4 AND bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('list_catalog_courses','list_catalog_sessions','get_catalog_course','get_catalog_filters') $test$);
SELECT pg_temp.catalog_check('default argument counts match contract',$test$ SELECT (SELECT pronargdefaults=6 FROM pg_proc WHERE oid='public.list_catalog_courses(text,text,text,integer,uuid,integer)'::regprocedure) AND (SELECT pronargdefaults=3 FROM pg_proc WHERE oid='public.list_catalog_sessions(uuid,integer,uuid,integer)'::regprocedure) $test$);
SELECT pg_temp.catalog_check('material base still admin-only policy',$test$ SELECT count(*)=1 AND bool_and(cmd='SELECT' AND qual LIKE '%private.is_admin()%') FROM pg_policies WHERE schemaname='public' AND tablename='session_materials' $test$);
SELECT pg_temp.catalog_check('private material tables remain closed',$test$ SELECT NOT has_table_privilege('authenticated','private.material_payloads','SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('authenticated','private.material_operations','SELECT,INSERT,UPDATE,DELETE') $test$);
SELECT pg_temp.catalog_check('material storage and receipt buckets remain private',$test$ SELECT count(*)=3 AND bool_and(NOT public) FROM storage.buckets WHERE id IN ('course-materials','assignment-submissions','payment-receipts') $test$);
SELECT pg_temp.catalog_check('only existing cover Storage policies allowed',$test$ SELECT NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname NOT IN ('course_covers_read','course_covers_insert','course_covers_delete')) $test$);

SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_check('admin authoring still sees fictional drafts',$test$ SELECT count(*)=3 FROM public.courses WHERE id IN ('f2c0e400-0000-4000-8000-000000000226','f2c0e400-0000-4000-8000-000000000227','f2c0e400-0000-4000-8000-000000000228') $test$);
SELECT pg_temp.catalog_check('admin catalog excludes drafts archives deleted',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Hidden')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('admin draft details unavailable',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000226') IS NULL $test$);
SELECT pg_temp.catalog_check('admin archived details unavailable',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000227') IS NULL $test$);
SELECT pg_temp.catalog_check('admin deleted details unavailable',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000228') IS NULL $test$);
SELECT pg_temp.catalog_check('admin draft parent outline empty',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000226')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('admin archived parent outline empty',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000227')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('admin deleted parent outline empty',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000228')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('admin outline excludes hidden child sessions',$test$ SELECT jsonb_array_length(public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>50)->'items')=25 $test$);
SELECT pg_temp.catalog_check('admin filters exclude hidden categories',$test$ SELECT NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(public.get_catalog_filters()->'categories') v WHERE v IN ('CAT4 SecretDraft','CAT4 SecretArchived','CAT4 SecretDeleted')) $test$);

SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000002","session_id":"f2c0e400-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
INSERT INTO pg_temp.catalog_saved VALUES ('courses1',public.list_catalog_courses(p_search=>'CAT4 Course'));
INSERT INTO pg_temp.catalog_saved VALUES ('courses2',public.list_catalog_courses(p_search=>'CAT4 Course',
  p_after_position=>(pg_temp.catalog_saved('courses1')->'next_cursor'->>'position')::integer,
  p_after_id=>(pg_temp.catalog_saved('courses1')->'next_cursor'->>'id')::uuid));
INSERT INTO pg_temp.catalog_saved VALUES ('sessions1',public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201'));
INSERT INTO pg_temp.catalog_saved VALUES ('sessions2',public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',
  p_after_position=>(pg_temp.catalog_saved('sessions1')->'next_cursor'->>'position')::integer,
  p_after_id=>(pg_temp.catalog_saved('sessions1')->'next_cursor'->>'id')::uuid));
SELECT pg_temp.catalog_check('student default empty search accepted and page bounded',$test$ SELECT jsonb_array_length(public.list_catalog_courses()->'items')=20 $test$);
SELECT pg_temp.catalog_check('student first course page exactly twenty and has more',$test$ SELECT jsonb_array_length(pg_temp.catalog_saved('courses1')->'items')=20 AND (pg_temp.catalog_saved('courses1')->>'has_more')::boolean $test$);
SELECT pg_temp.catalog_check('course next cursor is last returned not sentinel',$test$ SELECT pg_temp.catalog_saved('courses1')->'next_cursor'=jsonb_build_object('position',(pg_temp.catalog_saved('courses1')->'items'->19->>'position')::integer,'id',pg_temp.catalog_saved('courses1')->'items'->19->>'id') AND pg_temp.catalog_saved('courses1')->'items'->19->>'id'='f2c0e400-0000-4000-8000-000000000220' $test$);
SELECT pg_temp.catalog_check('second course page five terminal cursor null',$test$ SELECT jsonb_array_length(pg_temp.catalog_saved('courses2')->'items')=5 AND pg_temp.catalog_saved('courses2')->'has_more'='false'::jsonb AND pg_temp.catalog_saved('courses2')->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.catalog_check('course pages have twenty five unique fixture identities',$test$ SELECT count(*)=25 AND count(DISTINCT item->>'id')=25 FROM (SELECT jsonb_array_elements(pg_temp.catalog_saved('courses1')->'items') item UNION ALL SELECT jsonb_array_elements(pg_temp.catalog_saved('courses2')->'items')) x $test$);
SELECT pg_temp.catalog_check('course tie UUIDs ascending',$test$ SELECT pg_temp.catalog_saved('courses1')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000201' AND pg_temp.catalog_saved('courses1')->'items'->1->>'id'='f2c0e400-0000-4000-8000-000000000202' AND pg_temp.catalog_saved('courses1')->'items'->2->>'id'='f2c0e400-0000-4000-8000-000000000203' $test$);
SELECT pg_temp.catalog_check('course exact page size terminal has no cursor',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 Course',p_limit=>25)->'items')=25 AND public.list_catalog_courses(p_search=>'CAT4 Course',p_limit=>25)->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.catalog_check('limit one and limit fifty accepted',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 Course',p_limit=>1)->'items')=1 AND jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 Course',p_limit=>50)->'items')=25 $test$);
SELECT pg_temp.catalog_check('valid cursor after final course yields empty envelope',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course',p_after_position=>2147483647,p_after_id=>'f2c0e400-0000-4000-8000-000000000999')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('course envelopes exact allowlist',$test$ SELECT pg_temp.catalog_keys(pg_temp.catalog_saved('courses1'),ARRAY['items','has_more','next_cursor']) AND pg_temp.catalog_keys(pg_temp.catalog_saved('courses1')->'next_cursor',ARRAY['position','id']) $test$);
SELECT pg_temp.catalog_check('course items exact allowlist',$test$ SELECT bool_and(pg_temp.catalog_keys(item,ARRAY['id','title','description','instructor','category','level','price_piasters','position','cover_path'])) FROM jsonb_array_elements(pg_temp.catalog_saved('courses1')->'items') item $test$);
SELECT pg_temp.catalog_check('course detail exact allowlist and list parity',$test$ SELECT pg_temp.catalog_keys(public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201'),ARRAY['id','title','description','instructor','category','level','price_piasters','position','cover_path']) AND public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201')=pg_temp.catalog_saved('courses1')->'items'->0 $test$);
SELECT pg_temp.catalog_check('nullable covers remain JSON null',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000202')->'cover_path'='null'::jsonb $test$);
SELECT pg_temp.catalog_check('cover reference remains course scoped PNG metadata',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201')->>'cover_path'='f2c0e400-0000-4000-8000-000000000201/f2c0e400-0000-4000-8000-000000000801.png' $test$);
SELECT pg_temp.catalog_check('zero price returned without ownership claim',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201')->'price_piasters'='0'::jsonb AND NOT (public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201') ?| ARRAY['owned','available','can_play','entitlement']) $test$);
SELECT pg_temp.catalog_check('int32 maximum course price and position preserved',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000225')->'price_piasters'='2147483647'::jsonb AND public.get_catalog_course('f2c0e400-0000-4000-8000-000000000225')->'position'='2147483647'::jsonb $test$);

SELECT pg_temp.catalog_check('search finds later page title',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course 25')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000225' AND jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 Course 25')->'items')=1 $test$);
SELECT pg_temp.catalog_check('search instructor case insensitive trimmed ASCII space',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>'  cat4 finding instructor  ')->'items')=1 AND public.list_catalog_courses(p_search=>'  cat4 finding instructor  ')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000224' $test$);
SELECT pg_temp.catalog_check('search category finds later page course',$test$ SELECT public.list_catalog_courses(p_search=>'cat4 late')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000225' $test$);
SELECT pg_temp.catalog_check('search does not include description',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 description only needle')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('combined search category level applied before pagination',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course',p_category=>' CAT4 Late ',p_level=>' CAT4 Year2 ')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000225' AND jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 Course',p_category=>' CAT4 Late ',p_level=>' CAT4 Year2 ')->'items')=1 $test$);
SELECT pg_temp.catalog_check('mismatched combined filters empty',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course',p_category=>'CAT4 Late',p_level=>'CAT4 Year1')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('category filters are exact case sensitive',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course',p_category=>'cat4 late')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('blank category and level equal clear filters',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 Course',p_category=>'   ',p_level=>' ')=public.list_catalog_courses(p_search=>'CAT4 Course') $test$);
SELECT pg_temp.catalog_check('space only search equals empty search',$test$ SELECT public.list_catalog_courses(p_search=>'  ')=public.list_catalog_courses() $test$);
SELECT pg_temp.catalog_check('tabs are literal not ASCII-space trim',$test$ SELECT public.list_catalog_courses(p_search=>E'\tCAT4 Course')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('percent wildcard is literal',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 rate%literal')->'items')=1 AND public.list_catalog_courses(p_search=>'CAT4 rate%literal')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000229' $test$);
SELECT pg_temp.catalog_check('percent cannot expand over arbitrary title suffix',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 %literal')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('underscore wildcard is literal',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>'CAT4 under_literal')->'items')=1 AND public.list_catalog_courses(p_search=>'CAT4 under_literal')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000230' $test$);
SELECT pg_temp.catalog_check('underscore cannot expand to arbitrary title character',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4 _')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('backslash is literal',$test$ SELECT jsonb_array_length(public.list_catalog_courses(p_search=>E'CAT4 slash\\literal')->'items')=1 AND public.list_catalog_courses(p_search=>E'CAT4 slash\\literal')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000231' $test$);
SELECT pg_temp.catalog_check('SQL looking search remains literal text',$test$ SELECT public.list_catalog_courses(p_search=>$needle$CAT4 ' OR 1=1 --$needle$)='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('trimmed search maximum length accepted',$test$ SELECT public.list_catalog_courses(p_search=>'  '||repeat('z',100)||'  ')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('trimmed filter maximum length accepted',$test$ SELECT public.list_catalog_courses(p_category=>' '||repeat('z',120)||' ',p_level=>repeat('z',120))='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('filter options exact envelope',$test$ SELECT pg_temp.catalog_keys(public.get_catalog_filters(),ARRAY['categories','levels']) $test$);
SELECT pg_temp.catalog_check('filter options include later page categories and levels',$test$ SELECT (public.get_catalog_filters()->'categories') ? 'CAT4 Late' AND (public.get_catalog_filters()->'levels') ? 'CAT4 Year2' $test$);
SELECT pg_temp.catalog_check('ASCII fixture filter categories C sorted distinct',$test$ SELECT jsonb_agg(v ORDER BY ord)='["CAT4 Core","CAT4 Late","CAT4 Wild"]'::jsonb FROM jsonb_array_elements_text(public.get_catalog_filters()->'categories') WITH ORDINALITY x(v,ord) WHERE left(v,5)='CAT4 ' $test$);
SELECT pg_temp.catalog_check('filter options full published catalog SQL C order',$test$ SELECT public.get_catalog_filters()=jsonb_build_object('categories',coalesce((SELECT jsonb_agg(v ORDER BY v COLLATE "C") FROM (SELECT DISTINCT btrim(category) v FROM public.courses WHERE status='published' AND deleted_at IS NULL) c),'[]'::jsonb),'levels',coalesce((SELECT jsonb_agg(v ORDER BY v COLLATE "C") FROM (SELECT DISTINCT btrim(level) v FROM public.courses WHERE status='published' AND deleted_at IS NULL) l),'[]'::jsonb)) $test$);

SELECT pg_temp.catalog_check('session first page twenty and more',$test$ SELECT jsonb_array_length(pg_temp.catalog_saved('sessions1')->'items')=20 AND pg_temp.catalog_saved('sessions1')->'has_more'='true'::jsonb $test$);
SELECT pg_temp.catalog_check('session cursor last returned not sentinel',$test$ SELECT pg_temp.catalog_saved('sessions1')->'next_cursor'=jsonb_build_object('position',(pg_temp.catalog_saved('sessions1')->'items'->19->>'position')::integer,'id',pg_temp.catalog_saved('sessions1')->'items'->19->>'id') AND pg_temp.catalog_saved('sessions1')->'items'->19->>'id'='f2c0e400-0000-4000-8000-000000000520' $test$);
SELECT pg_temp.catalog_check('session terminal page five no cursor',$test$ SELECT jsonb_array_length(pg_temp.catalog_saved('sessions2')->'items')=5 AND pg_temp.catalog_saved('sessions2')->'has_more'='false'::jsonb AND pg_temp.catalog_saved('sessions2')->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.catalog_check('session pages unique and no hidden identities',$test$ SELECT count(*)=25 AND count(DISTINCT item->>'id')=25 AND bool_and((item->>'id')::uuid<'f2c0e400-0000-4000-8000-000000000526'::uuid) FROM (SELECT jsonb_array_elements(pg_temp.catalog_saved('sessions1')->'items') item UNION ALL SELECT jsonb_array_elements(pg_temp.catalog_saved('sessions2')->'items')) x $test$);
SELECT pg_temp.catalog_check('session order is position UUID not numbering',$test$ SELECT pg_temp.catalog_saved('sessions1')->'items'->0->>'id'='f2c0e400-0000-4000-8000-000000000501' AND pg_temp.catalog_saved('sessions1')->'items'->1->>'id'='f2c0e400-0000-4000-8000-000000000502' AND (pg_temp.catalog_saved('sessions1')->'items'->0->>'session_number')::integer>(pg_temp.catalog_saved('sessions1')->'items'->1->>'session_number')::integer $test$);
SELECT pg_temp.catalog_check('session exact item and envelope allowlists',$test$ SELECT pg_temp.catalog_keys(pg_temp.catalog_saved('sessions1'),ARRAY['items','has_more','next_cursor']) AND bool_and(pg_temp.catalog_keys(item,ARRAY['id','course_id','session_number','title','description','price_piasters','position','is_free_preview'])) FROM jsonb_array_elements(pg_temp.catalog_saved('sessions1')->'items') item $test$);
SELECT pg_temp.catalog_check('preview flag is boolean designation only',$test$ SELECT pg_temp.catalog_saved('sessions1')->'items'->0->'is_free_preview'='true'::jsonb AND NOT (pg_temp.catalog_saved('sessions1')->'items'->0 ?| ARRAY['can_play','owned','playback_url','materials']) $test$);
SELECT pg_temp.catalog_check('session int32 maxima preserved',$test$ SELECT (pg_temp.catalog_saved('sessions2')->'items'->4) @> '{"price_piasters":2147483647,"position":2147483647,"session_number":2147483647}'::jsonb $test$);
SELECT pg_temp.catalog_check('session numbering lower bound one preserved',$test$ SELECT pg_temp.catalog_saved('sessions2')->'items'->3->'session_number'='1'::jsonb $test$);
SELECT pg_temp.catalog_check('session limit one and fifty accepted',$test$ SELECT jsonb_array_length(public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>1)->'items')=1 AND jsonb_array_length(public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>50)->'items')=25 $test$);
SELECT pg_temp.catalog_check('session exact boundary terminal cursor null',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>25)->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.catalog_check('session cursor beyond end empty',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',2147483647,'f2c0e400-0000-4000-8000-000000000999')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('unknown parent detail null',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000999') IS NULL $test$);
SELECT pg_temp.catalog_check('unknown parent outline empty envelope',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000999')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.catalog_check('student draft archived deleted outlines all empty',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000226')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb AND public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000227')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb AND public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000228')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);

-- Invalid-input validation is exercised only with a genuinely active admitted user.
SELECT pg_temp.catalog_error('explicit null search invalid',$test$ SELECT public.list_catalog_courses(p_search=>NULL) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('search over one hundred invalid',$test$ SELECT public.list_catalog_courses(p_search=>repeat('x',101)) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('category over one hundred twenty invalid',$test$ SELECT public.list_catalog_courses(p_category=>repeat('x',121)) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('level over one hundred twenty invalid',$test$ SELECT public.list_catalog_courses(p_level=>repeat('x',121)) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course null limit invalid',$test$ SELECT public.list_catalog_courses(p_limit=>NULL) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course zero limit invalid',$test$ SELECT public.list_catalog_courses(p_limit=>0) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course fifty one limit invalid',$test$ SELECT public.list_catalog_courses(p_limit=>51) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course position without UUID invalid',$test$ SELECT public.list_catalog_courses(p_after_position=>0) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course UUID without position invalid',$test$ SELECT public.list_catalog_courses(p_after_id=>'f2c0e400-0000-4000-8000-000000000201') $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('course negative cursor invalid',$test$ SELECT public.list_catalog_courses(p_after_position=>-1,p_after_id=>'f2c0e400-0000-4000-8000-000000000201') $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('detail null UUID invalid',$test$ SELECT public.get_catalog_course(NULL) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline null course UUID invalid',$test$ SELECT public.list_catalog_sessions(NULL) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline null limit invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>NULL) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline zero limit invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>0) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline fifty one limit invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>51) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline position without UUID invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_after_position=>0) $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline UUID without position invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_after_id=>'f2c0e400-0000-4000-8000-000000000501') $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_error('outline negative cursor invalid',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',-1,'f2c0e400-0000-4000-8000-000000000501') $test$,'22023','invalid_catalog_input');
SELECT pg_temp.catalog_check('published material descriptors still invisible to student',$test$ SELECT count(*)=0 FROM public.session_materials WHERE session_id='f2c0e400-0000-4000-8000-000000000501' $test$);
SELECT pg_temp.catalog_error('student private material payload read denied',$test$ SELECT * FROM private.material_payloads $test$,'42501','permission denied for table material_payloads');
SELECT pg_temp.catalog_error('student admin material detail denied',$test$ SELECT public.get_admin_material_detail((pg_temp.catalog_saved('assignment')->>'id')::uuid) $test$,'42501','admin_required');
SELECT pg_temp.catalog_error('student course authoring denied',$test$ INSERT INTO public.courses(title,instructor,category,level) VALUES('forged','forged','forged','forged') $test$,'42501','new row violates row-level security policy for table "courses"');
SELECT pg_temp.catalog_check('student course UPDATE remains RLS filtered',$test$ WITH changed AS (UPDATE public.courses SET title='Intrusion' WHERE id='f2c0e400-0000-4000-8000-000000000201' RETURNING id) SELECT count(*)=0 FROM changed $test$);
SELECT pg_temp.catalog_check('student session UPDATE remains RLS filtered',$test$ WITH changed AS (UPDATE public.course_sessions SET title='Intrusion' WHERE id='f2c0e400-0000-4000-8000-000000000501' RETURNING id) SELECT count(*)=0 FROM changed $test$);
SELECT pg_temp.catalog_check('catalog responses never contain material payload canaries',$test$ SELECT public.list_catalog_courses(p_search=>'CAT4',p_limit=>50)::text NOT LIKE '%CAT4_PRIVATE_%' AND public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201')::text NOT LIKE '%CAT4_PRIVATE_%' AND public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>50)::text NOT LIKE '%CAT4_PRIVATE_%' AND public.get_catalog_filters()::text NOT LIKE '%CAT4_PRIVATE_%' $test$);
RESET ROLE;
SELECT pg_temp.catalog_check('catalog reads have no audit or operation side effects',$test$ SELECT (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e400-%')=event_count AND (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e400-%')=operation_count FROM pg_temp.catalog_baseline $test$);

-- Published-only predicate is rechecked on every call after parent lifecycle changes.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000001","session_id":"f2c0e400-0000-4000-8000-000000000101"}';
UPDATE public.courses SET status='archived' WHERE id='f2c0e400-0000-4000-8000-000000000201';
SELECT pg_temp.catalog_check('archiving formerly visible parent hides admin outline immediately',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201') IS NULL AND public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
UPDATE public.courses SET deleted_at=now() WHERE id='f2c0e400-0000-4000-8000-000000000201';
SELECT pg_temp.catalog_check('deleting formerly visible parent hides all outlines',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
UPDATE public.courses SET deleted_at=NULL WHERE id='f2c0e400-0000-4000-8000-000000000201';
SELECT pg_temp.catalog_check('restored draft parent stays unavailable',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201') IS NULL AND public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
UPDATE public.courses SET status='published' WHERE id='f2c0e400-0000-4000-8000-000000000201';
SELECT pg_temp.catalog_check('explicit republication restores published outline only',$test$ SELECT jsonb_array_length(public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201',p_limit=>50)->'items')=25 $test$);
RESET ROLE;
-- Privileged failed constraint probes alter only fixture rows and roll back inside helpers.
SELECT pg_temp.catalog_error('image reference constraint rejects arbitrary URL',$test$ UPDATE public.courses SET cover_path='https://example.invalid/paid.pdf' WHERE id='f2c0e400-0000-4000-8000-000000000201' $test$,'23514','new row for relation "courses" violates check constraint "courses_cover_path_check"');
SELECT pg_temp.catalog_error('negative authoritative course price denied',$test$ UPDATE public.courses SET price_piasters=-1 WHERE id='f2c0e400-0000-4000-8000-000000000201' $test$,'23514','new row for relation "courses" violates check constraint "courses_price_piasters_check"');
SELECT pg_temp.catalog_error('negative authoritative course position denied',$test$ UPDATE public.courses SET position=-1 WHERE id='f2c0e400-0000-4000-8000-000000000201' $test$,'23514','new row for relation "courses" violates check constraint "courses_position_check"');
SELECT pg_temp.catalog_error('zero authoritative session number denied',$test$ UPDATE public.course_sessions SET session_number=0 WHERE id='f2c0e400-0000-4000-8000-000000000501' $test$,'23514','new row for relation "course_sessions" violates check constraint "course_sessions_session_number_check"');
SELECT pg_temp.catalog_error('int32 course price overflow denied',$test$ UPDATE public.courses SET price_piasters=2147483648 WHERE id='f2c0e400-0000-4000-8000-000000000201' $test$,'22003','integer out of range');
SELECT pg_temp.catalog_error('negative authoritative session price denied',$test$ UPDATE public.course_sessions SET price_piasters=-1 WHERE id='f2c0e400-0000-4000-8000-000000000501' $test$,'23514','new row for relation "course_sessions" violates check constraint "course_sessions_price_piasters_check"');
SELECT pg_temp.catalog_error('negative authoritative session position denied',$test$ UPDATE public.course_sessions SET position=-1 WHERE id='f2c0e400-0000-4000-8000-000000000501' $test$,'23514','new row for relation "course_sessions" violates check constraint "course_sessions_position_check"');
SELECT pg_temp.catalog_error('int32 session number overflow denied',$test$ UPDATE public.course_sessions SET session_number=2147483648 WHERE id='f2c0e400-0000-4000-8000-000000000501' $test$,'22003','integer out of range');

-- Four assertions per invalid admission: never disguise denial as empty catalog data.
CREATE FUNCTION pg_temp.catalog_denied(p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM pg_temp.catalog_error(p_label||' courses denied',$test$ SELECT public.list_catalog_courses() $test$,'42501','catalog_access_required');
  PERFORM pg_temp.catalog_error(p_label||' detail denied',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201') $test$,'42501','catalog_access_required');
  PERFORM pg_temp.catalog_error(p_label||' outline denied',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201') $test$,'42501','catalog_access_required');
  PERFORM pg_temp.catalog_error(p_label||' filters denied',$test$ SELECT public.get_catalog_filters() $test$,'42501','catalog_access_required');
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.catalog_denied(text) TO authenticated;
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e400-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('disabled administrator');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e400-0000-4000-8000-000000000001';
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000002","session_id":"f2c0e400-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.catalog_denied('disabled student');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('revoked student device');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f2c0e400-0000-4000-8000-000000000102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('expired student Auth session');
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e400-0000-4000-8000-000000000102';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f2c0e400-0000-4000-8000-000000000102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('ended student admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e400-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id=NULL WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('nonadmitted student');
RESET ROLE;
UPDATE private.account_access SET active_session_id='f2c0e400-0000-4000-8000-000000000102' WHERE user_id='f2c0e400-0000-4000-8000-000000000002';
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('unverified student');
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=now(),banned_until=now()+interval '1 hour' WHERE id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.catalog_denied('banned student');
RESET ROLE;
UPDATE auth.users SET banned_until=NULL WHERE id='f2c0e400-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e400-0000-4000-8000-000000000002","session_id":"f2c0e400-0000-4000-8000-000000000999"}';
SELECT pg_temp.catalog_denied('missing student Auth session');
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT pg_temp.catalog_denied('authenticated role without identity');

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{"role":"anon"}';
SELECT pg_temp.catalog_error('anonymous courses EXECUTE denied',$test$ SELECT public.list_catalog_courses() $test$,'42501','permission denied for function list_catalog_courses');
SELECT pg_temp.catalog_error('anonymous detail EXECUTE denied',$test$ SELECT public.get_catalog_course('f2c0e400-0000-4000-8000-000000000201') $test$,'42501','permission denied for function get_catalog_course');
SELECT pg_temp.catalog_error('anonymous outlines EXECUTE denied',$test$ SELECT public.list_catalog_sessions('f2c0e400-0000-4000-8000-000000000201') $test$,'42501','permission denied for function list_catalog_sessions');
SELECT pg_temp.catalog_error('anonymous filters EXECUTE denied',$test$ SELECT public.get_catalog_filters() $test$,'42501','permission denied for function get_catalog_filters');
RESET ROLE;
SELECT pg_temp.catalog_check('fixture content and role grants preserved after denials',$test$ SELECT (SELECT count(*) FROM public.courses WHERE created_by='f2c0e400-0000-4000-8000-000000000001')=32 AND (SELECT count(*) FROM public.course_sessions WHERE created_by='f2c0e400-0000-4000-8000-000000000001')=31 AND (SELECT role='student' FROM private.account_access WHERE user_id='f2c0e400-0000-4000-8000-000000000002') AND (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e400-%')=4 $test$);

DO $count$ BEGIN
  IF (SELECT count(*) FROM pg_temp.catalog_results)<>155 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 155 catalog assertions';
  END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',155,
  'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase2_catalog_report
FROM pg_temp.catalog_results;
ROLLBACK;

-- Read-only cleanup proof against reserved identifiers, never by owner/global deletion.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f2c0e400-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f2c0e400-%' OR user_id::text LIKE 'f2c0e400-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f2c0e400-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f2c0e400-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f2c0e400-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e400-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f2c0e400-%' OR created_by::text LIKE 'f2c0e400-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM public.course_sessions WHERE id::text LIKE 'f2c0e400-%' OR created_by::text LIKE 'f2c0e400-%') AS reserved_course_sessions_remaining,
 (SELECT count(*) FROM public.session_materials WHERE created_by::text LIKE 'f2c0e400-%' OR session_id='f2c0e400-0000-4000-8000-000000000501') AS reserved_materials_remaining,
 (SELECT count(*) FROM private.material_operations WHERE actor_id::text LIKE 'f2c0e400-%') AS reserved_operations_remaining,
 (SELECT count(*) FROM private.material_payloads WHERE body_text='CAT4_PRIVATE_BODY_CANARY' OR target_url='https://example.invalid/?token=CAT4_PRIVATE_URL_CANARY') AS reserved_payloads_remaining,
 (SELECT count(*) FROM storage.objects WHERE name LIKE 'f2c0e400-%') AS reserved_storage_objects_remaining;
