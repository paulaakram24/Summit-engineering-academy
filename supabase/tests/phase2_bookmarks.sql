-- One privileged connection, whole file, stop-on-error. Main owns execution.
-- Atomic preflight: insert new migration after BEGIN, retain this ROLLBACK.
-- No owner data, Auth API, Storage objects, purchases or entitlement writes.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE bookmark_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE bookmark_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.bookmark_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.bookmark_replies TO authenticated;

CREATE FUNCTION pg_temp.bookmark_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.bookmark_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.bookmark_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.bookmark_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.bookmark_claim(p_user integer) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
    'sub','f2c0e500-0000-4000-8000-'||lpad(p_user::text,12,'0'),
    'session_id','f2c0e500-0000-4000-8000-'||lpad((100+p_user)::text,12,'0'),
    'user_metadata',jsonb_build_object('role','admin','is_admin',true))::text,true);
END;
$helper$;
CREATE FUNCTION pg_temp.bookmark_reply(p_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
  SELECT value FROM pg_temp.bookmark_replies WHERE key=p_key;
$helper$;
CREATE FUNCTION pg_temp.bookmark_keys(p_value jsonb,p_keys text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
  SELECT coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_value) k)=
    (SELECT array_agg(k ORDER BY k) FROM unnest(p_keys) k),false);
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.bookmark_check(text,text),pg_temp.bookmark_error(text,text,text,text),
  pg_temp.bookmark_claim(integer),pg_temp.bookmark_reply(text),pg_temp.bookmark_keys(jsonb,text[]) TO authenticated,anon;

-- Plain INSERTs abort on fixture collisions; never upsert or impersonate the owner.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f2c0e500-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
  'bookmarks-'||n::text||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
  '{"name":"Fictional bookmarks fixture","role":"admin","is_admin":true}'::jsonb,false,now(),now()
