-- Phase 2 covers: standalone rollback suite; main executes on one privileged connection.
-- Requires 20261019015308_phase2_private_covers.sql plus both identity and content migrations.
-- Storage rows below are transactional metadata, not uploaded files. No DELETE guard bypass.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE cover_results(test_name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE cover_courses(key text PRIMARY KEY,id uuid NOT NULL UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE cover_paths(key text PRIMARY KEY,path text NOT NULL UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE cover_audit_snapshot(n bigint NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.cover_results,pg_temp.cover_courses,pg_temp.cover_paths TO authenticated,anon;
CREATE FUNCTION pg_temp.check_true(test_name text,query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
 EXECUTE query INTO STRICT actual;
 IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',test_name,actual; END IF;
 INSERT INTO pg_temp.cover_results VALUES(test_name,'PASS');
END
$helper$;
CREATE FUNCTION pg_temp.expect_error(test_name text,query text,expected_state text,expected_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
 BEGIN
  EXECUTE query;
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
 END;
 -- Helper assertion errors are outside the tested-statement handler.
 IF got_state IS NULL THEN RAISE EXCEPTION 'FAIL [%]: statement succeeded',test_name; END IF;
 IF got_state<>expected_state OR got_message<>expected_message THEN
  RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',test_name,expected_state,expected_message,got_state,got_message;
 END IF;
 INSERT INTO pg_temp.cover_results VALUES(test_name,'PASS');
END
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.check_true(text,text),pg_temp.expect_error(text,text,text,text) TO authenticated,anon;
-- Plain INSERT deliberately fails on reserved-identity collisions. Never upsert real users.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT v.id::uuid,'authenticated','authenticated',v.email,now(),
'{"provider":"email","providers":["email"]}'::jsonb,
'{"name":"Fictional cover fixture","role":"admin","is_admin":true}'::jsonb,false,now(),now()
FROM (VALUES ('f2c0e200-0000-4000-8000-000000000001','covers-admin-a@example.invalid'),('f2c0e200-0000-4000-8000-000000000002','covers-student@example.invalid'),('f2c0e200-0000-4000-8000-000000000003','covers-admin-b@example.invalid')) v(id,email);
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
VALUES ('f2c0e200-0000-4000-8000-000000000101','f2c0e200-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
('f2c0e200-0000-4000-8000-000000000102','f2c0e200-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour'),
('f2c0e200-0000-4000-8000-000000000103','f2c0e200-0000-4000-8000-000000000003',now(),now(),now()+interval '1 hour');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.register_device(repeat('1',64),'Fictional cover test device');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000002","session_id":"f2c0e200-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.register_device(repeat('2',64),'Fictional cover test device');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000003","session_id":"f2c0e200-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.register_device(repeat('3',64),'Fictional cover test device');

RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id IN ('f2c0e200-0000-4000-8000-000000000001','f2c0e200-0000-4000-8000-000000000003');

SELECT pg_temp.check_true('private PNG bucket bounds',$test$SELECT count(*)=1 AND bool_and(NOT public AND file_size_limit=3145728 AND allowed_mime_types=ARRAY['image/png']) FROM storage.buckets WHERE id='course-covers'$test$);

SELECT pg_temp.check_true('exact three scoped policies and no update policy',$test$SELECT count(*)=3 AND bool_and(roles=ARRAY['authenticated']::name[] AND permissive='PERMISSIVE' AND CASE policyname WHEN 'course_covers_read' THEN cmd='SELECT' AND qual LIKE '%course-covers%' AND qual LIKE '%cover_storage_allowed%' AND qual LIKE '%read%' WHEN 'course_covers_insert' THEN cmd='INSERT' AND with_check LIKE '%course-covers%' AND with_check LIKE '%cover_storage_allowed%' AND with_check LIKE '%insert%' WHEN 'course_covers_delete' THEN cmd='DELETE' AND qual LIKE '%course-covers%' AND qual LIKE '%cover_storage_allowed%' AND qual LIKE '%delete%' ELSE false END) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'course_covers_%'$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

-- Privileged fixture-only course IDs make post-rollback object-prefix checks independent
-- of course rows. The JWT remains the admitted fixture admin for the audit trigger.
RESET ROLE;
WITH c AS (INSERT INTO public.courses(id,title,instructor,category,level,status)
 VALUES ('f2c0e200-0000-4000-8000-000000000201','published','Fixture','Engineering','1','published'),
 ('f2c0e200-0000-4000-8000-000000000202','draft','Fixture','Engineering','1','draft')
 RETURNING id,title) INSERT INTO pg_temp.cover_courses SELECT title,id FROM c;
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.cover_paths SELECT 'p'||i,public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))->>'path' FROM generate_series(1,5) i;
INSERT INTO pg_temp.cover_paths VALUES ('draft',public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='draft'))->>'path');

SELECT pg_temp.expect_error('five live reservations cap',$test$SELECT public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','cover_upload_limit');

RESET ROLE;

SELECT pg_temp.check_true('reservation path creator course state and audit metadata',$test$SELECT count(*)=6 AND bool_and(a.created_by='f2c0e200-0000-4000-8000-000000000001' AND a.state='uploading' AND a.created_at>now()-interval '1 hour' AND a.path ~ ('^'||a.course_id::text||'/[0-9a-f-]{36}\.png$')) AND (SELECT count(*)=6 FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action='cover_upload_prepared') FROM private.course_cover_assets a JOIN pg_temp.cover_paths p ON p.path=a.path$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('reservation owner allowed upload but not update or premature delete',$test$SELECT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p1'),'insert') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p1'),'update') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p1'),'delete')$test$);

SELECT pg_temp.expect_error('unreserved path insert denied',$test$INSERT INTO storage.objects(bucket_id,name) VALUES ('course-covers',(SELECT id FROM pg_temp.cover_courses WHERE key='published')::text||'/f2c0e200-0000-4000-8000-000000000999.png')$test$,'42501','new row violates row-level security policy for table "objects"');

SELECT pg_temp.expect_error('cover path direct update denied',$test$UPDATE public.courses SET cover_path=(SELECT path FROM pg_temp.cover_paths WHERE key='p1') WHERE id=(SELECT id FROM pg_temp.cover_courses WHERE key='published')$test$,'42501','permission denied for table courses');

SELECT pg_temp.expect_error('private reservation ledger direct access denied',$test$SELECT * FROM private.course_cover_assets$test$,'42501','permission denied for table course_cover_assets');

SELECT pg_temp.expect_error('missing storage object cannot attach',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'),NULL)$test$,'42501','cover_upload_invalid');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000003","session_id":"f2c0e200-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('other active admin cannot upload owner reservation',$test$SELECT private.is_admin() AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p1'),'insert')$test$);

SELECT pg_temp.expect_error('other admin storage insert denied',$test$INSERT INTO storage.objects(bucket_id,name) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','new row violates row-level security policy for table "objects"');

SELECT pg_temp.expect_error('other admin cannot attach owner reservation',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'),NULL)$test$,'42501','cover_unavailable');

RESET ROLE;

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p2'),jsonb_build_object('mimetype','image/jpeg','size',1234));

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p3'),jsonb_build_object('mimetype','image/png','size',3145729));

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p4'),jsonb_build_object('mimetype','image/png','size',3145728));

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='draft'),jsonb_build_object('mimetype','image/png','size',1));

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.expect_error('wrong MIME storage object cannot attach',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p2'),NULL)$test$,'42501','cover_upload_invalid');

SELECT pg_temp.expect_error('oversized storage object cannot attach',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p3'),NULL)$test$,'42501','cover_upload_invalid');

SELECT pg_temp.check_true('valid maximum PNG attaches',$test$SELECT (public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'),NULL)->>'cover_path')=(SELECT path FROM pg_temp.cover_paths WHERE key='p4')$test$);

SELECT pg_temp.check_true('valid minimum PNG attaches on draft',$test$SELECT (public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='draft'),(SELECT path FROM pg_temp.cover_paths WHERE key='draft'),NULL)->>'cover_path')=(SELECT path FROM pg_temp.cover_paths WHERE key='draft')$test$);

RESET ROLE;
INSERT INTO pg_temp.cover_audit_snapshot SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action LIKE 'content_%';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('same-path retry accepts original expected null',$test$SELECT (public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'),NULL)->>'cover_path')=(SELECT path FROM pg_temp.cover_paths WHERE key='p4')$test$);

SELECT public.abandon_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'));
RESET ROLE;

SELECT pg_temp.check_true('attach retry and abandon attached are mutation and audit safe',$test$SELECT (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action LIKE 'content_%')=n AND (SELECT state='attached' FROM private.course_cover_assets WHERE path=(SELECT path FROM pg_temp.cover_paths WHERE key='p4')) AND NOT EXISTS(SELECT 1 FROM private.security_events WHERE action='cover_upload_abandoned' AND actor_id='f2c0e200-0000-4000-8000-000000000001' AND details->>'path'=(SELECT path FROM pg_temp.cover_paths WHERE key='p4')) FROM pg_temp.cover_audit_snapshot$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('attached object never cleanup-deletable',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'delete')$test$);

SELECT pg_temp.check_true('storage update filtered prevents overwrite',$test$WITH changed AS (UPDATE storage.objects SET metadata='{"mimetype":"image/jpeg","size":2}'::jsonb WHERE bucket_id='course-covers' AND name=(SELECT path FROM pg_temp.cover_paths WHERE key='p4') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000002","session_id":"f2c0e200-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student sees current published reference only',$test$SELECT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'read') AND (SELECT count(*)=1 FROM storage.objects WHERE bucket_id='course-covers' AND name IN (SELECT path FROM pg_temp.cover_paths)) AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('student draft and unattached objects hidden',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='draft'),'read') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p2'),'read') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p3'),'read') AND NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='course-covers' AND name IN ((SELECT path FROM pg_temp.cover_paths WHERE key='draft'),(SELECT path FROM pg_temp.cover_paths WHERE key='p2'),(SELECT path FROM pg_temp.cover_paths WHERE key='p3')))$test$);

SELECT pg_temp.expect_error('student upload reservation denied',$test$INSERT INTO storage.objects(bucket_id,name) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','new row violates row-level security policy for table "objects"');

SELECT pg_temp.expect_error('student prepare_course_cover denied',$test$SELECT public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','admin_required');

SELECT pg_temp.expect_error('student attach_course_cover denied',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'),NULL)$test$,'42501','admin_required');

SELECT pg_temp.expect_error('student abandon_course_cover denied',$test$SELECT public.abandon_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','admin_required');

SELECT pg_temp.expect_error('student list_retired_course_covers denied',$test$SELECT public.list_retired_course_covers((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','admin_required');

SELECT pg_temp.expect_error('student finish_course_cover_cleanup denied',$test$SELECT public.finish_course_cover_cleanup((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','admin_required');

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{"role":"anon"}';

SELECT pg_temp.expect_error('anon prepare_course_cover denied',$test$SELECT public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','permission denied for function prepare_course_cover');

SELECT pg_temp.expect_error('anon attach_course_cover denied',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'),NULL)$test$,'42501','permission denied for function attach_course_cover');

SELECT pg_temp.expect_error('anon abandon_course_cover denied',$test$SELECT public.abandon_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','permission denied for function abandon_course_cover');

SELECT pg_temp.expect_error('anon list_retired_course_covers denied',$test$SELECT public.list_retired_course_covers((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','permission denied for function list_retired_course_covers');

SELECT pg_temp.expect_error('anon finish_course_cover_cleanup denied',$test$SELECT public.finish_course_cover_cleanup((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$,'42501','permission denied for function finish_course_cover_cleanup');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.abandon_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'));
SELECT public.abandon_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'));

SELECT pg_temp.expect_error('abandoned reservation never reattaches',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'))$test$,'42501','cover_unavailable');

SELECT pg_temp.check_true('abandoned reservation no longer uploadable',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p5'),'insert') AND private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p5'),'delete')$test$);

SELECT public.finish_course_cover_cleanup((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'));
SELECT public.finish_course_cover_cleanup((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'));
RESET ROLE;

SELECT pg_temp.check_true('cleanup and abandonment audited once retain tombstone',$test$SELECT (SELECT state='cleaned' FROM private.course_cover_assets WHERE path=(SELECT path FROM pg_temp.cover_paths WHERE key='p5')) AND (SELECT count(*)=1 FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action='cover_upload_abandoned' AND details->>'path'=(SELECT path FROM pg_temp.cover_paths WHERE key='p5')) AND (SELECT count(*)=1 FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action='cover_cleanup_finished' AND details->>'path'=(SELECT path FROM pg_temp.cover_paths WHERE key='p5'))$test$);

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p5'),jsonb_build_object('mimetype','image/png','size',100));

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('late object at cleaned tombstone relisted',$test$SELECT public.list_retired_course_covers((SELECT id FROM pg_temp.cover_courses WHERE key='published')) @> jsonb_build_array((SELECT path FROM pg_temp.cover_paths WHERE key='p5')) AND private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p5'),'delete') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p5'),'insert')$test$);

SELECT pg_temp.expect_error('cleaned late object cannot attach',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'))$test$,'42501','cover_unavailable');

SELECT pg_temp.expect_error('cleanup completion waits for real object removal',$test$SELECT public.finish_course_cover_cleanup((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p5'))$test$,'42501','cover_cleanup_pending');

INSERT INTO pg_temp.cover_paths VALUES('p6',public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))->>'path');
RESET ROLE;

INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('course-covers',(SELECT path FROM pg_temp.cover_paths WHERE key='p6'),jsonb_build_object('mimetype','image/png','size',100));

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.expect_error('stale expected cover raises conflict',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p6'),NULL)$test$,'40001','cover_changed');

SELECT pg_temp.check_true('correct compare and swap replaces reference',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p6'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'))->>'cover_path'=(SELECT path FROM pg_temp.cover_paths WHERE key='p6')$test$);

SELECT pg_temp.check_true('retired old reference deletable current reference protected',$test$SELECT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'delete') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'insert') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p6'),'delete')$test$);

SELECT pg_temp.expect_error('retired old path never reattaches',$test$SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),(SELECT path FROM pg_temp.cover_paths WHERE key='p4'),(SELECT path FROM pg_temp.cover_paths WHERE key='p6'))$test$,'42501','cover_unavailable');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000002","session_id":"f2c0e200-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student retired objects hidden new reference visible',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'read') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p5'),'read') AND private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p6'),'read') AND (SELECT count(*)=1 AND bool_and(name=(SELECT path FROM pg_temp.cover_paths WHERE key='p6')) FROM storage.objects WHERE bucket_id='course-covers' AND name IN (SELECT path FROM pg_temp.cover_paths)) AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'delete')$test$);

RESET ROLE;
UPDATE private.course_cover_assets SET created_at=now()-interval '2 hours' WHERE path=(SELECT path FROM pg_temp.cover_paths WHERE key='p1');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('expired reservation not uploadable',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p1'),'insert')$test$);

SELECT pg_temp.check_true('cleanup lists and retires expired reservation bounded',$test$SELECT public.list_retired_course_covers((SELECT id FROM pg_temp.cover_courses WHERE key='published')) @> jsonb_build_array((SELECT path FROM pg_temp.cover_paths WHERE key='p1')) AND jsonb_array_length(public.list_retired_course_covers((SELECT id FROM pg_temp.cover_courses WHERE key='published')))<=20$test$);

RESET ROLE;

SELECT pg_temp.check_true('expiration audited once with retired state',$test$SELECT (SELECT state='retired' FROM private.course_cover_assets WHERE path=(SELECT path FROM pg_temp.cover_paths WHERE key='p1')) AND (SELECT count(*)=1 FROM private.security_events WHERE actor_id='f2c0e200-0000-4000-8000-000000000001' AND action='cover_upload_expired' AND details->>'path'=(SELECT path FROM pg_temp.cover_paths WHERE key='p1'))$test$);

RESET ROLE;

UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e200-0000-4000-8000-000000000001';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('revoked actual session denies all storage actions',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p6'),'read') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p2'),'insert') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'delete') AND NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='course-covers' AND name IN (SELECT path FROM pg_temp.cover_paths))$test$);

SELECT pg_temp.expect_error('revoked admin cannot prepare',$test$SELECT public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','admin_required');

RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e200-0000-4000-8000-000000000001';
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e200-0000-4000-8000-000000000101';

RESET ROLE;

UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f2c0e200-0000-4000-8000-000000000101';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('expired actual session denies all storage actions',$test$SELECT NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p6'),'read') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p2'),'insert') AND NOT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p4'),'delete') AND NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='course-covers' AND name IN (SELECT path FROM pg_temp.cover_paths))$test$);

SELECT pg_temp.expect_error('expired admin cannot prepare',$test$SELECT public.prepare_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$,'42501','admin_required');

RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e200-0000-4000-8000-000000000001';
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e200-0000-4000-8000-000000000101';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"f2c0e200-0000-4000-8000-000000000001","session_id":"f2c0e200-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.attach_course_cover((SELECT id FROM pg_temp.cover_courses WHERE key='published'),NULL,(SELECT path FROM pg_temp.cover_paths WHERE key='p6'));

SELECT pg_temp.check_true('detach retires reference leaves no student read',$test$SELECT private.cover_storage_allowed((SELECT path FROM pg_temp.cover_paths WHERE key='p6'),'delete') AND (SELECT cover_path IS NULL FROM public.courses WHERE id=(SELECT id FROM pg_temp.cover_courses WHERE key='published'))$test$);

RESET ROLE;

SELECT pg_temp.check_true('all expected storage fixture metadata unchanged',$test$SELECT count(*)=6 AND bool_and(CASE WHEN name=(SELECT path FROM pg_temp.cover_paths WHERE key='p2') THEN metadata->>'mimetype'='image/jpeg' WHEN name=(SELECT path FROM pg_temp.cover_paths WHERE key='p3') THEN metadata->>'size'='3145729' ELSE metadata->>'mimetype'='image/png' END) FROM storage.objects WHERE bucket_id='course-covers' AND name IN (SELECT path FROM pg_temp.cover_paths)$test$);

SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',53,'tests',jsonb_agg(jsonb_build_object('name',test_name,'outcome',outcome) ORDER BY test_name)) AS phase2_covers_report FROM pg_temp.cover_results;
ROLLBACK;
-- Separate readback remains valid after migration-plus-suite rollback (no new relations referenced).
SELECT
 (SELECT count(*) FROM auth.users WHERE id IN ('f2c0e200-0000-4000-8000-000000000001','f2c0e200-0000-4000-8000-000000000002','f2c0e200-0000-4000-8000-000000000003')) AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id IN ('f2c0e200-0000-4000-8000-000000000101','f2c0e200-0000-4000-8000-000000000102','f2c0e200-0000-4000-8000-000000000103')) AS reserved_sessions_remaining,
 (SELECT count(*) FROM public.courses WHERE created_by IN ('f2c0e200-0000-4000-8000-000000000001','f2c0e200-0000-4000-8000-000000000002','f2c0e200-0000-4000-8000-000000000003')) AS reserved_courses_remaining,
 (SELECT count(*) FROM storage.objects WHERE bucket_id='course-covers' AND split_part(name,'/',1) IN ('f2c0e200-0000-4000-8000-000000000201','f2c0e200-0000-4000-8000-000000000202')) AS reserved_objects_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id IN ('f2c0e200-0000-4000-8000-000000000001','f2c0e200-0000-4000-8000-000000000002','f2c0e200-0000-4000-8000-000000000003')) AS reserved_events_remaining;
