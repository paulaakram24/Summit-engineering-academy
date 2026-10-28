-- Standalone Phase 2 regression; main runs this ENTIRE file in one privileged connection.
-- Requires both Phase 1 migrations and 20261018154932_phase2_content_core.sql.
-- No migration, owner, Auth API, email or storage-policy changes.
BEGIN;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SET LOCAL row_security = on;
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claim.role = '';
SET LOCAL request.jwt.claims = '{}';

CREATE TEMP TABLE phase2_results(test_name text PRIMARY KEY, outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE phase2_ids(key text PRIMARY KEY, id uuid UNIQUE NOT NULL, kind text NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE phase2_baseline(event_count bigint NOT NULL, course_price integer NOT NULL) ON COMMIT DROP;
GRANT SELECT, INSERT ON pg_temp.phase2_results, pg_temp.phase2_ids TO authenticated, anon;

CREATE FUNCTION pg_temp.check_true(test_name text, query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL [%]: expected true, got %', test_name, actual;
  END IF;
  INSERT INTO pg_temp.phase2_results VALUES(test_name,'PASS');
END
$helper$;

CREATE FUNCTION pg_temp.expect_error(test_name text, query text, expected_state text, expected_message text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  -- Only the tested statement is caught; assertion/helper failures are outside this block.
  BEGIN
    EXECUTE query;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE, got_message=MESSAGE_TEXT;
  END;
  IF got_state IS NULL THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, statement succeeded', test_name, expected_state, expected_message;
  END IF;
  IF got_state<>expected_state OR got_message<>expected_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %', test_name, expected_state, expected_message, got_state, got_message;
  END IF;
  INSERT INTO pg_temp.phase2_results VALUES(test_name,'PASS');
END
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.check_true(text,text),pg_temp.expect_error(text,text,text,text) TO authenticated,anon;

-- Collision-failing INSERT only; never upsert a reserved identity.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
VALUES
('f2c0e100-0000-4000-8000-000000000001','authenticated','authenticated','phase2-admin@example.invalid',now(),
'{"provider":"email","providers":["email"]}','{"name":"Fictional content admin","role":"admin","is_admin":true}',false,now(),now()),
('f2c0e100-0000-4000-8000-000000000002','authenticated','authenticated','phase2-student@example.invalid',now(),
'{"provider":"email","providers":["email"]}','{"name":"Fictional content student","role":"admin","is_admin":true}',false,now(),now());
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after) VALUES
('f2c0e100-0000-4000-8000-000000000101','f2c0e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
('f2c0e100-0000-4000-8000-000000000102','f2c0e100-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('admin fixture initially student despite forged metadata', $test$SELECT public.register_device(repeat('a',64),'Phase 2 fictional admin device')->>'role'='student'$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student fixture registration ignores forged metadata', $test$SELECT public.register_device(repeat('b',64),'Phase 2 fictional student device')->>'role'='student'$test$);

RESET ROLE;
-- Trusted fixture-only role grant. No real owner identity is selected or changed.
UPDATE private.account_access SET role='admin' WHERE user_id='f2c0e100-0000-4000-8000-000000000001';

SELECT pg_temp.check_true('fixture server admin grant exactly one enabled account', $test$SELECT count(*)=1 FROM private.account_access WHERE user_id='f2c0e100-0000-4000-8000-000000000001' AND role='admin' AND NOT disabled$test$);

SELECT pg_temp.check_true('content tables RLS enabled', $test$SELECT count(*)=2 AND bool_and(relrowsecurity) FROM pg_class WHERE oid IN ('public.courses'::regclass,'public.course_sessions'::regclass)$test$);

SELECT pg_temp.check_true('three existing material buckets remain private', $test$SELECT count(*)=3 AND bool_and(NOT public) FROM storage.buckets WHERE id IN ('course-materials','payment-receipts','assignment-submissions')$test$);

SELECT pg_temp.check_true('storage object policies allow only named cover policies', $test$SELECT count(*)=0 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname NOT IN ('course_covers_read','course_covers_insert','course_covers_delete','material_upload_quarantine_insert')$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('active server admin access', $test$SELECT public.get_access_context()->>'role'='admin' AND private.is_admin()$test$);

WITH inserted AS (
 INSERT INTO public.courses(title,description,instructor,category,level,price_piasters,position,status)
 VALUES ('cp','Published fixture','Fixture instructor','Engineering','1',12345,0,'published'),
 ('cd','Draft fixture','Fixture instructor','Engineering','1',0,1,'draft'),
 ('ca','Archived fixture','Fixture instructor','Engineering','1',0,2,'archived'),
 ('cx','Deleted parent fixture','Fixture instructor','Engineering','1',0,3,'published')
 RETURNING id,title
) INSERT INTO pg_temp.phase2_ids SELECT title,id,'course' FROM inserted;
WITH inserted AS (
 INSERT INTO public.course_sessions(course_id,session_number,title,description,price_piasters,position,status,is_free_preview)
 SELECT c.id,v.num,v.key,'Session fixture',6789,v.pos,v.status,v.preview
 FROM (VALUES ('cp',1,'sp',0,'published',true),('cp',2,'sd',1,'draft',false),
 ('cp',3,'sa',2,'archived',false),('cp',4,'sx',3,'archived',false),
 ('cd',1,'hp_d',0,'published',true),('ca',1,'hp_a',0,'published',true),
 ('cx',1,'hp_x',0,'published',true)) AS v(parent,num,key,pos,status,preview)
 JOIN pg_temp.phase2_ids c ON c.key=v.parent
 RETURNING id,title
) INSERT INTO pg_temp.phase2_ids SELECT title,id,'session' FROM inserted;

SELECT pg_temp.check_true('admin creates and reads all four lifecycle courses', $test$SELECT count(*)=4 AND bool_and(created_by='f2c0e100-0000-4000-8000-000000000001' AND cover_path IS NULL) FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='course')$test$);

SELECT pg_temp.check_true('admin creates and reads seven sessions', $test$SELECT count(*)=7 AND bool_and(created_by='f2c0e100-0000-4000-8000-000000000001') FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='session')$test$);

RESET ROLE;

SELECT pg_temp.check_true('one atomic insert audit per content entity', $test$SELECT count(*)=11 AND count(DISTINCT details->>'id')=11 AND bool_and(actor_id='f2c0e100-0000-4000-8000-000000000001' AND subject_id=actor_id AND action='content_insert' AND details->>'entity' IN ('courses','course_sessions') AND details->>'status' IN ('draft','published','archived') AND details->>'deleted'='false' AND NOT(details ?| ARRAY['description','phone','email'])) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000001' AND action LIKE 'content_%'$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('admin soft deletes hidden parent', $test$WITH changed AS (UPDATE public.courses SET deleted_at=now() WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cx') RETURNING status,deleted_at) SELECT count(*)=1 AND bool_and(status='archived' AND deleted_at IS NOT NULL) FROM changed$test$);

SELECT pg_temp.check_true('admin soft deletes session', $test$WITH changed AS (UPDATE public.course_sessions SET deleted_at=now() WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sx') RETURNING status,deleted_at) SELECT count(*)=1 AND bool_and(status='archived' AND deleted_at IS NOT NULL) FROM changed$test$);

SELECT pg_temp.check_true('admin course edit keeps exact integer piasters', $test$WITH changed AS (UPDATE public.courses SET title='Edited course',price_piasters=12346,position=5 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING *) SELECT count(*)=1 AND bool_and(title='Edited course' AND price_piasters=12346 AND position=5 AND created_by='f2c0e100-0000-4000-8000-000000000001') FROM changed$test$);

SELECT pg_temp.check_true('admin session edit exact price ordering and preview', $test$WITH changed AS (UPDATE public.course_sessions SET title='Edited session',price_piasters=6790,session_number=10,position=6,is_free_preview=false WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING *) SELECT count(*)=1 AND bool_and(title='Edited session' AND price_piasters=6790 AND session_number=10 AND position=6 AND NOT is_free_preview) FROM changed$test$);

SELECT pg_temp.expect_error('courses rejects invalid title', $test$UPDATE public.courses SET title='   ' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_title_check"');

SELECT pg_temp.expect_error('courses rejects invalid instructor', $test$UPDATE public.courses SET instructor=' ' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_instructor_check"');

SELECT pg_temp.expect_error('courses rejects invalid category', $test$UPDATE public.courses SET category=' ' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_category_check"');

SELECT pg_temp.expect_error('courses rejects invalid level', $test$UPDATE public.courses SET level=' ' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_level_check"');

SELECT pg_temp.expect_error('courses rejects invalid description', $test$UPDATE public.courses SET description=repeat('x',10001) WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_description_check"');

SELECT pg_temp.expect_error('courses rejects invalid price_piasters', $test$UPDATE public.courses SET price_piasters=-1 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_price_piasters_check"');

SELECT pg_temp.expect_error('courses rejects invalid position', $test$UPDATE public.courses SET position=-1 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_position_check"');

SELECT pg_temp.expect_error('courses rejects invalid status', $test$UPDATE public.courses SET status='invalid' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '23514', 'new row for relation "courses" violates check constraint "courses_status_check"');

SELECT pg_temp.expect_error('courses rejects price integer overflow', $test$UPDATE public.courses SET price_piasters=2147483648 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '22003', 'integer out of range');

SELECT pg_temp.expect_error('courses client cannot update created_by', $test$UPDATE public.courses SET created_by='f2c0e100-0000-4000-8000-000000000002' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('courses client cannot update id', $test$UPDATE public.courses SET id='f2c0e100-0000-4000-8000-000000000501' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('courses client cannot update created_at', $test$UPDATE public.courses SET created_at=now()-interval '1 day' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('courses client cannot update updated_at', $test$UPDATE public.courses SET updated_at=now()+interval '1 day' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('courses client cannot insert created_by', $test$INSERT INTO public.courses(title,instructor,category,level,created_by) VALUES ('Forged creator','Fixture','Engineering','1','f2c0e100-0000-4000-8000-000000000002')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('courses admin permanent delete denied', $test$DELETE FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('course_sessions rejects invalid title', $test$UPDATE public.course_sessions SET title=' ' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_title_check"');

SELECT pg_temp.expect_error('course_sessions rejects invalid description', $test$UPDATE public.course_sessions SET description=repeat('x',10001) WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_description_check"');

SELECT pg_temp.expect_error('course_sessions rejects invalid session_number', $test$UPDATE public.course_sessions SET session_number=0 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_session_number_check"');

SELECT pg_temp.expect_error('course_sessions rejects invalid price_piasters', $test$UPDATE public.course_sessions SET price_piasters=-1 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_price_piasters_check"');

SELECT pg_temp.expect_error('course_sessions rejects invalid position', $test$UPDATE public.course_sessions SET position=-1 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_position_check"');

SELECT pg_temp.expect_error('course_sessions rejects invalid status', $test$UPDATE public.course_sessions SET status='invalid' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '23514', 'new row for relation "course_sessions" violates check constraint "course_sessions_status_check"');

SELECT pg_temp.expect_error('course_sessions rejects price integer overflow', $test$UPDATE public.course_sessions SET price_piasters=2147483648 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '22003', 'integer out of range');

SELECT pg_temp.expect_error('course_sessions client cannot update created_by', $test$UPDATE public.course_sessions SET created_by='f2c0e100-0000-4000-8000-000000000002' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('course_sessions client cannot update id', $test$UPDATE public.course_sessions SET id='f2c0e100-0000-4000-8000-000000000501' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('course_sessions client cannot update created_at', $test$UPDATE public.course_sessions SET created_at=now()-interval '1 day' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('course_sessions client cannot update updated_at', $test$UPDATE public.course_sessions SET updated_at=now()+interval '1 day' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('course_sessions client cannot insert created_by', $test$INSERT INTO public.course_sessions(course_id,session_number,title,created_by) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),50,'Forged creator','f2c0e100-0000-4000-8000-000000000002')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('course_sessions admin permanent delete denied', $test$DELETE FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('session parent immutable by column grant', $test$UPDATE public.course_sessions SET course_id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cd') WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('session number unique within parent', $test$UPDATE public.course_sessions SET session_number=10 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sd')$test$, '23505', 'duplicate key value violates unique constraint "course_sessions_course_id_session_number_key"');

SELECT pg_temp.expect_error('soft deleted session still reserves number', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),4,'Duplicate deleted number')$test$, '23505', 'duplicate key value violates unique constraint "course_sessions_course_id_session_number_key"');

SELECT pg_temp.expect_error('cover path not writable before controlled uploads', $test$UPDATE public.courses SET cover_path='arbitrary/path' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

RESET ROLE;
INSERT INTO pg_temp.phase2_baseline SELECT
 (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000001' AND action LIKE 'content_%'),
 (SELECT price_piasters FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp'));

SELECT pg_temp.check_true('only successful initial content writes audited', $test$SELECT event_count=15 AND course_price=12346 FROM pg_temp.phase2_baseline$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.expect_error('content and audit roll back together on statement failure', $test$DO $atomic$ BEGIN UPDATE public.courses SET price_piasters=1 WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp'); RAISE EXCEPTION 'phase2_atomic_probe' USING ERRCODE='P0001'; END $atomic$$test$, 'P0001', 'phase2_atomic_probe');

RESET ROLE;

SELECT pg_temp.check_true('failed statement leaves exact content price and audit count intact', $test$SELECT (SELECT price_piasters FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp'))=course_price AND (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000001' AND action LIKE 'content_%')=event_count FROM pg_temp.phase2_baseline$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('course delete forces archived even if publication requested', $test$WITH changed AS (UPDATE public.courses SET deleted_at=now(),status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING *) SELECT count(*)=1 AND bool_and(status='archived' AND deleted_at IS NOT NULL) FROM changed$test$);

SELECT pg_temp.check_true('deleted course blocks editing existing session', $test$WITH changed AS (UPDATE public.course_sessions SET title='Forbidden child edit' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('deleted course blocks new session', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),98,'Forbidden child insert')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

SELECT pg_temp.check_true('course restore forces draft even if publication requested', $test$WITH changed AS (UPDATE public.courses SET deleted_at=NULL,status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING *) SELECT count(*)=1 AND bool_and(status='draft' AND deleted_at IS NULL) FROM changed$test$);

SELECT pg_temp.check_true('explicit course republish required', $test$WITH changed AS (UPDATE public.courses SET status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING status) SELECT count(*)=1 AND bool_and(status='published') FROM changed$test$);

SELECT pg_temp.check_true('session delete forces archive', $test$WITH changed AS (UPDATE public.course_sessions SET deleted_at=now(),status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING *) SELECT count(*)=1 AND bool_and(status='archived' AND deleted_at IS NOT NULL) FROM changed$test$);

SELECT pg_temp.check_true('session restore forces draft', $test$WITH changed AS (UPDATE public.course_sessions SET deleted_at=NULL,status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING *) SELECT count(*)=1 AND bool_and(status='draft' AND deleted_at IS NULL) FROM changed$test$);

SELECT pg_temp.check_true('session republish after restore', $test$WITH changed AS (UPDATE public.course_sessions SET status='published' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING status) SELECT count(*)=1 AND bool_and(status='published') FROM changed$test$);

RESET ROLE;

SELECT pg_temp.check_true('lifecycle audit exact count and state transitions', $test$SELECT count(*)=21 AND count(*) FILTER(WHERE action='content_update')=10 AND count(*) FILTER(WHERE action='content_update' AND details->>'deleted'='true' AND details->>'status'='archived')=4 AND count(*) FILTER(WHERE action='content_update' AND details->>'deleted'='false' AND details->>'status'='draft')=2 FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000001' AND action LIKE 'content_%'$test$);

SELECT pg_temp.check_true('deleted parent prevented child edit without mutation', $test$SELECT title='Edited session' AND course_id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') AND created_by='f2c0e100-0000-4000-8000-000000000001' FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('forged student metadata never grants admin', $test$SELECT NOT private.is_admin() AND public.get_access_context()->>'role'='student'$test$);

SELECT pg_temp.check_true('student sees only published nondeleted course', $test$SELECT count(*)=1 AND bool_and(id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') AND price_piasters=12346) FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='course')$test$);

SELECT pg_temp.check_true('student sees only published session of published parent', $test$SELECT count(*)=1 AND bool_and(id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') AND price_piasters=6790) FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='session')$test$);

SELECT pg_temp.check_true('student hidden course cd', $test$SELECT count(*)=0 FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cd')$test$);

SELECT pg_temp.check_true('student hidden course ca', $test$SELECT count(*)=0 FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='ca')$test$);

SELECT pg_temp.check_true('student hidden course cx', $test$SELECT count(*)=0 FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cx')$test$);

SELECT pg_temp.check_true('student hidden session sd', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sd')$test$);

SELECT pg_temp.check_true('student hidden session sa', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sa')$test$);

SELECT pg_temp.check_true('student hidden session sx', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sx')$test$);

SELECT pg_temp.check_true('student hidden session hp_d', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='hp_d')$test$);

SELECT pg_temp.check_true('student hidden session hp_a', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='hp_a')$test$);

SELECT pg_temp.check_true('student hidden session hp_x', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='hp_x')$test$);

SELECT pg_temp.expect_error('student courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('student courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Student intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student courses delete denied', $test$DELETE FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('student course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

SELECT pg_temp.check_true('student course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Student intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student course_sessions delete denied', $test$DELETE FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

RESET ROLE;

SELECT pg_temp.check_true('student write attempts change neither content nor audit', $test$SELECT (SELECT title FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp'))='Edited course' AND (SELECT title FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp'))='Edited session' AND (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000002' AND action LIKE 'content_%')=0$test$);

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{"role":"anon"}';

SELECT pg_temp.expect_error('anonymous courses read denied', $test$SELECT * FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('anonymous courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('anonymous courses update denied', $test$UPDATE public.courses SET title='Anonymous intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('anonymous courses delete denied', $test$DELETE FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp')$test$, '42501', 'permission denied for table courses');

SELECT pg_temp.expect_error('anonymous course_sessions read denied', $test$SELECT * FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('anonymous course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('anonymous course_sessions update denied', $test$UPDATE public.course_sessions SET title='Anonymous intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

SELECT pg_temp.expect_error('anonymous course_sessions delete denied', $test$DELETE FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp')$test$, '42501', 'permission denied for table course_sessions');

RESET ROLE;

UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f2c0e100-0000-4000-8000-000000000101';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('admin expired helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('admin expired courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin expired courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin expired courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('admin expired course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin expired course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin expired course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000001';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000101' WHERE user_id='f2c0e100-0000-4000-8000-000000000001';

RESET ROLE;

UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e100-0000-4000-8000-000000000001';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('admin revoked helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('admin revoked courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin revoked courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin revoked courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('admin revoked course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin revoked course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin revoked course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000001';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000101' WHERE user_id='f2c0e100-0000-4000-8000-000000000001';

RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.end_session();

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000001","session_id":"f2c0e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('admin ended helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('admin ended courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin ended courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin ended courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('admin ended course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('admin ended course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('admin ended course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000001';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000101';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000101' WHERE user_id='f2c0e100-0000-4000-8000-000000000001';

RESET ROLE;

UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f2c0e100-0000-4000-8000-000000000102';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student expired helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('student expired courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student expired courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student expired courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('student expired course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student expired course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student expired course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000102' WHERE user_id='f2c0e100-0000-4000-8000-000000000002';

RESET ROLE;

UPDATE private.devices SET revoked_at=now() WHERE user_id='f2c0e100-0000-4000-8000-000000000002';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student revoked helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('student revoked courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student revoked courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student revoked courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('student revoked course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student revoked course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student revoked course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000102' WHERE user_id='f2c0e100-0000-4000-8000-000000000002';

RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT public.end_session();

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2c0e100-0000-4000-8000-000000000002","session_id":"f2c0e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';

SELECT pg_temp.check_true('student ended helper denies active role', $test$SELECT NOT private.is_active() AND NOT private.is_admin()$test$);

SELECT pg_temp.check_true('student ended courses invisible', $test$SELECT count(*)=0 FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student ended courses update filtered', $test$WITH changed AS (UPDATE public.courses SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student ended courses insert denied', $test$INSERT INTO public.courses(title,instructor,category,level) VALUES ('Rejected course','Fixture','Engineering','1')$test$, '42501', 'new row violates row-level security policy for table "courses"');

SELECT pg_temp.check_true('student ended course_sessions invisible', $test$SELECT count(*)=0 FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids)$test$);

SELECT pg_temp.check_true('student ended course_sessions update filtered', $test$WITH changed AS (UPDATE public.course_sessions SET title='Invalid session intrusion' WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp') RETURNING id) SELECT count(*)=0 FROM changed$test$);

SELECT pg_temp.expect_error('student ended course_sessions insert denied', $test$INSERT INTO public.course_sessions(course_id,session_number,title) VALUES ((SELECT id FROM pg_temp.phase2_ids WHERE key='cp'),99,'Rejected session')$test$, '42501', 'new row violates row-level security policy for table "course_sessions"');

RESET ROLE;
-- Reset only this fictional fixture between independent denial scenarios.
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f2c0e100-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f2c0e100-0000-4000-8000-000000000102';
UPDATE private.account_access SET active_session_id='f2c0e100-0000-4000-8000-000000000102' WHERE user_id='f2c0e100-0000-4000-8000-000000000002';

SELECT pg_temp.check_true('denied sessions preserve all fixture content and audit', $test$SELECT (SELECT count(*) FROM public.courses WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='course'))=4 AND (SELECT count(*) FROM public.course_sessions WHERE id IN (SELECT id FROM pg_temp.phase2_ids WHERE kind='session'))=7 AND (SELECT title FROM public.courses WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='cp'))='Edited course' AND (SELECT title FROM public.course_sessions WHERE id=(SELECT id FROM pg_temp.phase2_ids WHERE key='sp'))='Edited session' AND (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000001' AND action LIKE 'content_%')=21 AND (SELECT count(*) FROM private.security_events WHERE actor_id='f2c0e100-0000-4000-8000-000000000002' AND action LIKE 'content_%')=0$test$);

SELECT pg_temp.check_true('storage policies remain scoped after content regression', $test$SELECT count(*)=0 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname NOT IN ('course_covers_read','course_covers_insert','course_covers_delete','material_upload_quarantine_insert')$test$);

-- Report BEFORE rollback; require this JSON result, not absence of an error.
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',130,'tests',jsonb_agg(jsonb_build_object('name',test_name,'outcome',outcome) ORDER BY test_name)) AS phase2_test_report FROM pg_temp.phase2_results;
ROLLBACK;
-- Read-only cleanup proof executes as the original role after rollback.
SELECT
 (SELECT count(*) FROM auth.users WHERE id IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id IN ('f2c0e100-0000-4000-8000-000000000101','f2c0e100-0000-4000-8000-000000000102')) AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_admissions_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE created_by IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_courses_remaining,
 (SELECT count(*) FROM public.course_sessions WHERE created_by IN ('f2c0e100-0000-4000-8000-000000000001','f2c0e100-0000-4000-8000-000000000002')) AS reserved_content_sessions_remaining;