FROM generate_series(1,3) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f2c0e500-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
  ('f2c0e500-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM generate_series(1,3) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_claim(1);
SELECT public.register_device(repeat('a',64),'Bookmark admin fixture');
SELECT pg_temp.bookmark_claim(2);
SELECT public.register_device(repeat('b',64),'Bookmark student fixture');
SELECT pg_temp.bookmark_claim(3);
SELECT public.register_device(repeat('c',64),'Bookmark other student fixture');
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f2c0e500-0000-4000-8000-000000000001';
SELECT pg_temp.bookmark_claim(1);
INSERT INTO public.courses(id,title,description,instructor,category,level,price_piasters,position,status)
SELECT ('f2c0e500-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,'Bookmark fixture '||n::text,
  'Safe catalog description','Fictional instructor','Engineering','1',10000+n,
  CASE WHEN n>25 THEN 0 ELSE (n-1)/3 END,'published'
FROM generate_series(1,29) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_claim(2);
SELECT pg_temp.bookmark_check('forged admin metadata does not change student authority',$test$ SELECT public.get_access_context()->>'role'='student' AND NOT private.is_admin() $test$);
SELECT pg_temp.bookmark_check('initial published state false revision zero exact',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201')='{"course_id":"f2c0e500-0000-4000-8000-000000000201","saved":false,"revision":0}'::jsonb $test$);
SELECT pg_temp.bookmark_check('initial list empty terminal envelope',$test$ SELECT public.list_saved_courses()='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
INSERT INTO pg_temp.bookmark_replies
SELECT 'saved_'||n::text,public.set_course_bookmark(('f2c0e500-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,true,0)
FROM generate_series(1,28) n;
SELECT pg_temp.bookmark_check('save exact state fields revision one',$test$ SELECT pg_temp.bookmark_reply('saved_1')='{"course_id":"f2c0e500-0000-4000-8000-000000000201","saved":true,"revision":1}'::jsonb $test$);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',true,1);
SELECT pg_temp.bookmark_check('same desired save advances revision without duplicate',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201')->>'revision'='2' AND (SELECT count(*) FROM private.course_bookmarks WHERE course_id='f2c0e500-0000-4000-8000-000000000201')=1 $test$);
SELECT pg_temp.bookmark_error('same request retry with stale revision conflicts',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',true,1) $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.bookmark_claim(3);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',true,0);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000228',true,0);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000229',true,0);
RESET ROLE;
-- Hide three saved rows at the front of the sort; filtering must precede lookahead.
SELECT pg_temp.bookmark_claim(1);
UPDATE public.courses SET status='draft' WHERE id='f2c0e500-0000-4000-8000-000000000226';
UPDATE public.courses SET status='archived' WHERE id='f2c0e500-0000-4000-8000-000000000227';
UPDATE public.courses SET deleted_at=now() WHERE id='f2c0e500-0000-4000-8000-000000000228';
SELECT pg_temp.bookmark_check('RLS enabled and owner FK restrictive no parent FK',$test$ SELECT (SELECT relrowsecurity FROM pg_class WHERE oid='private.course_bookmarks'::regclass) AND (SELECT count(*)=1 AND bool_and(confrelid='auth.users'::regclass AND confdeltype='r') FROM pg_constraint WHERE conrelid='private.course_bookmarks'::regclass AND contype='f') $test$);
SELECT pg_temp.bookmark_check('owner course key and course FK lookup index',$test$ SELECT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.course_bookmarks'::regclass AND contype='p') AND EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='private' AND tablename='course_bookmarks' AND indexdef LIKE '%(course_id)%') $test$);
SELECT pg_temp.bookmark_check('exact three policies no admin bypass or delete policy',$test$ SELECT count(*)=3 AND bool_and(cmd IN ('SELECT','INSERT','UPDATE') AND roles=ARRAY['authenticated']::name[] AND coalesce(qual,'') NOT LIKE '%is_admin%' AND coalesce(with_check,'') NOT LIKE '%is_admin%') FROM pg_policies WHERE schemaname='private' AND tablename='course_bookmarks' $test$);
SELECT pg_temp.bookmark_check('narrow columns grants no delete truncate ownership update',$test$ SELECT has_table_privilege('authenticated','private.course_bookmarks','SELECT') AND has_column_privilege('authenticated','private.course_bookmarks','saved','UPDATE') AND has_column_privilege('authenticated','private.course_bookmarks','revision','UPDATE') AND has_column_privilege('authenticated','private.course_bookmarks','owner_id','INSERT') AND NOT has_column_privilege('authenticated','private.course_bookmarks','owner_id','UPDATE') AND NOT has_column_privilege('authenticated','private.course_bookmarks','revision','INSERT') AND NOT has_table_privilege('authenticated','private.course_bookmarks','DELETE,TRUNCATE') AND NOT has_table_privilege('anon','private.course_bookmarks','SELECT,INSERT,UPDATE,DELETE') $test$);
SELECT pg_temp.bookmark_check('three RPC invoker volatility and empty search path',$test$ SELECT count(*)=3 AND bool_and(NOT prosecdef AND proconfig=ARRAY['search_path=""'] AND provolatile=CASE WHEN proname='set_course_bookmark' THEN 'v'::char ELSE 's'::char END) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND proname IN ('get_course_bookmark','set_course_bookmark','list_saved_courses') $test$);
SELECT pg_temp.bookmark_check('only authenticated client EXECUTE no PUBLIC default',$test$ SELECT count(*)=3 AND bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND proname IN ('get_course_bookmark','set_course_bookmark','list_saved_courses') $test$);

SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_claim(1);
SELECT pg_temp.bookmark_check('admin cannot inspect student saved references',$test$ SELECT count(*)=0 FROM private.course_bookmarks WHERE owner_id='f2c0e500-0000-4000-8000-000000000002' $test$);
SELECT pg_temp.bookmark_check('admin own state never borrows another account save',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201')->'saved'='false'::jsonb AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201')->'revision'='0'::jsonb $test$);
SELECT pg_temp.bookmark_error('admin cannot insert another owner reference',$test$ INSERT INTO private.course_bookmarks(owner_id,course_id) VALUES('f2c0e500-0000-4000-8000-000000000002','f2c0e500-0000-4000-8000-000000000229') $test$,'42501','new row violates row-level security policy for table "course_bookmarks"');
SELECT pg_temp.bookmark_check('admin cannot update another account saved state',$test$ WITH changed AS (UPDATE private.course_bookmarks SET saved=false,revision=revision+1 WHERE owner_id='f2c0e500-0000-4000-8000-000000000002' RETURNING course_id) SELECT count(*)=0 FROM changed $test$);
SELECT pg_temp.bookmark_check('admin hidden draft archive deleted reads null',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000226') IS NULL AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000227') IS NULL AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000228') IS NULL $test$);
SELECT pg_temp.bookmark_error('admin cannot save draft despite authoring privileges',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000226',true,0) $test$,'42501','bookmark_course_unavailable');
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000202',true,0);
SELECT pg_temp.bookmark_check('admin may save only for own identity',$test$ SELECT jsonb_array_length(public.list_saved_courses()->'items')=1 AND public.list_saved_courses()->'items'->0->>'id'='f2c0e500-0000-4000-8000-000000000202' $test$);

SELECT pg_temp.bookmark_claim(2);
INSERT INTO pg_temp.bookmark_replies VALUES('page1',public.list_saved_courses());
INSERT INTO pg_temp.bookmark_replies VALUES('page2',public.list_saved_courses(
  (pg_temp.bookmark_reply('page1')->'next_cursor'->>'position')::integer,
  (pg_temp.bookmark_reply('page1')->'next_cursor'->>'id')::uuid));
SELECT pg_temp.bookmark_check('first page twenty after hidden filtering with lookahead',$test$ SELECT jsonb_array_length(pg_temp.bookmark_reply('page1')->'items')=20 AND pg_temp.bookmark_reply('page1')->'has_more'='true'::jsonb $test$);
SELECT pg_temp.bookmark_check('next cursor last returned not lookahead sentinel',$test$ SELECT pg_temp.bookmark_reply('page1')->'next_cursor'=jsonb_build_object('position',(pg_temp.bookmark_reply('page1')->'items'->19->>'position')::integer,'id',pg_temp.bookmark_reply('page1')->'items'->19->>'id') AND pg_temp.bookmark_reply('page1')->'items'->19->>'id'='f2c0e500-0000-4000-8000-000000000220' $test$);
SELECT pg_temp.bookmark_check('last page five and terminal cursor null',$test$ SELECT jsonb_array_length(pg_temp.bookmark_reply('page2')->'items')=5 AND pg_temp.bookmark_reply('page2')->'has_more'='false'::jsonb AND pg_temp.bookmark_reply('page2')->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.bookmark_check('pages unique no hidden or other account course',$test$ SELECT count(*)=25 AND count(DISTINCT item->>'id')=25 AND bool_and((item->>'id')::uuid<'f2c0e500-0000-4000-8000-000000000226'::uuid) FROM (SELECT jsonb_array_elements(pg_temp.bookmark_reply('page1')->'items') item UNION ALL SELECT jsonb_array_elements(pg_temp.bookmark_reply('page2')->'items')) x $test$);
SELECT pg_temp.bookmark_check('equal positions sort UUID ascending',$test$ SELECT pg_temp.bookmark_reply('page1')->'items'->0->>'id'='f2c0e500-0000-4000-8000-000000000201' AND pg_temp.bookmark_reply('page1')->'items'->1->>'id'='f2c0e500-0000-4000-8000-000000000202' $test$);
SELECT pg_temp.bookmark_check('saved page and course fields exact catalog projection',$test$ SELECT pg_temp.bookmark_keys(pg_temp.bookmark_reply('page1'),ARRAY['items','has_more','next_cursor']) AND bool_and(pg_temp.bookmark_keys(item,ARRAY['id','title','description','instructor','category','level','price_piasters','position','cover_path'])) FROM jsonb_array_elements(pg_temp.bookmark_reply('page1')->'items') item $test$);
SELECT pg_temp.bookmark_check('saved course projection equals published catalog detail',$test$ SELECT pg_temp.bookmark_reply('page1')->'items'->0=public.get_catalog_course('f2c0e500-0000-4000-8000-000000000201') $test$);
SELECT pg_temp.bookmark_check('exact limit terminal and max fifty supported',$test$ SELECT public.list_saved_courses(p_limit=>25)->'next_cursor'='null'::jsonb AND jsonb_array_length(public.list_saved_courses(p_limit=>50)->'items')=25 AND jsonb_array_length(public.list_saved_courses(p_limit=>1)->'items')=1 $test$);
SELECT pg_temp.bookmark_check('cursor beyond end empty terminal envelope',$test$ SELECT public.list_saved_courses(2147483647,'f2c0e500-0000-4000-8000-000000000999')='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
SELECT pg_temp.bookmark_check('student cannot inspect or edit other saved references',$test$ WITH changed AS (UPDATE private.course_bookmarks SET saved=false,revision=revision+1 WHERE owner_id='f2c0e500-0000-4000-8000-000000000003' RETURNING course_id) SELECT (SELECT count(*) FROM private.course_bookmarks WHERE owner_id='f2c0e500-0000-4000-8000-000000000003')=0 AND (SELECT count(*) FROM changed)=0 $test$);
SELECT pg_temp.bookmark_check('student hidden states and missing course all null',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000226') IS NULL AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000227') IS NULL AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000228') IS NULL AND public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000999') IS NULL $test$);
SELECT pg_temp.bookmark_error('draft save denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000226',true,1) $test$,'42501','bookmark_course_unavailable');
SELECT pg_temp.bookmark_error('archived save denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000227',true,1) $test$,'42501','bookmark_course_unavailable');
SELECT pg_temp.bookmark_error('deleted save denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000228',true,1) $test$,'42501','bookmark_course_unavailable');
SELECT pg_temp.bookmark_error('missing course save denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000999',true,0) $test$,'42501','bookmark_course_unavailable');
INSERT INTO pg_temp.bookmark_replies VALUES('hidden_remove',public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000228',false,1));
SELECT pg_temp.bookmark_check('known revision hidden removal advances false tombstone',$test$ SELECT pg_temp.bookmark_reply('hidden_remove')='{"course_id":"f2c0e500-0000-4000-8000-000000000228","saved":false,"revision":2}'::jsonb AND (SELECT count(*)=1 AND bool_and(NOT saved AND revision=2) FROM private.course_bookmarks WHERE course_id='f2c0e500-0000-4000-8000-000000000228') $test$);
INSERT INTO pg_temp.bookmark_replies VALUES('missing_remove',public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000999',false,0));
SELECT pg_temp.bookmark_check('missing removal same false revision one semantics',$test$ SELECT pg_temp.bookmark_reply('missing_remove')='{"course_id":"f2c0e500-0000-4000-8000-000000000999","saved":false,"revision":1}'::jsonb $test$);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000999',false,1);
SELECT pg_temp.bookmark_check('repeated missing removal advances existing tombstone',$test$ SELECT count(*)=1 AND bool_and(NOT saved AND revision=2) FROM private.course_bookmarks WHERE course_id='f2c0e500-0000-4000-8000-000000000999' $test$);
-- ABA regression: no initial save row, newer remove wins; older expected-0 save fails.
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000229',false,0);
SELECT pg_temp.bookmark_error('delayed save expected zero cannot follow newer initial remove',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000229',true,0) $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.bookmark_check('ABA denial preserves false tombstone and revision',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000229')='{"course_id":"f2c0e500-0000-4000-8000-000000000229","saved":false,"revision":1}'::jsonb $test$);
SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',false,2);
SELECT pg_temp.bookmark_error('delayed remove cannot overwrite newer state revision',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',false,2) $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.bookmark_check('false tombstones excluded from saved list',$test$ SELECT jsonb_array_length(public.list_saved_courses(p_limit=>50)->'items')=24 $test$);
SELECT pg_temp.bookmark_error('direct tombstone deletion denied',$test$ DELETE FROM private.course_bookmarks WHERE owner_id=auth.uid() $test$,'42501','permission denied for table course_bookmarks');
SELECT pg_temp.bookmark_error('direct owner reassignment denied',$test$ UPDATE private.course_bookmarks SET owner_id='f2c0e500-0000-4000-8000-000000000003' WHERE owner_id=auth.uid() $test$,'42501','permission denied for table course_bookmarks');
SELECT pg_temp.bookmark_error('direct backward revision reset denied',$test$ UPDATE private.course_bookmarks SET revision=0 WHERE course_id='f2c0e500-0000-4000-8000-000000000201' $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.bookmark_error('direct save of hidden row rejected by UPDATE policy',$test$ UPDATE private.course_bookmarks SET saved=true,revision=revision+1 WHERE course_id='f2c0e500-0000-4000-8000-000000000228' $test$,'42501','new row violates row-level security policy for table "course_bookmarks"');
SELECT pg_temp.bookmark_error('direct revision injection on INSERT denied',$test$ INSERT INTO private.course_bookmarks(owner_id,course_id,revision) VALUES(auth.uid(),'f2c0e500-0000-4000-8000-000000000998',100) $test$,'42501','permission denied for table course_bookmarks');

SELECT pg_temp.bookmark_error('get null course invalid',$test$ SELECT public.get_course_bookmark(NULL) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('set null course invalid',$test$ SELECT public.set_course_bookmark(NULL,false,0) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('set null saved invalid',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',NULL,3) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('set null revision invalid',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',true,NULL) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('set negative revision invalid',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',true,-1) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('null limit invalid',$test$ SELECT public.list_saved_courses(p_limit=>NULL) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('zero limit invalid',$test$ SELECT public.list_saved_courses(p_limit=>0) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('over fifty limit invalid',$test$ SELECT public.list_saved_courses(p_limit=>51) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('position without ID invalid',$test$ SELECT public.list_saved_courses(p_after_position=>0) $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('ID without position invalid',$test$ SELECT public.list_saved_courses(p_after_id=>'f2c0e500-0000-4000-8000-000000000201') $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_error('negative cursor invalid',$test$ SELECT public.list_saved_courses(-1,'f2c0e500-0000-4000-8000-000000000201') $test$,'22023','invalid_bookmark_input');
SELECT pg_temp.bookmark_check('saving never enables student material reads',$test$ SELECT count(*)=0 FROM public.session_materials $test$);
RESET ROLE;
-- Privileged boundary setup only: a missing-course false tombstone at int32 max.
INSERT INTO private.course_bookmarks(owner_id,course_id,saved,revision)
VALUES('f2c0e500-0000-4000-8000-000000000002','f2c0e500-0000-4000-8000-000000000997',false,2147483647);
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_error('max revision cannot wrap on accepted remove',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000997',false,2147483647) $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.bookmark_claim(3);
SELECT pg_temp.bookmark_check('other account reference survived hidden removal',$test$ SELECT count(*)=1 AND bool_and(saved AND revision=1) FROM private.course_bookmarks WHERE course_id='f2c0e500-0000-4000-8000-000000000228' $test$);

-- Four assertions for each inactive fixture: state, mutation, list, direct RLS read.
CREATE FUNCTION pg_temp.bookmark_denied(p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM pg_temp.bookmark_error(p_label||' get denied',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201') $test$,'42501','bookmark_access_required');
  PERFORM pg_temp.bookmark_error(p_label||' set denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',false,0) $test$,'42501','bookmark_access_required');
  PERFORM pg_temp.bookmark_error(p_label||' list denied',$test$ SELECT public.list_saved_courses() $test$,'42501','bookmark_access_required');
  PERFORM pg_temp.bookmark_check(p_label||' table hidden',$test$ SELECT count(*)=0 FROM private.course_bookmarks $test$);
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.bookmark_denied(text) TO authenticated;
RESET ROLE;
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_claim(2);
SELECT pg_temp.bookmark_denied('disabled student');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_denied('revoked student device');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f2c0e500-0000-4000-8000-000000000102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_denied('ended student admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e500-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id=NULL WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_denied('nonadmitted student');
RESET ROLE;
UPDATE private.account_access SET active_session_id='f2c0e500-0000-4000-8000-000000000102' WHERE user_id='f2c0e500-0000-4000-8000-000000000002';
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e500-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.bookmark_claim(1);
SELECT pg_temp.bookmark_denied('disabled administrator');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e500-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{}';
SELECT pg_temp.bookmark_error('anonymous get EXECUTE denied',$test$ SELECT public.get_course_bookmark('f2c0e500-0000-4000-8000-000000000201') $test$,'42501','permission denied for function get_course_bookmark');
SELECT pg_temp.bookmark_error('anonymous set EXECUTE denied',$test$ SELECT public.set_course_bookmark('f2c0e500-0000-4000-8000-000000000201',false,0) $test$,'42501','permission denied for function set_course_bookmark');
SELECT pg_temp.bookmark_error('anonymous list EXECUTE denied',$test$ SELECT public.list_saved_courses() $test$,'42501','permission denied for function list_saved_courses');
RESET ROLE;
SELECT pg_temp.bookmark_check('owner foreign keys and references remain fixture scoped',$test$ SELECT (SELECT count(*) FROM public.courses WHERE created_by='f2c0e500-0000-4000-8000-000000000001')=29 AND (SELECT role FROM private.account_access WHERE user_id='f2c0e500-0000-4000-8000-000000000002')='student' $test$);

DO $count$ BEGIN
  IF (SELECT count(*) FROM pg_temp.bookmark_results)<>84 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 84 bookmark assertions';
  END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',84,
  'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase2_bookmarks_report
FROM pg_temp.bookmark_results;
ROLLBACK;
-- Preflight-safe cleanup uses only preexisting relations. Check bookmarks separately
-- after a deployed-suite rollback; the new table is absent after schema preflight rollback.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f2c0e500-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f2c0e500-%' OR user_id::text LIKE 'f2c0e500-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f2c0e500-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f2c0e500-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f2c0e500-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f2c0e500-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e500-%' OR subject_id::text LIKE 'f2c0e500-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f2c0e500-%' OR created_by::text LIKE 'f2c0e500-%') AS reserved_courses_remaining;
