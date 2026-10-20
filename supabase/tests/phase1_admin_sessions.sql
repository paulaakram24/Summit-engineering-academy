-- Whole file, one privileged connection, stop-on-error; fixtures always ROLLBACK.
-- Main may insert the frozen admin_parallel_sessions migration immediately after BEGIN
-- for atomic schema+fixture preflight. No Auth API, Storage mutation or owner reset.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE admin_session_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE admin_session_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.admin_session_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.admin_session_replies TO authenticated;

CREATE FUNCTION pg_temp.admin_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.admin_session_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.admin_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.admin_session_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.admin_claim(p_user integer,p_session integer) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
    'sub','f1a5e200-0000-4000-8000-'||lpad(p_user::text,12,'0'),
    'session_id','f1a5e200-0000-4000-8000-'||lpad(p_session::text,12,'0'),
    'user_metadata',jsonb_build_object('role','admin','is_admin',true),
    'app_metadata',jsonb_build_object('role','admin'))::text,true);
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.admin_check(text,text),pg_temp.admin_error(text,text,text,text),
  pg_temp.admin_claim(integer,integer) TO authenticated,anon;

-- Collision-failing fictional accounts only; forged metadata never sets account_access.role.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f1a5e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
  'admin-sessions-'||n::text||'@example.invalid',now(),'{"provider":"email","role":"admin"}'::jsonb,
  '{"name":"Fictional admission fixture","role":"admin","is_admin":true}'::jsonb,false,now(),now()
