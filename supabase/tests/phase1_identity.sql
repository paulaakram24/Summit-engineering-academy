-- Phase 1 integration regression: submit this ENTIRE file as one execute_sql query.
-- Requires privileged fixture setup; never run individual fragments. No Auth API/email calls.
-- Target: supabase/migrations/20261016060804_phase1_identity.sql
-- Requires: supabase/migrations/20261016110640_logout_before_registration.sql
BEGIN;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SET LOCAL row_security = on;
-- Clear legacy claim GUCs, which can otherwise override request.jwt.claims.
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claim.role = '';
SET LOCAL request.jwt.claims = '{}';

CREATE TEMP TABLE phase1_results (
  test_name text PRIMARY KEY,
  outcome text NOT NULL CHECK (outcome = 'PASS')
) ON COMMIT DROP;
GRANT SELECT, INSERT ON pg_temp.phase1_results TO authenticated, anon;

-- All helpers are SECURITY INVOKER: dynamic SQL retains the current test role.
CREATE FUNCTION pg_temp.check_true(test_name text, query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL [%]: expected true, got %', test_name, actual;
  END IF;
  INSERT INTO pg_temp.phase1_results VALUES (test_name, 'PASS');
END
$helper$;

CREATE FUNCTION pg_temp.expect_error(test_name text, query text,
                                    expected_state text, expected_message text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  -- ONLY the tested statement is inside the exception handler.
  BEGIN
    EXECUTE query;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_state = RETURNED_SQLSTATE, got_message = MESSAGE_TEXT;
  END;
  IF got_state IS NULL THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, statement succeeded',
      test_name, expected_state, expected_message;
  END IF;
  IF got_state <> expected_state OR got_message <> expected_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',
      test_name, expected_state, expected_message, got_state, got_message;
  END IF;
  INSERT INTO pg_temp.phase1_results VALUES (test_name, 'PASS');
END
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.check_true(text,text),
  pg_temp.expect_error(text,text,text,text) TO authenticated, anon;

-- Reserved fictional identities. Plain INSERT deliberately aborts on collisions.
INSERT INTO auth.users
  (id, aud, role, email, email_confirmed_at, banned_until,
   raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at)
VALUES
  ('f1a5e100-0000-4000-8000-000000000001','authenticated','authenticated','phase1-1@example.invalid',
   now(),NULL,
   '{"provider":"email","providers":["email"]}',
   '{"name":"Fictional 1","role":"admin","is_admin":true}',false,now(),now()),
  ('f1a5e100-0000-4000-8000-000000000002','authenticated','authenticated','phase1-2@example.invalid',
   now(),NULL,
   '{"provider":"email","providers":["email"]}',
   '{"name":"Fictional 2","role":"admin","is_admin":true}',false,now(),now()),
  ('f1a5e100-0000-4000-8000-000000000003','authenticated','authenticated','phase1-3@example.invalid',
   NULL,NULL,
   '{"provider":"email","providers":["email"]}',
   '{"name":"Fictional 3","role":"admin","is_admin":true}',false,now(),now()),
  ('f1a5e100-0000-4000-8000-000000000004','authenticated','authenticated','phase1-4@example.invalid',
   now(),now() + interval '1 day',
   '{"provider":"email","providers":["email"]}',
   '{"name":"Fictional 4","role":"admin","is_admin":true}',false,now(),now());
INSERT INTO auth.sessions (id,user_id,created_at,updated_at,not_after)
VALUES
  ('f1a5e100-0000-4000-8000-000000000101','f1a5e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000102','f1a5e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000103','f1a5e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000104','f1a5e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000105','f1a5e100-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000201','f1a5e100-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000301','f1a5e100-0000-4000-8000-000000000003',now(),now(),now()+interval '1 hour'),
  ('f1a5e100-0000-4000-8000-000000000401','f1a5e100-0000-4000-8000-000000000004',now(),now(),now()+interval '1 hour');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000002","session_id":"f1a5e100-0000-4000-8000-000000000201","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.check_true('bob register', $test$SELECT public.register_device(repeat('b',64),'Fictional test device')->>'role' = 'student'$test$);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('unregistered context', $test$SELECT public.get_access_context()$test$, '42501', 'session_not_registered');
SELECT pg_temp.check_true('alice register ignores raw metadata role', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')->>'role' = 'student'$test$);
SELECT pg_temp.check_true('own profile read', $test$SELECT count(*)=1 FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001' AND name='Fictional 1'$test$);
SELECT pg_temp.check_true('own profile update', $test$WITH changed AS (UPDATE public.profiles SET name='Updated Fictional',phone='000-test',university='Fictional Academy' WHERE id='f1a5e100-0000-4000-8000-000000000001' RETURNING *) SELECT count(*)=1 AND bool_and(name='Updated Fictional' AND phone='000-test' AND university='Fictional Academy') FROM changed$test$);
SELECT pg_temp.check_true('cross user read', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000002') denied$test$);
SELECT pg_temp.check_true('cross user update', $test$WITH changed AS (UPDATE public.profiles SET name='Intrusion' WHERE id='f1a5e100-0000-4000-8000-000000000002' RETURNING id) SELECT count(*)=0 FROM changed$test$);
SELECT pg_temp.check_true('jwt metadata role escalation ineffective', $test$SELECT public.get_access_context()->>'role' = 'student'$test$);
SELECT pg_temp.expect_error('profile id update denied', $test$UPDATE public.profiles SET id='f1a5e100-0000-4000-8000-000000000002' WHERE id='f1a5e100-0000-4000-8000-000000000001'$test$, '42501', 'permission denied for table profiles');
SELECT pg_temp.expect_error('private account_access select denied', $test$SELECT * FROM private.account_access$test$, '42501', 'permission denied for table account_access');
SELECT pg_temp.expect_error('private account_access delete denied', $test$DELETE FROM private.account_access WHERE false$test$, '42501', 'permission denied for table account_access');
SELECT pg_temp.expect_error('private devices select denied', $test$SELECT * FROM private.devices$test$, '42501', 'permission denied for table devices');
SELECT pg_temp.expect_error('private devices delete denied', $test$DELETE FROM private.devices WHERE false$test$, '42501', 'permission denied for table devices');
SELECT pg_temp.expect_error('private session_access select denied', $test$SELECT * FROM private.session_access$test$, '42501', 'permission denied for table session_access');
SELECT pg_temp.expect_error('private session_access delete denied', $test$DELETE FROM private.session_access WHERE false$test$, '42501', 'permission denied for table session_access');
SELECT pg_temp.expect_error('private security_events select denied', $test$SELECT * FROM private.security_events$test$, '42501', 'permission denied for table security_events');
SELECT pg_temp.expect_error('private security_events delete denied', $test$DELETE FROM private.security_events WHERE false$test$, '42501', 'permission denied for table security_events');
SELECT pg_temp.expect_error('private role update denied', $test$UPDATE private.account_access SET role='admin' WHERE user_id='f1a5e100-0000-4000-8000-000000000001'$test$, '42501', 'permission denied for table account_access');
SELECT pg_temp.expect_error('valid_session helper not client callable', $test$SELECT private.valid_session()$test$, '42501', 'permission denied for function valid_session');
SELECT pg_temp.check_true('active same device idempotent', $test$SELECT (public.register_device(repeat('a',64),'Changed label') = public.get_access_context())$test$);
SELECT pg_temp.expect_error('active session cannot swap device', $test$SELECT public.register_device(repeat('c',64),'Fictional test device')$test$, '42501', 'session_device_mismatch');
RESET ROLE;
SELECT pg_temp.check_true('failed swap leaves one device', $test$SELECT count(*)=1 FROM private.devices WHERE user_id='f1a5e100-0000-4000-8000-000000000001'$test$);
SELECT pg_temp.check_true('idempotent one start event', $test$SELECT count(*)=1 FROM private.security_events WHERE subject_id='f1a5e100-0000-4000-8000-000000000001' AND action='session_started'$test$);
SELECT pg_temp.check_true('cross update left bob intact', $test$SELECT name='Fictional 2' FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000002'$test$);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('sequential competing login blocked', $test$SELECT public.register_device(repeat('c',64),'Fictional test device')$test$, '42501', 'active_session_exists');
SELECT pg_temp.expect_error('competing session has no context', $test$SELECT public.get_access_context()$test$, '42501', 'session_not_registered');
SELECT pg_temp.check_true('competing session no profile', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001') denied$test$);
-- Cancel a valid, unregistered session while Alice's first session is still active.
-- No prior logout for Alice has occurred, so one total logout event proves deduplication.
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000105"}';
SELECT public.end_session();
SELECT public.end_session();
SELECT pg_temp.expect_error('logout before registration prevents delayed register', $test$SELECT public.register_device(repeat('e',64),'Cancelled fictional device')$test$, '42501', 'session_replaced');
RESET ROLE;
SELECT pg_temp.check_true('unregistered logout leaves ended deviceless tombstone', $test$SELECT count(*)=1 FROM private.session_access WHERE session_id='f1a5e100-0000-4000-8000-000000000105' AND user_id='f1a5e100-0000-4000-8000-000000000001' AND device_id IS NULL AND ended_at IS NOT NULL$test$);
SELECT pg_temp.check_true('unregistered repeated logout logs exactly once', $test$SELECT count(*)=1 FROM private.security_events WHERE actor_id='f1a5e100-0000-4000-8000-000000000001' AND subject_id='f1a5e100-0000-4000-8000-000000000001' AND action='session_ended'$test$);
SELECT pg_temp.check_true('unregistered logout preserves first active pointer', $test$SELECT active_session_id='f1a5e100-0000-4000-8000-000000000101'::uuid FROM private.account_access WHERE user_id='f1a5e100-0000-4000-8000-000000000001'$test$);
SELECT pg_temp.check_true('cancelled registration creates no device', $test$SELECT count(*)=1 FROM private.devices WHERE user_id='f1a5e100-0000-4000-8000-000000000001'$test$);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000101","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.check_true('first session remains active', $test$SELECT public.get_access_context()->>'role'='student'$test$);
SELECT pg_temp.check_true('first session reads profile after spare session logout', $test$SELECT count(*)=1 FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001' AND name='Updated Fictional'$test$);
SELECT public.end_session();
SELECT pg_temp.expect_error('ended context denied', $test$SELECT public.get_access_context()$test$, '42501', 'session_replaced');
SELECT pg_temp.expect_error('ended session cannot re-register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'session_replaced');
SELECT pg_temp.check_true('ended profile read denied', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001') denied$test$);
SELECT pg_temp.check_true('ended profile update denied', $test$WITH changed AS (UPDATE public.profiles SET name='Intrusion' WHERE id='f1a5e100-0000-4000-8000-000000000001' RETURNING id) SELECT count(*)=0 FROM changed$test$);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000102","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.check_true('second device after logout', $test$SELECT public.register_device(repeat('c',64),'Fictional test device')->>'role'='student'$test$);
SELECT public.end_session();
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('third registered device denied', $test$SELECT public.register_device(repeat('d',64),'Fictional test device')$test$, '42501', 'device_limit');
SELECT pg_temp.check_true('existing device can return after logout', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')->>'role'='student'$test$);
SELECT pg_temp.expect_error('existing different device cannot swap active binding', $test$SELECT public.register_device(repeat('c',64),'Fictional test device')$test$, '42501', 'session_device_mismatch');
RESET ROLE;
SELECT pg_temp.check_true('exactly two devices retained across logouts', $test$SELECT count(*)=2 FROM private.devices WHERE user_id='f1a5e100-0000-4000-8000-000000000001' AND revoked_at IS NULL$test$);
SELECT pg_temp.check_true('active binding still original token', $test$SELECT count(*)=1 FROM private.session_access x JOIN private.devices d ON d.id=x.device_id WHERE x.session_id='f1a5e100-0000-4000-8000-000000000103' AND d.token_hash=sha256(convert_to(repeat('a',64),'UTF8'))$test$);
SELECT pg_temp.check_true('ended write left alice intact', $test$SELECT name='Updated Fictional' FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001'$test$);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000003","session_id":"f1a5e100-0000-4000-8000-000000000301","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('unverified register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('unverified context', $test$SELECT public.get_access_context()$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('unverified logout', $test$SELECT public.end_session()$test$, '42501', 'unverified_or_invalid_session');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000004","session_id":"f1a5e100-0000-4000-8000-000000000401","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('banned register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('banned context', $test$SELECT public.get_access_context()$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('banned logout', $test$SELECT public.end_session()$test$, '42501', 'unverified_or_invalid_session');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('missing uid', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'authentication_required');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('missing session id', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000201","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('other user auth session', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000104","user_metadata":{"role":"admin","is_admin":true}}';
RESET ROLE;
DELETE FROM auth.sessions WHERE id='f1a5e100-0000-4000-8000-000000000104';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000104","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('deleted unregistered session', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';
RESET ROLE;
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f1a5e100-0000-4000-8000-000000000103';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('expired session register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('expired session context', $test$SELECT public.get_access_context()$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('expired session logout', $test$SELECT public.end_session()$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.check_true('expired session profile denied', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001') denied$test$);
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f1a5e100-0000-4000-8000-000000000103';
UPDATE private.account_access SET disabled=true WHERE user_id='f1a5e100-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('disabled register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'account_disabled');
SELECT pg_temp.expect_error('disabled context', $test$SELECT public.get_access_context()$test$, '42501', 'session_replaced');
SELECT pg_temp.check_true('disabled profile denied', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001') denied$test$);
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f1a5e100-0000-4000-8000-000000000001';
DELETE FROM auth.sessions WHERE id='f1a5e100-0000-4000-8000-000000000103';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000001","session_id":"f1a5e100-0000-4000-8000-000000000103","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.expect_error('deleted registered session context', $test$SELECT public.get_access_context()$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.expect_error('deleted registered session register', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'unverified_or_invalid_session');
SELECT pg_temp.check_true('deleted session profile denied', $test$SELECT count(*)=0 FROM (SELECT * FROM public.profiles WHERE id='f1a5e100-0000-4000-8000-000000000001') denied$test$);
RESET ROLE;
SELECT pg_temp.check_true('storage objects RLS enabled', $test$SELECT relrowsecurity FROM pg_class WHERE oid='storage.objects'::regclass$test$);
SELECT pg_temp.check_true('phase1 storage allows only named cover policies', $test$SELECT count(*)=0 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname NOT IN ('course_covers_read','course_covers_insert','course_covers_delete')$test$);
SELECT pg_temp.check_true('all three buckets private', $test$SELECT count(*)=3 AND bool_and(NOT public) FROM storage.buckets WHERE id IN ('course-materials','payment-receipts','assignment-submissions')$test$);
INSERT INTO storage.objects (bucket_id,name) VALUES ('course-materials','phase1-regression/fictional-fixture.txt');
INSERT INTO storage.objects (bucket_id,name) VALUES ('payment-receipts','phase1-regression/fictional-fixture.txt');
INSERT INTO storage.objects (bucket_id,name) VALUES ('assignment-submissions','phase1-regression/fictional-fixture.txt');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f1a5e100-0000-4000-8000-000000000002","session_id":"f1a5e100-0000-4000-8000-000000000201","user_metadata":{"role":"admin","is_admin":true}}';
SELECT pg_temp.check_true('course-materials storage read denied', $test$SELECT count(*)=0 FROM (SELECT * FROM storage.objects WHERE bucket_id='course-materials' AND name='phase1-regression/fictional-fixture.txt') denied$test$);
SELECT pg_temp.check_true('course-materials storage update denied', $test$WITH changed AS (UPDATE storage.objects SET name='phase1-regression/changed.txt' WHERE bucket_id='course-materials' AND name='phase1-regression/fictional-fixture.txt' RETURNING id) SELECT count(*)=0 FROM changed$test$);
-- Direct DELETE is blocked by storage.protect_delete(), not an RLS row-count check.
SELECT pg_temp.expect_error('course-materials storage delete denied', $test$DELETE FROM storage.objects WHERE bucket_id='course-materials' AND name='phase1-regression/fictional-fixture.txt'$test$, '42501', 'Direct deletion from storage tables is not allowed. Use the Storage API instead.');
SELECT pg_temp.expect_error('course-materials storage insert denied', $test$INSERT INTO storage.objects(bucket_id,name) VALUES ('course-materials','phase1-regression/denied.txt')$test$, '42501', 'new row violates row-level security policy for table "objects"');
SELECT pg_temp.check_true('payment-receipts storage read denied', $test$SELECT count(*)=0 FROM (SELECT * FROM storage.objects WHERE bucket_id='payment-receipts' AND name='phase1-regression/fictional-fixture.txt') denied$test$);
SELECT pg_temp.check_true('payment-receipts storage update denied', $test$WITH changed AS (UPDATE storage.objects SET name='phase1-regression/changed.txt' WHERE bucket_id='payment-receipts' AND name='phase1-regression/fictional-fixture.txt' RETURNING id) SELECT count(*)=0 FROM changed$test$);
-- Direct DELETE is blocked by storage.protect_delete(), not an RLS row-count check.
SELECT pg_temp.expect_error('payment-receipts storage delete denied', $test$DELETE FROM storage.objects WHERE bucket_id='payment-receipts' AND name='phase1-regression/fictional-fixture.txt'$test$, '42501', 'Direct deletion from storage tables is not allowed. Use the Storage API instead.');
SELECT pg_temp.expect_error('payment-receipts storage insert denied', $test$INSERT INTO storage.objects(bucket_id,name) VALUES ('payment-receipts','phase1-regression/denied.txt')$test$, '42501', 'new row violates row-level security policy for table "objects"');
SELECT pg_temp.check_true('assignment-submissions storage read denied', $test$SELECT count(*)=0 FROM (SELECT * FROM storage.objects WHERE bucket_id='assignment-submissions' AND name='phase1-regression/fictional-fixture.txt') denied$test$);
SELECT pg_temp.check_true('assignment-submissions storage update denied', $test$WITH changed AS (UPDATE storage.objects SET name='phase1-regression/changed.txt' WHERE bucket_id='assignment-submissions' AND name='phase1-regression/fictional-fixture.txt' RETURNING id) SELECT count(*)=0 FROM changed$test$);
-- Direct DELETE is blocked by storage.protect_delete(), not an RLS row-count check.
SELECT pg_temp.expect_error('assignment-submissions storage delete denied', $test$DELETE FROM storage.objects WHERE bucket_id='assignment-submissions' AND name='phase1-regression/fictional-fixture.txt'$test$, '42501', 'Direct deletion from storage tables is not allowed. Use the Storage API instead.');
SELECT pg_temp.expect_error('assignment-submissions storage insert denied', $test$INSERT INTO storage.objects(bucket_id,name) VALUES ('assignment-submissions','phase1-regression/denied.txt')$test$, '42501', 'new row violates row-level security policy for table "objects"');
RESET ROLE;
SELECT pg_temp.check_true('storage fixture rows intact', $test$SELECT count(*)=3 FROM storage.objects WHERE bucket_id IN ('course-materials','payment-receipts','assignment-submissions') AND name='phase1-regression/fictional-fixture.txt'$test$);
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '{}';
SELECT pg_temp.expect_error('anon register_device denied', $test$SELECT public.register_device(repeat('a',64),'Fictional test device')$test$, '42501', 'permission denied for function register_device');
SELECT pg_temp.expect_error('anon get_access_context denied', $test$SELECT public.get_access_context()$test$, '42501', 'permission denied for function get_access_context');
SELECT pg_temp.expect_error('anon end_session denied', $test$SELECT public.end_session()$test$, '42501', 'permission denied for function end_session');
RESET ROLE;
-- A successful result is emitted BEFORE rollback. No permanent test helpers.
SELECT jsonb_build_object(
  'suite','phase1_identity',
  'status','PASS',
  'passed',count(*),
  'tests',jsonb_agg(jsonb_build_object('test',test_name,'status',outcome) ORDER BY test_name)
) AS phase1_test_report
FROM pg_temp.phase1_results;
ROLLBACK;
