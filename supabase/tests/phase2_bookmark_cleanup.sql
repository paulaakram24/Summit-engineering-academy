-- One privileged connection, whole file, stop-on-error; main owns execution.
-- Atomic preflight: insert the additive migration immediately after BEGIN below.
-- All writes are fictional f2c0e600 fixtures; no owner, storage or payment writes.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE cleanup_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE cleanup_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.cleanup_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.cleanup_replies TO authenticated;
CREATE FUNCTION pg_temp.cleanup_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.cleanup_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.cleanup_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.cleanup_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.cleanup_claim(p_user integer) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
    'sub','f2c0e600-0000-4000-8000-'||lpad(p_user::text,12,'0'),
    'session_id','f2c0e600-0000-4000-8000-'||lpad((100+p_user)::text,12,'0'),
    'user_metadata',jsonb_build_object('role','admin','is_admin',true))::text,true);
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.cleanup_check(text,text),pg_temp.cleanup_error(text,text,text,text),
  pg_temp.cleanup_claim(integer) TO authenticated,anon;

-- Collision-failing INSERTs, never upserts over real identities.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f2c0e600-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
  'bookmark-cleanup-'||n::text||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
  '{"name":"Fictional cleanup fixture","role":"admin"}'::jsonb,false,now(),now()
FROM generate_series(1,2) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f2c0e600-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
  ('f2c0e600-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM generate_series(1,2) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(1);
SELECT public.register_device(repeat('a',64),'Cleanup admin fixture');
SELECT pg_temp.cleanup_claim(2);
SELECT public.register_device(repeat('b',64),'Cleanup student fixture');
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f2c0e600-0000-4000-8000-000000000001';
SELECT pg_temp.cleanup_claim(1);
INSERT INTO public.courses(id,title,description,instructor,category,level,price_piasters,position,status)
SELECT ('f2c0e600-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,
  'Cleanup fixture '||n::text,'Private fictional description','Fictional instructor','Engineering','1',10000,n,
  CASE n WHEN 1 THEN 'published' WHEN 2 THEN 'draft' ELSE 'archived' END
FROM generate_series(1,5) n;
UPDATE public.courses SET deleted_at=now() WHERE id='f2c0e600-0000-4000-8000-000000000204';
-- Privileged setup deliberately includes a saved unknown UUID: no parent FK exists.
INSERT INTO private.course_bookmarks(owner_id,course_id,saved,revision)
SELECT 'f2c0e600-0000-4000-8000-000000000002'::uuid,
  ('f2c0e600-0000-4000-8000-'||lpad(c::text,12,'0'))::uuid,s,r
FROM (VALUES(201,true,3),(202,true,4),(203,true,5),(204,true,6),
  (901,true,7),(902,false,0),(205,false,9)) x(c,s,r);
INSERT INTO private.course_bookmarks(owner_id,course_id,saved,revision) VALUES
 ('f2c0e600-0000-4000-8000-000000000001','f2c0e600-0000-4000-8000-000000000202',true,8),
 ('f2c0e600-0000-4000-8000-000000000001','f2c0e600-0000-4000-8000-000000000201',true,2);

SELECT pg_temp.cleanup_check('RPC no parameters invoker volatile empty search path',$test$
 SELECT pronargs=0 AND prorettype='jsonb'::regtype AND NOT prosecdef
 AND provolatile::text='v' AND proconfig=ARRAY['search_path=""']
 FROM pg_proc WHERE oid='public.clear_unavailable_course_bookmarks()'::regprocedure $test$);
SELECT pg_temp.cleanup_check('authenticated only EXECUTE no public or anon',$test$
 SELECT has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE')
 FROM pg_proc p WHERE oid='public.clear_unavailable_course_bookmarks()'::regprocedure $test$);
SELECT pg_temp.cleanup_check('existing no delete and narrow update grants retained',$test$
 SELECT NOT has_table_privilege('authenticated','private.course_bookmarks','DELETE,TRUNCATE')
 AND NOT has_column_privilege('authenticated','private.course_bookmarks','owner_id','UPDATE')
 AND has_column_privilege('authenticated','private.course_bookmarks','revision','UPDATE') $test$);

SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(2);
SELECT pg_temp.cleanup_check('active student ignores forged admin metadata',$test$
 SELECT private.is_active() AND NOT private.is_admin() AND public.get_access_context()->>'role'='student' $test$);
INSERT INTO pg_temp.cleanup_replies VALUES('student',public.clear_unavailable_course_bookmarks());
SELECT pg_temp.cleanup_check('exact count-only response includes four unavailable refs',$test$
 SELECT value='{"cleared_count":4}'::jsonb FROM pg_temp.cleanup_replies WHERE key='student' $test$);
SELECT pg_temp.cleanup_check('draft archive deleted and unknown become false with next revision',$test$
 SELECT count(*)=4 AND bool_and(NOT b.saved AND b.revision=x.r)
 FROM private.course_bookmarks b JOIN (VALUES
 ('f2c0e600-0000-4000-8000-000000000202'::uuid,5),
 ('f2c0e600-0000-4000-8000-000000000203'::uuid,6),
 ('f2c0e600-0000-4000-8000-000000000204'::uuid,7),
 ('f2c0e600-0000-4000-8000-000000000901'::uuid,8)) x(id,r) ON b.course_id=x.id $test$);
SELECT pg_temp.cleanup_check('all seven own rows retained no tombstone deletion',$test$ SELECT count(*)=7 FROM private.course_bookmarks $test$);
SELECT pg_temp.cleanup_check('published saved state and revision unchanged',$test$
 SELECT saved AND revision=3 FROM private.course_bookmarks WHERE course_id='f2c0e600-0000-4000-8000-000000000201' $test$);
SELECT pg_temp.cleanup_check('revision zero false unknown tombstone unchanged',$test$
 SELECT NOT saved AND revision=0 FROM private.course_bookmarks WHERE course_id='f2c0e600-0000-4000-8000-000000000902' $test$);
SELECT pg_temp.cleanup_check('existing nonzero false hidden tombstone unchanged',$test$
 SELECT NOT saved AND revision=9 FROM private.course_bookmarks WHERE course_id='f2c0e600-0000-4000-8000-000000000205' $test$);
SELECT pg_temp.cleanup_check('hidden and missing state still null no enumeration',$test$
 SELECT public.get_course_bookmark('f2c0e600-0000-4000-8000-000000000202') IS NULL
 AND public.get_course_bookmark('f2c0e600-0000-4000-8000-000000000204') IS NULL
 AND public.get_course_bookmark('f2c0e600-0000-4000-8000-000000000901') IS NULL $test$);
SELECT pg_temp.cleanup_check('student cannot inspect admin references',$test$
 SELECT count(*)=0 FROM private.course_bookmarks WHERE owner_id='f2c0e600-0000-4000-8000-000000000001' $test$);
RESET ROLE;
SELECT pg_temp.cleanup_check('student cleanup preserves both admin rows',$test$
 SELECT count(*)=2 AND bool_and(saved AND revision=CASE WHEN course_id='f2c0e600-0000-4000-8000-000000000201' THEN 2 ELSE 8 END)
 FROM private.course_bookmarks WHERE owner_id='f2c0e600-0000-4000-8000-000000000001' $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(1);
SELECT pg_temp.cleanup_check('admin cannot inspect other owner even for cleanup',$test$
 SELECT count(*)=0 FROM private.course_bookmarks WHERE owner_id='f2c0e600-0000-4000-8000-000000000002' $test$);
INSERT INTO pg_temp.cleanup_replies VALUES('admin',public.clear_unavailable_course_bookmarks());
SELECT pg_temp.cleanup_check('admin cleanup reports only own hidden reference',$test$
 SELECT value='{"cleared_count":1}'::jsonb FROM pg_temp.cleanup_replies WHERE key='admin' $test$);
SELECT pg_temp.cleanup_check('admin own unavailable false advances published unchanged',$test$
 SELECT count(*)=2 AND bool_and(CASE WHEN course_id='f2c0e600-0000-4000-8000-000000000201' THEN saved AND revision=2 ELSE NOT saved AND revision=9 END)
 FROM private.course_bookmarks $test$);
RESET ROLE;
SELECT pg_temp.cleanup_check('admin cleanup cannot alter student state',$test$
 SELECT count(*)=7 AND count(*) FILTER(WHERE saved)=1 AND sum(revision)=38
 FROM private.course_bookmarks WHERE owner_id='f2c0e600-0000-4000-8000-000000000002' $test$);
-- Republish only the fictional cleared parent to exercise CAS rather than availability.
SELECT pg_temp.cleanup_claim(1);
UPDATE public.courses SET status='published' WHERE id='f2c0e600-0000-4000-8000-000000000202';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(2);
SELECT pg_temp.cleanup_error('delayed pre-cleanup save conflicts after republish',$test$
 SELECT public.set_course_bookmark('f2c0e600-0000-4000-8000-000000000202',true,4) $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.cleanup_check('stale save never resurrects cleared row',$test$
 SELECT public.get_course_bookmark('f2c0e600-0000-4000-8000-000000000202')=
 '{"course_id":"f2c0e600-0000-4000-8000-000000000202","saved":false,"revision":5}'::jsonb $test$);
INSERT INTO pg_temp.cleanup_replies VALUES('repeat',public.clear_unavailable_course_bookmarks());
SELECT pg_temp.cleanup_check('empty repeat exact zero no hidden metadata',$test$
 SELECT value='{"cleared_count":0}'::jsonb FROM pg_temp.cleanup_replies WHERE key='repeat' $test$);

RESET ROLE;
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_error('disabled student cleanup denied',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_access_required');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_error('revoked device cleanup denied',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_access_required');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f2c0e600-0000-4000-8000-000000000102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_error('ended admission cleanup denied',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_access_required');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e600-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id=NULL WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_error('nonadmitted student cleanup denied',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_access_required');
RESET ROLE;
UPDATE private.account_access SET active_session_id='f2c0e600-0000-4000-8000-000000000102' WHERE user_id='f2c0e600-0000-4000-8000-000000000002';
UPDATE private.account_access SET disabled=true WHERE user_id='f2c0e600-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(1);
SELECT pg_temp.cleanup_error('disabled admin cleanup denied without exemption',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_access_required');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f2c0e600-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{}';
SELECT pg_temp.cleanup_error('anonymous EXECUTE denied',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','permission denied for function clear_unavailable_course_bookmarks');
RESET ROLE;
-- One ordinary candidate plus one exhausted candidate: the whole UPDATE must roll back.
INSERT INTO private.course_bookmarks(owner_id,course_id,saved,revision) VALUES
 ('f2c0e600-0000-4000-8000-000000000002','f2c0e600-0000-4000-8000-000000000903',true,10),
 ('f2c0e600-0000-4000-8000-000000000002','f2c0e600-0000-4000-8000-000000000904',true,2147483647);
SET LOCAL ROLE authenticated;
SELECT pg_temp.cleanup_claim(2);
SELECT pg_temp.cleanup_error('revision exhaustion rejects entire cleanup',$test$ SELECT public.clear_unavailable_course_bookmarks() $test$,'42501','bookmark_state_conflict');
SELECT pg_temp.cleanup_check('exhaustion preserves both candidates no partial update',$test$
 SELECT count(*)=2 AND bool_and(saved AND revision=CASE WHEN course_id='f2c0e600-0000-4000-8000-000000000903' THEN 10 ELSE 2147483647 END)
 FROM private.course_bookmarks WHERE course_id IN('f2c0e600-0000-4000-8000-000000000903','f2c0e600-0000-4000-8000-000000000904') $test$);
SELECT pg_temp.cleanup_check('exhaustion leaves all preexisting states intact',$test$
 SELECT count(*)=7 AND count(*) FILTER(WHERE saved)=1 AND sum(revision)=38
 FROM private.course_bookmarks WHERE course_id NOT IN('f2c0e600-0000-4000-8000-000000000903','f2c0e600-0000-4000-8000-000000000904') $test$);
RESET ROLE;
DO $count$ BEGIN
  IF (SELECT count(*) FROM pg_temp.cleanup_results)<>29 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 29 bookmark cleanup assertions';
  END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',29,
 'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase2_bookmark_cleanup_report
FROM pg_temp.cleanup_results;
ROLLBACK;
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f2c0e600-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f2c0e600-%' OR user_id::text LIKE 'f2c0e600-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f2c0e600-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f2c0e600-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f2c0e600-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f2c0e600-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e600-%' OR subject_id::text LIKE 'f2c0e600-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f2c0e600-%' OR created_by::text LIKE 'f2c0e600-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM private.course_bookmarks WHERE owner_id::text LIKE 'f2c0e600-%' OR course_id::text LIKE 'f2c0e600-%') AS reserved_bookmarks_remaining;