FROM generate_series(1,3) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f1a5e200-0000-4000-8000-'||lpad((100*u+s)::text,12,'0'))::uuid,
  ('f1a5e200-0000-4000-8000-'||lpad(u::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM (VALUES(1,8),(2,4),(3,3)) users(u,session_count)
CROSS JOIN LATERAL generate_series(1,session_count) s;
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,101);
SELECT pg_temp.admin_check('forged metadata initial admin fixture remains student',$test$ SELECT public.register_device(repeat('a',64),'Fixture A')->>'role'='student' $test$);
SELECT pg_temp.admin_claim(2,201);
SELECT public.register_device(repeat('a',64),'Fixture student A');
SELECT pg_temp.admin_check('student ignores both metadata admin claims',$test$ SELECT public.get_access_context()->>'role'='student' AND private.is_active() AND NOT private.is_admin() $test$);
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f1a5e200-0000-4000-8000-000000000001';
INSERT INTO private.account_access(user_id,role) VALUES('f1a5e200-0000-4000-8000-000000000003','admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,101);
SELECT pg_temp.admin_check('existing admitted session becomes actual server admin',$test$ SELECT private.is_active() AND private.is_admin() AND public.get_access_context()->>'role'='admin' $test$);
SELECT pg_temp.admin_claim(1,102);
SELECT pg_temp.admin_check('second concurrent admin installation admitted',$test$ SELECT public.register_device(repeat('b',64),'Fixture B')->>'role'='admin' $test$);
SELECT pg_temp.admin_claim(1,103);
SELECT pg_temp.admin_check('third concurrent admin installation admitted',$test$ SELECT public.register_device(repeat('c',64),'Fixture C')->>'role'='admin' $test$);
SELECT pg_temp.admin_claim(1,104);
SELECT pg_temp.admin_check('fourth concurrent admin installation admitted',$test$ SELECT public.register_device(repeat('d',64),'Fixture D')->>'role'='admin' $test$);
SELECT pg_temp.admin_claim(1,105);
SELECT pg_temp.admin_check('same admin installation allows another Auth session',$test$ SELECT public.register_device(repeat('a',64),'Fixture shared A')->>'role'='admin' $test$);
INSERT INTO pg_temp.admin_session_replies VALUES('repeat',public.register_device(repeat('a',64),'Ignored rename'));
SELECT pg_temp.admin_check('admin repeat admission returns own context idempotently',$test$ SELECT value=public.get_access_context() FROM pg_temp.admin_session_replies WHERE key='repeat' $test$);
SELECT pg_temp.admin_error('admin cannot swap an existing session device',$test$ SELECT public.register_device(repeat('b',64),'Wrong binding') $test$,'42501','session_device_mismatch');
RESET ROLE;
SELECT pg_temp.admin_check('five admissions four devices and exactly five start audits',$test$ SELECT (SELECT count(*) FROM private.session_access WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND ended_at IS NULL)=5 AND (SELECT count(*) FROM private.devices WHERE user_id='f1a5e200-0000-4000-8000-000000000001')=4 AND (SELECT count(*) FROM private.security_events WHERE subject_id='f1a5e200-0000-4000-8000-000000000001' AND action='session_started')=5 $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,103);
SELECT pg_temp.admin_check('nonpointer admin context remains active with exact response fields',$test$ SELECT private.is_active() AND public.get_access_context()->>'role'='admin' AND public.get_access_context() ?& ARRAY['role','device_id'] AND (SELECT count(*) FROM jsonb_object_keys(public.get_access_context()))=2 $test$);
-- The exact own-device binding is checked privileged, not by granting private table reads.
RESET ROLE;
SELECT pg_temp.admin_check('context device matches current JWT admission not legacy pointer',$test$ SELECT (public.get_access_context()->>'device_id')::uuid=x.device_id AND x.session_id<>a.active_session_id FROM private.session_access x JOIN private.account_access a ON a.user_id=x.user_id WHERE x.session_id='f1a5e200-0000-4000-8000-000000000103' $test$);
UPDATE private.account_access SET disabled=true WHERE user_id='f1a5e200-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_check('disabled admin has no admission exemption',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() AND (SELECT count(*) FROM public.profiles WHERE id=auth.uid())=0 $test$);
SELECT pg_temp.admin_error('disabled admin registration denied',$test$ SELECT public.register_device(repeat('e',64),'Disabled') $test$,'42501','account_disabled');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f1a5e200-0000-4000-8000-000000000001';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND token_hash=sha256(convert_to(repeat('c',64),'UTF8'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_check('revoked admin installation loses current access',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() $test$);
SELECT pg_temp.admin_error('revoked admin cannot register again',$test$ SELECT public.register_device(repeat('c',64),'Revoked') $test$,'42501','device_revoked');
SELECT pg_temp.admin_claim(1,105);
SELECT pg_temp.admin_check('revocation preserves another installation',$test$ SELECT private.is_active() AND public.get_access_context()->>'role'='admin' $test$);
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND token_hash=sha256(convert_to(repeat('c',64),'UTF8'));
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id='f1a5e200-0000-4000-8000-000000000103';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,103);
SELECT pg_temp.admin_check('expired admin Auth session cannot read',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() $test$);
SELECT pg_temp.admin_error('expired admin context denied',$test$ SELECT public.get_access_context() $test$,'42501','unverified_or_invalid_session');
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id='f1a5e200-0000-4000-8000-000000000103';
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='f1a5e200-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_error('unverified admin registration denied',$test$ SELECT public.register_device(repeat('c',64),'Unverified') $test$,'42501','unverified_or_invalid_session');
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=now(),banned_until=now()+interval '1 hour' WHERE id='f1a5e200-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_check('banned admin cannot use existing admission',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() $test$);
RESET ROLE;
UPDATE auth.users SET banned_until=NULL WHERE id='f1a5e200-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,201);
SELECT pg_temp.admin_error('another user Auth session not admitted as admin',$test$ SELECT public.register_device(repeat('a',64),'Cross user') $test$,'42501','unverified_or_invalid_session');
SELECT pg_temp.admin_claim(1,101);
SELECT public.end_session();
SELECT public.end_session();
SELECT pg_temp.admin_error('logged out admin session cannot resurrect',$test$ SELECT public.register_device(repeat('a',64),'Ended') $test$,'42501','session_replaced');
SELECT pg_temp.admin_claim(1,105);
SELECT pg_temp.admin_check('local admin logout preserves same-device peer',$test$ SELECT private.is_active() AND public.get_access_context()->>'role'='admin' $test$);
RESET ROLE;
SELECT pg_temp.admin_check('admin logout ends exactly one admission and audit once',$test$ SELECT (SELECT count(*) FROM private.session_access WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND ended_at IS NULL)=4 AND (SELECT count(*) FROM private.security_events WHERE subject_id='f1a5e200-0000-4000-8000-000000000001' AND action='session_ended')=1 AND (SELECT active_session_id IS NULL FROM private.account_access WHERE user_id='f1a5e200-0000-4000-8000-000000000001') $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,106);
SELECT public.end_session();
SELECT public.end_session();
SELECT pg_temp.admin_error('admin logout before registration blocks delayed admission',$test$ SELECT public.register_device(repeat('f',64),'Cancelled') $test$,'42501','session_replaced');
RESET ROLE;
SELECT pg_temp.admin_check('unregistered admin logout has deviceless tombstone audit once',$test$ SELECT (SELECT device_id IS NULL AND ended_at IS NOT NULL FROM private.session_access WHERE session_id='f1a5e200-0000-4000-8000-000000000106') AND (SELECT count(*) FROM private.security_events WHERE subject_id='f1a5e200-0000-4000-8000-000000000001' AND action='session_ended')=2 AND (SELECT count(*) FROM private.devices WHERE user_id='f1a5e200-0000-4000-8000-000000000001')=4 $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,105);
INSERT INTO pg_temp.admin_session_replies VALUES('null_pointer_repeat',public.register_device(repeat('a',64),'Repeat'));
SELECT pg_temp.admin_check('admin works with null pointer and retry adds no start',$test$ SELECT private.is_active() AND value=public.get_access_context() FROM pg_temp.admin_session_replies WHERE key='null_pointer_repeat' $test$);
SELECT pg_temp.admin_claim(2,202);
SELECT pg_temp.admin_error('student competing session still blocked',$test$ SELECT public.register_device(repeat('b',64),'Student B') $test$,'42501','active_session_exists');
SELECT pg_temp.admin_claim(2,201);
SELECT public.end_session();
SELECT pg_temp.admin_claim(2,202);
SELECT pg_temp.admin_check('student second installation after logout allowed',$test$ SELECT public.register_device(repeat('b',64),'Student B')->>'role'='student' $test$);
SELECT public.end_session();
SELECT pg_temp.admin_claim(2,203);
SELECT pg_temp.admin_error('student third registered installation still blocked',$test$ SELECT public.register_device(repeat('c',64),'Student C') $test$,'42501','device_limit');
SELECT public.register_device(repeat('a',64),'Student A');
SELECT pg_temp.admin_check('student existing installation may return',$test$ SELECT public.get_access_context()->>'role'='student' AND private.is_active() AND NOT private.is_admin() $test$);
SELECT pg_temp.admin_error('student cannot change authoritative role',$test$ UPDATE private.account_access SET role='admin' WHERE user_id=auth.uid() $test$,'42501','permission denied for table account_access');
RESET ROLE;
UPDATE private.account_access SET active_session_id=NULL WHERE user_id='f1a5e200-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_check('student remains tied to single active pointer',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() $test$);
RESET ROLE;
UPDATE private.account_access SET active_session_id='f1a5e200-0000-4000-8000-000000000203' WHERE user_id='f1a5e200-0000-4000-8000-000000000002';
UPDATE private.account_access SET role='student' WHERE user_id='f1a5e200-0000-4000-8000-000000000001';
SELECT pg_temp.admin_check('demotion closes all admin admissions without choosing devices',$test$ SELECT (SELECT count(*) FROM private.session_access WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND ended_at IS NULL)=0 AND (SELECT active_session_id IS NULL AND role='student' FROM private.account_access WHERE user_id='f1a5e200-0000-4000-8000-000000000001') AND (SELECT count(*) FROM private.devices WHERE user_id='f1a5e200-0000-4000-8000-000000000001' AND revoked_at IS NULL)=4 AND (SELECT count(*) FROM private.security_events WHERE subject_id='f1a5e200-0000-4000-8000-000000000001' AND action='admin_admissions_ended_on_demotion')=1 $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(1,105);
SELECT pg_temp.admin_check('stale admin JWT cannot exempt demoted account',$test$ SELECT NOT private.is_active() AND NOT private.is_admin() $test$);
SELECT pg_temp.admin_error('demoted ended admission cannot reenter',$test$ SELECT public.register_device(repeat('a',64),'Demoted old') $test$,'42501','session_replaced');
SELECT pg_temp.admin_claim(1,107);
SELECT pg_temp.admin_error('demoted excess devices block even existing installation',$test$ SELECT public.register_device(repeat('a',64),'Demoted fresh') $test$,'42501','device_limit');
RESET ROLE;
-- Explicit fixture-only remediation. No production device is selected or revoked.
UPDATE private.devices SET revoked_at=now() WHERE user_id='f1a5e200-0000-4000-8000-000000000001'
  AND token_hash<>sha256(convert_to(repeat('a',64),'UTF8'));
SET LOCAL ROLE authenticated;
SELECT public.register_device(repeat('a',64),'Remediated');
SELECT pg_temp.admin_check('demoted account can reenter only under student policy',$test$ SELECT public.get_access_context()->>'role'='student' AND private.is_active() AND NOT private.is_admin() $test$);
SELECT pg_temp.admin_claim(1,108);
SELECT pg_temp.admin_error('demoted account second simultaneous session blocked',$test$ SELECT public.register_device(repeat('a',64),'Competing remediated') $test$,'42501','active_session_exists');
SELECT pg_temp.admin_claim(3,301);
SELECT public.register_device(repeat('a',64),'Two-device admin A');
SELECT pg_temp.admin_claim(3,302);
SELECT public.register_device(repeat('b',64),'Two-device admin B');
RESET ROLE;
UPDATE private.account_access SET role='student' WHERE user_id='f1a5e200-0000-4000-8000-000000000003';
SELECT pg_temp.admin_check('two-device demotion ends admissions retains devices',$test$ SELECT (SELECT count(*) FROM private.session_access WHERE user_id='f1a5e200-0000-4000-8000-000000000003' AND ended_at IS NULL)=0 AND (SELECT count(*) FROM private.devices WHERE user_id='f1a5e200-0000-4000-8000-000000000003' AND revoked_at IS NULL)=2 $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(3,303);
SELECT public.register_device(repeat('b',64),'Fresh student');
SELECT pg_temp.admin_check('two-device demotion admits fresh student session',$test$ SELECT public.get_access_context()->>'role'='student' AND private.is_active() AND NOT private.is_admin() $test$);
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f1a5e200-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SELECT pg_temp.admin_claim(3,301);
SELECT pg_temp.admin_check('promotion does not resurrect ended admin sessions',$test$ SELECT NOT private.is_active() $test$);
RESET ROLE;
SELECT pg_temp.admin_check('private helpers preserve security definer grants and empty paths',$test$ SELECT count(*)=4 AND bool_and(prosecdef AND proconfig=ARRAY['search_path=""'] AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('is_active','get_access_context','register_device','end_session') $test$);
SELECT pg_temp.admin_check('demotion trigger not directly callable and device tombstone constraint retained',$test$ SELECT NOT has_function_privilege('authenticated','private.close_admin_admissions_on_demotion()','EXECUTE') AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.session_access'::regclass AND conname='session_requires_device_or_ended') $test$);
SELECT pg_temp.admin_check('initial five starts plus one fresh demoted admission audited once',$test$ SELECT count(*)=6 AND count(DISTINCT details->>'device_id')=4 FROM private.security_events WHERE subject_id='f1a5e200-0000-4000-8000-000000000001' AND action='session_started' $test$);

DO $count$ BEGIN
  IF (SELECT count(*) FROM pg_temp.admin_session_results)<>46 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 46 admin-session assertions';
  END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',46,
  'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase1_admin_sessions_report
FROM pg_temp.admin_session_results;
ROLLBACK;
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f1a5e200-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f1a5e200-%' OR user_id::text LIKE 'f1a5e200-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f1a5e200-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f1a5e200-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f1a5e200-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f1a5e200-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f1a5e200-%' OR subject_id::text LIKE 'f1a5e200-%') AS reserved_events_remaining;
