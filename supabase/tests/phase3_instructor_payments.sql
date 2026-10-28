-- Whole file, one privileged connection, ON_ERROR_STOP=1. Main owns execution.
-- Atomic preflight: insert additive migration just after BEGIN; retain ROLLBACK.
-- Sequential CAS evidence only, NOT real parallel interleavings or checkout acceptance.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE setup_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE setup_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.setup_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.setup_replies TO authenticated;
CREATE FUNCTION pg_temp.setup_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
 EXECUTE p_query INTO STRICT actual;
 IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
 INSERT INTO pg_temp.setup_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.setup_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
 BEGIN EXECUTE p_query;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
 END;
 IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
  RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
 END IF;
 INSERT INTO pg_temp.setup_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.setup_claim(p_user integer) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
 'sub','f3c0e200-0000-4000-8000-'||lpad(p_user::text,12,'0'),
 'session_id','f3c0e200-0000-4000-8000-'||lpad((100+p_user)::text,12,'0'),
 'user_metadata',jsonb_build_object('role','admin','is_admin',true))::text,true);
END;
$helper$;
CREATE FUNCTION pg_temp.setup_reply(p_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$ SELECT value FROM pg_temp.setup_replies WHERE key=p_key; $helper$;
CREATE FUNCTION pg_temp.setup_keys(p_value jsonb,p_keys text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_value) k)=
 (SELECT array_agg(k ORDER BY k) FROM unnest(p_keys) k),false);
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.setup_check(text,text),pg_temp.setup_error(text,text,text,text),
 pg_temp.setup_claim(integer),pg_temp.setup_reply(text),pg_temp.setup_keys(jsonb,text[]) TO authenticated,anon;

SELECT pg_temp.setup_check('all ten new functions closed to public anon service role',$test$
 SELECT count(*)=10 AND bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p WHERE oid IN('private.reject_payment_setup_history_change()'::regprocedure,
 'private.payment_instructor_eligible(uuid)'::regprocedure,'private.read_payment_setup(text,uuid,uuid,integer)'::regprocedure,
 'private.save_my_instructor_payment_profile(text,text,text,integer)'::regprocedure,'private.set_course_payment_instructor(uuid,uuid,integer)'::regprocedure,
 'public.get_my_instructor_payment_profile()'::regprocedure,'public.save_my_instructor_payment_profile(text,text,text,integer)'::regprocedure,
 'public.get_course_payment_instructor(uuid)'::regprocedure,'public.set_course_payment_instructor(uuid,uuid,integer)'::regprocedure,
 'public.list_payment_instructors(uuid,integer)'::regprocedure) $test$);
SELECT pg_temp.setup_check('five public invoker RPCs fixed empty path',$test$
 SELECT count(*)=5 AND bool_and(NOT prosecdef AND proconfig=ARRAY['search_path=""'] AND has_function_privilege('authenticated',p.oid,'EXECUTE'))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND proname IN
 ('get_my_instructor_payment_profile','save_my_instructor_payment_profile','get_course_payment_instructor','set_course_payment_instructor','list_payment_instructors') $test$);
SELECT pg_temp.setup_check('four private tables RLS no direct client or service access',$test$
 SELECT count(*)=4 AND bool_and(relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AND NOT has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))
 FROM pg_class c WHERE oid IN('private.instructor_payment_profiles'::regclass,'private.instructor_payment_profile_history'::regclass,
 'private.course_payment_instructors'::regclass,'private.course_payment_instructor_history'::regclass) $test$);
SELECT pg_temp.setup_check('order creation remains closed at both entry points',$test$
 SELECT count(*)=2 AND bool_and(NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('service_role',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p WHERE oid IN('public.create_pending_order(text,uuid,uuid)'::regprocedure,'private.create_pending_order(text,uuid,uuid)'::regprocedure) $test$);
CREATE TEMP TABLE setup_order_contract AS SELECT pg_get_functiondef('public.get_own_order(uuid)'::regprocedure) AS definition;

-- Privileged, count-only baseline BEFORE any fixture inserts. Match directory
-- eligibility including display availability; never print existing identities/data.
CREATE TEMP TABLE setup_directory_baseline ON COMMIT DROP AS
 SELECT count(*) AS eligible_count
 FROM private.instructor_payment_profiles p JOIN public.profiles d ON d.id=p.instructor_id
 WHERE private.payment_instructor_eligible(p.instructor_id)
 AND char_length(btrim(d.name,' ')) BETWEEN 1 AND 120;
GRANT SELECT ON pg_temp.setup_directory_baseline TO authenticated;

-- Walk every page as the caller, checking exact sizes, projection, strict UUID
-- order and last-item cursors. Expected total bounds traversal; errors disclose
-- no directory values. Results stay in temporary replies, never report output.
CREATE FUNCTION pg_temp.setup_directory_snapshot(p_expected_total bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE v_page jsonb; v_items jsonb; v_item jsonb; v_all jsonb:='[]'::jsonb;
 v_after uuid; v_id uuid; v_seen bigint:=0; v_size integer; v_more boolean;
BEGIN
 LOOP
  v_page:=public.list_payment_instructors(v_after,50);
  IF pg_temp.setup_keys(v_page,ARRAY['items','has_more','next_cursor']) IS DISTINCT FROM true
   OR jsonb_typeof(v_page->'items') IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'FAIL: directory page projection';
  END IF;
  v_items:=v_page->'items';
  v_size:=jsonb_array_length(v_items);
  v_more:=p_expected_total>v_seen+v_size;
  IF v_size<>least(50,p_expected_total-v_seen)
   OR (v_page->'has_more') IS DISTINCT FROM to_jsonb(v_more) THEN
   RAISE EXCEPTION 'FAIL: directory page size or continuation';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
   IF pg_temp.setup_keys(v_item,ARRAY['instructor_id','display_name']) IS DISTINCT FROM true
    OR jsonb_typeof(v_item->'instructor_id') IS DISTINCT FROM 'string'
    OR jsonb_typeof(v_item->'display_name') IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'FAIL: directory item projection';
   END IF;
   v_id:=(v_item->>'instructor_id')::uuid;
   IF v_after IS NOT NULL AND v_id<=v_after THEN
    RAISE EXCEPTION 'FAIL: directory order or duplicate identity';
   END IF;
   v_after:=v_id;
  END LOOP;
  IF (v_page->'next_cursor') IS DISTINCT FROM
   (CASE WHEN v_more THEN jsonb_build_object('instructor_id',v_items->(v_size-1)->>'instructor_id') ELSE 'null'::jsonb END) THEN
   RAISE EXCEPTION 'FAIL: directory cursor must be last returned identity';
  END IF;
  v_all:=v_all||v_items;
  v_seen:=v_seen+v_size;
  EXIT WHEN NOT v_more;
 END LOOP;
 RETURN v_all;
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.setup_directory_snapshot(bigint) TO authenticated;

-- Plain inserts fail on collisions. All later changes are restricted to this prefix.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
 'instructor-setup-'||n::text||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
 jsonb_build_object('name','Display '||n,'role','admin'),false,now(),now() FROM generate_series(1,32) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f3c0e200-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
 ('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM unnest(ARRAY[1,2,3,10]) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_claim(1);
SELECT public.register_device(repeat('a',64),'Setup admin one fixture');
SELECT pg_temp.setup_claim(2);
SELECT public.register_device(repeat('b',64),'Setup admin two fixture');
SELECT pg_temp.setup_claim(3);
SELECT public.register_device(repeat('c',64),'Setup student fixture');
SELECT pg_temp.setup_claim(10);
SELECT public.register_device(repeat('d',64),'Setup overflow fixture');
RESET ROLE;
-- Registration creates these only for admitted fixtures. The remaining payees
-- deliberately have no Auth/app session but need authoritative account/display rows.
INSERT INTO private.account_access(user_id)
SELECT ('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
FROM generate_series(4,32) n WHERE n<>10;
INSERT INTO public.profiles(id,name)
SELECT ('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Display '||n
FROM generate_series(4,32) n WHERE n<>10;
UPDATE private.account_access SET role='admin' WHERE user_id::text LIKE 'f3c0e200-%' AND user_id NOT IN
 ('f3c0e200-0000-4000-8000-000000000003','f3c0e200-0000-4000-8000-000000000005');
UPDATE private.account_access SET disabled=true WHERE user_id='f3c0e200-0000-4000-8000-000000000004';
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='f3c0e200-0000-4000-8000-000000000006';
UPDATE auth.users SET is_anonymous=true WHERE id='f3c0e200-0000-4000-8000-000000000007';
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='f3c0e200-0000-4000-8000-000000000008';
SELECT pg_temp.setup_claim(1);
INSERT INTO public.courses(id,title,description,instructor,category,level,price_piasters,position,status)
SELECT ('f3c0e200-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,'Setup course '||n,
 'Fictional only','Display string is NOT a payee','Engineering','1',12345,n,
 CASE WHEN n=3 THEN 'published' WHEN n=5 THEN 'archived' ELSE 'draft' END FROM generate_series(1,6) n;
UPDATE public.courses SET deleted_at=now() WHERE id='f3c0e200-0000-4000-8000-000000000202';
-- Ineligible remnants and pagination/overflow profiles are privileged fixture setup.
INSERT INTO private.instructor_payment_profiles(instructor_id,recipient_name,phone_number,method_configuration,revision)
SELECT ('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Fictional recipient '||n,'+00000000000',
 'instapay_only',CASE WHEN n=10 THEN 2147483647 ELSE 1 END
FROM generate_series(4,32) n WHERE n<>9;
INSERT INTO private.instructor_payment_profile_history(instructor_id,revision,recipient_name,phone_number,method_configuration,actor_id)
SELECT instructor_id,revision,recipient_name,phone_number,method_configuration,instructor_id
FROM private.instructor_payment_profiles WHERE instructor_id::text LIKE 'f3c0e200-%';
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_claim(1);
SELECT pg_temp.setup_check('own absent profile returns null',$test$ SELECT public.get_my_instructor_payment_profile() IS NULL $test$);
SELECT pg_temp.setup_check('existing draft course absent binding returns null',$test$ SELECT public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201') IS NULL $test$);
INSERT INTO pg_temp.setup_replies VALUES('profile1',public.save_my_instructor_payment_profile('  Fictional One  ','+00000000000','instapay_only',0));
SELECT pg_temp.setup_check('profile exact five fields trimmed own identity revision one',$test$
 SELECT pg_temp.setup_reply('profile1')='{"instructor_id":"f3c0e200-0000-4000-8000-000000000001","recipient_name":"Fictional One","phone_number":"+00000000000","method_configuration":"instapay_only","revision":1}'::jsonb $test$);
SELECT pg_temp.setup_claim(2);
SELECT pg_temp.setup_check('other admin profile read returns own null not others',$test$ SELECT public.get_my_instructor_payment_profile() IS NULL $test$);
INSERT INTO pg_temp.setup_replies VALUES('profile2',public.save_my_instructor_payment_profile('Fictional Two','00000000000','instapay_and_vodafone_cash',0));
SELECT pg_temp.setup_claim(1);
SELECT pg_temp.setup_check('other admin save did not alter own receiving data',$test$ SELECT public.get_my_instructor_payment_profile()=pg_temp.setup_reply('profile1') $test$);
SELECT pg_temp.setup_error('profile stale create revision conflicts',$test$ SELECT public.save_my_instructor_payment_profile('New','0000000','instapay_only',0) $test$,'42501','payment_setup_state_conflict');
INSERT INTO pg_temp.setup_replies VALUES('profile1v2',public.save_my_instructor_payment_profile('Fictional One Updated','00000000001','instapay_and_vodafone_cash',1));
SELECT pg_temp.setup_check('profile update advances one and same number covers both methods',$test$
 SELECT pg_temp.setup_reply('profile1v2')->>'revision'='2' AND pg_temp.setup_reply('profile1v2')->>'phone_number'='00000000001'
 AND pg_temp.setup_reply('profile1v2')->>'method_configuration'='instapay_and_vodafone_cash' $test$);
SELECT pg_temp.setup_error('null profile name invalid',$test$ SELECT public.save_my_instructor_payment_profile(NULL,'0000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('blank profile name invalid',$test$ SELECT public.save_my_instructor_payment_profile('   ','0000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('overlong Unicode codepoint name invalid',$test$ SELECT public.save_my_instructor_payment_profile(repeat(chr(128512),161),'0000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('ASCII control name invalid',$test$ SELECT public.save_my_instructor_payment_profile('A'||chr(10)||'B','0000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('ASCII DEL name invalid',$test$ SELECT public.save_my_instructor_payment_profile('A'||chr(127),'0000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('formatted phone invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name','000 0000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('nonASCII phone digits invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name',repeat(chr(1633),7),'instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('too short phone invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name','000000','instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('too long phone invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name',repeat('0',16),'instapay_only',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('unknown method invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name','0000000','bank',2) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('negative expected revision invalid',$test$ SELECT public.save_my_instructor_payment_profile('Name','0000000','instapay_only',-1) $test$,'22023','invalid_payment_setup_input');
-- U+0085 is not an ASCII control. Do not silently broaden to POSIX cntrl rules.
INSERT INTO pg_temp.setup_replies VALUES('unicode',public.save_my_instructor_payment_profile('A'||chr(133)||'B',repeat('0',15),'instapay_only',2));
SELECT pg_temp.setup_check('nonASCII control retained and fifteen digits accepted',$test$
 SELECT pg_temp.setup_reply('unicode')->>'recipient_name'='A'||chr(133)||'B' AND pg_temp.setup_reply('unicode')->>'revision'='3' $test$);
INSERT INTO pg_temp.setup_replies VALUES('binding1',public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000002',0));
SELECT pg_temp.setup_check('binding exact three fields explicit selected admin',$test$
 SELECT pg_temp.setup_reply('binding1')='{"course_id":"f3c0e200-0000-4000-8000-000000000201","instructor_id":"f3c0e200-0000-4000-8000-000000000002","revision":1}'::jsonb $test$);
SELECT pg_temp.setup_error('stale initial binding revision conflicts',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000001',0) $test$,'42501','payment_setup_state_conflict');
SELECT pg_temp.setup_claim(2);
INSERT INTO pg_temp.setup_replies VALUES('binding2',public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000001',1));
SELECT pg_temp.setup_check('different admin can reassign with current CAS',$test$
 SELECT public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201')->>'revision'='2' AND public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201')->>'instructor_id'='f3c0e200-0000-4000-8000-000000000001' $test$);
SELECT pg_temp.setup_claim(1);
SELECT pg_temp.setup_error('null instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201',NULL,2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('missing instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000999',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('disabled instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000004',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('demoted instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000005',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('unverified instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000006',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('anonymous identity instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000007',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('banned instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000008',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('unconfigured instructor uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000009',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('missing course read unavailable',$test$ SELECT public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000999') $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('deleted course read unavailable',$test$ SELECT public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000202') $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('deleted course assignment unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000202','f3c0e200-0000-4000-8000-000000000001',0) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('null course invalid',$test$ SELECT public.get_course_payment_instructor(NULL) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('null binding revision invalid',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000001',NULL) $test$,'22023','invalid_payment_setup_input');
-- 25 eligible fixtures PLUS the captured real baseline. Many fixtures deliberately
-- have NO Auth/app session. Existing profiles/roles/receiving data are untouched.
INSERT INTO pg_temp.setup_replies VALUES('page1',public.list_payment_instructors());
INSERT INTO pg_temp.setup_replies VALUES('page2',public.list_payment_instructors((pg_temp.setup_reply('page1')->'next_cursor'->>'instructor_id')::uuid));
SELECT pg_temp.setup_check('directory first page twenty exact safe fields',$test$
 SELECT pg_temp.setup_keys(pg_temp.setup_reply('page1'),ARRAY['items','has_more','next_cursor'])
 AND jsonb_array_length(pg_temp.setup_reply('page1')->'items')=least(20,eligible_count+25)
 AND pg_temp.setup_reply('page1')->'has_more'=to_jsonb(eligible_count+25>20)
 AND (SELECT bool_and(pg_temp.setup_keys(item,ARRAY['instructor_id','display_name'])) FROM jsonb_array_elements(pg_temp.setup_reply('page1')->'items') item)
 FROM pg_temp.setup_directory_baseline $test$);
SELECT pg_temp.setup_check('directory cursor last returned not sentinel',$test$
 SELECT pg_temp.setup_reply('page1')->'next_cursor'=jsonb_build_object('instructor_id',pg_temp.setup_reply('page1')->'items'->19->>'instructor_id') $test$);
SELECT pg_temp.setup_check('directory later page baseline aware size continuation and cursor',$test$
 SELECT pg_temp.setup_keys(pg_temp.setup_reply('page2'),ARRAY['items','has_more','next_cursor'])
 AND jsonb_array_length(pg_temp.setup_reply('page2')->'items')=least(20,eligible_count+5)
 AND pg_temp.setup_reply('page2')->'has_more'=to_jsonb(eligible_count+25>40)
 AND pg_temp.setup_reply('page2')->'next_cursor'=CASE WHEN eligible_count+25>40
  THEN jsonb_build_object('instructor_id',pg_temp.setup_reply('page2')->'items'->19->>'instructor_id') ELSE 'null'::jsonb END
 AND (SELECT bool_and(pg_temp.setup_keys(item,ARRAY['instructor_id','display_name'])
  AND (item->>'instructor_id')::uuid>(pg_temp.setup_reply('page1')->'next_cursor'->>'instructor_id')::uuid)
  FROM jsonb_array_elements(pg_temp.setup_reply('page2')->'items') item)
 FROM pg_temp.setup_directory_baseline $test$);
INSERT INTO pg_temp.setup_replies
 SELECT 'directory_all',pg_temp.setup_directory_snapshot(eligible_count+25) FROM pg_temp.setup_directory_baseline;
SELECT pg_temp.setup_check('directory full eligible count excludes bad identities and contains offline admins',$test$
 SELECT jsonb_array_length(pg_temp.setup_reply('directory_all'))=eligible_count+25
 AND pg_temp.setup_reply('page1')->'items'=(SELECT jsonb_agg(value ORDER BY ordinal)
  FROM jsonb_array_elements(pg_temp.setup_reply('directory_all')) WITH ORDINALITY AS items(value,ordinal) WHERE ordinal<=20)
 AND pg_temp.setup_reply('page2')->'items'=(SELECT jsonb_agg(value ORDER BY ordinal)
  FROM jsonb_array_elements(pg_temp.setup_reply('directory_all')) WITH ORDINALITY AS items(value,ordinal) WHERE ordinal BETWEEN 21 AND 40)
 AND (SELECT array_agg(x->>'instructor_id' ORDER BY x->>'instructor_id')
  FROM jsonb_array_elements(pg_temp.setup_reply('directory_all')) x WHERE x->>'instructor_id' LIKE 'f3c0e200-%')=
 (SELECT array_agg('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0') ORDER BY n)
  FROM generate_series(1,32) n WHERE n IN(1,2) OR n BETWEEN 10 AND 32)
 FROM pg_temp.setup_directory_baseline $test$);
SELECT pg_temp.setup_error('directory null limit invalid',$test$ SELECT public.list_payment_instructors(p_limit=>NULL) $test$,'22023','invalid_payment_setup_input');
SELECT pg_temp.setup_error('directory over fifty invalid',$test$ SELECT public.list_payment_instructors(p_limit=>51) $test$,'22023','invalid_payment_setup_input');
RESET ROLE;
UPDATE public.profiles SET name='  Visible'||chr(10)||'Name  ' WHERE id='f3c0e200-0000-4000-8000-000000000002';
UPDATE public.profiles SET name='   ' WHERE id='f3c0e200-0000-4000-8000-000000000011';
UPDATE auth.users SET deleted_at=now() WHERE id='f3c0e200-0000-4000-8000-000000000012';
UPDATE auth.users SET banned_until=now() WHERE id='f3c0e200-0000-4000-8000-000000000013';
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.setup_replies
 SELECT 'directory_changed',pg_temp.setup_directory_snapshot(eligible_count+23) FROM pg_temp.setup_directory_baseline;
SELECT pg_temp.setup_check('directory profile display preserves controls trims spaces no recipient fallback',$test$
 SELECT x->>'display_name'='Visible'||chr(10)||'Name' FROM jsonb_array_elements(pg_temp.setup_reply('directory_changed')) x WHERE x->>'instructor_id'='f3c0e200-0000-4000-8000-000000000002' $test$);
SELECT pg_temp.setup_check('directory excludes blank display and softdeleted payee but ban ending now allowed',$test$
 SELECT jsonb_array_length(pg_temp.setup_reply('directory_changed'))=eligible_count+23
 AND (SELECT array_agg(x->>'instructor_id' ORDER BY x->>'instructor_id')
  FROM jsonb_array_elements(pg_temp.setup_reply('directory_changed')) x WHERE x->>'instructor_id' LIKE 'f3c0e200-%')=
 (SELECT array_agg('f3c0e200-0000-4000-8000-'||lpad(n::text,12,'0') ORDER BY n)
  FROM generate_series(1,32) n WHERE (n IN(1,2) OR n BETWEEN 10 AND 32) AND n NOT IN(11,12))
 FROM pg_temp.setup_directory_baseline $test$);
SELECT pg_temp.setup_error('softdeleted payee assignment uniform unavailable',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000012',2) $test$,'42501','payment_setup_target_unavailable');
SELECT pg_temp.setup_error('other admin cannot directly inspect current profile data',$test$ SELECT * FROM private.instructor_payment_profiles $test$,'42501','permission denied for table instructor_payment_profiles');
SELECT pg_temp.setup_error('profile history private even to other admin',$test$ SELECT * FROM private.instructor_payment_profile_history $test$,'42501','permission denied for table instructor_payment_profile_history');
SELECT pg_temp.setup_error('direct profile write denied',$test$ UPDATE private.instructor_payment_profiles SET recipient_name='Tampered' $test$,'42501','permission denied for table instructor_payment_profiles');
RESET ROLE;
SELECT pg_temp.setup_check('profile history preserves original details and accepted revisions',$test$
 SELECT count(*)=3 AND bool_and(actor_id=instructor_id) AND min(revision)=1 AND max(revision)=3
 AND count(*) FILTER(WHERE revision=1 AND recipient_name='Fictional One' AND phone_number='+00000000000')=1
 FROM private.instructor_payment_profile_history WHERE instructor_id='f3c0e200-0000-4000-8000-000000000001' $test$);
SELECT pg_temp.setup_check('binding history preserves original and replacement payees',$test$
 SELECT count(*)=2 AND count(*) FILTER(WHERE revision=1 AND instructor_id='f3c0e200-0000-4000-8000-000000000002')=1
 AND count(*) FILTER(WHERE revision=2 AND instructor_id='f3c0e200-0000-4000-8000-000000000001')=1
 FROM private.course_payment_instructor_history WHERE course_id='f3c0e200-0000-4000-8000-000000000201' $test$);
SELECT pg_temp.setup_check('safe audit identifiers only one event per accepted change',$test$
 SELECT count(*)=6 AND bool_and(CASE action WHEN 'instructor_payment_profile_saved' THEN pg_temp.setup_keys(details,ARRAY['instructor_id','revision']) ELSE pg_temp.setup_keys(details,ARRAY['course_id','instructor_id','revision']) END)
 FROM private.security_events WHERE actor_id::text LIKE 'f3c0e200-%' AND action IN('instructor_payment_profile_saved','course_payment_instructor_set') $test$);
SELECT pg_temp.setup_error('profile history immutable privileged update',$test$ UPDATE private.instructor_payment_profile_history SET recipient_name='No' WHERE instructor_id='f3c0e200-0000-4000-8000-000000000001' $test$,'42501','payment_setup_state_conflict');
SELECT pg_temp.setup_error('binding history immutable privileged delete',$test$ DELETE FROM private.course_payment_instructor_history WHERE course_id='f3c0e200-0000-4000-8000-000000000201' $test$,'42501','payment_setup_state_conflict');
INSERT INTO private.course_payment_instructors(course_id,instructor_id,revision) VALUES
 ('f3c0e200-0000-4000-8000-000000000204','f3c0e200-0000-4000-8000-000000000001',2147483647);
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_error('binding revision overflow rejected',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000204','f3c0e200-0000-4000-8000-000000000002',2147483647) $test$,'42501','payment_setup_state_conflict');
SELECT pg_temp.setup_claim(10);
SELECT pg_temp.setup_error('profile revision overflow rejected',$test$ SELECT public.save_my_instructor_payment_profile('No','0000000','instapay_only',2147483647) $test$,'42501','payment_setup_state_conflict');
RESET ROLE;
SELECT pg_temp.setup_check('overflow preserves current history and audit counts',$test$
 SELECT (SELECT revision FROM private.instructor_payment_profiles WHERE instructor_id='f3c0e200-0000-4000-8000-000000000010')=2147483647
 AND NOT EXISTS(SELECT 1 FROM private.course_payment_instructor_history WHERE course_id='f3c0e200-0000-4000-8000-000000000204')
 AND (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f3c0e200-%' AND action IN('instructor_payment_profile_saved','course_payment_instructor_set'))=6 $test$);
-- Fictional audit failure only. Trigger and all test objects roll back with the suite.
CREATE FUNCTION pg_temp.fail_setup_audit() RETURNS trigger LANGUAGE plpgsql AS $helper$
BEGIN
 IF NEW.actor_id='f3c0e200-0000-4000-8000-000000000001' AND NEW.action IN('instructor_payment_profile_saved','course_payment_instructor_set') THEN
  RAISE EXCEPTION 'fixture_setup_audit_failure' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$helper$;
CREATE TRIGGER fixture_setup_audit_failure BEFORE INSERT ON private.security_events FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_setup_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_claim(1);
SELECT pg_temp.setup_error('profile audit failure rejects change',$test$ SELECT public.save_my_instructor_payment_profile('Not committed','0000000','instapay_only',3) $test$,'23514','fixture_setup_audit_failure');
SELECT pg_temp.setup_error('binding audit failure rejects initial assignment',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000206','f3c0e200-0000-4000-8000-000000000002',0) $test$,'23514','fixture_setup_audit_failure');
RESET ROLE;
DROP TRIGGER fixture_setup_audit_failure ON private.security_events;
SELECT pg_temp.setup_check('audit failure rolls back profile binding histories and events',$test$
 SELECT (SELECT revision FROM private.instructor_payment_profiles WHERE instructor_id='f3c0e200-0000-4000-8000-000000000001')=3
 AND (SELECT count(*) FROM private.instructor_payment_profile_history WHERE instructor_id='f3c0e200-0000-4000-8000-000000000001')=3
 AND NOT EXISTS(SELECT 1 FROM private.course_payment_instructors WHERE course_id='f3c0e200-0000-4000-8000-000000000206')
 AND NOT EXISTS(SELECT 1 FROM private.course_payment_instructor_history WHERE course_id='f3c0e200-0000-4000-8000-000000000206')
 AND (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f3c0e200-%' AND action IN('instructor_payment_profile_saved','course_payment_instructor_set'))=6 $test$);

CREATE FUNCTION pg_temp.setup_denied(p_label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
 PERFORM pg_temp.setup_error(p_label||' profile read denied',$test$ SELECT public.get_my_instructor_payment_profile() $test$,'42501','payment_setup_access_required');
 PERFORM pg_temp.setup_error(p_label||' profile save denied',$test$ SELECT public.save_my_instructor_payment_profile('No','0000000','instapay_only',0) $test$,'42501','payment_setup_access_required');
 PERFORM pg_temp.setup_error(p_label||' binding read denied',$test$ SELECT public.get_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201') $test$,'42501','payment_setup_access_required');
 PERFORM pg_temp.setup_error(p_label||' binding save denied',$test$ SELECT public.set_course_payment_instructor('f3c0e200-0000-4000-8000-000000000201','f3c0e200-0000-4000-8000-000000000002',2) $test$,'42501','payment_setup_access_required');
 PERFORM pg_temp.setup_error(p_label||' directory denied',$test$ SELECT public.list_payment_instructors() $test$,'42501','payment_setup_access_required');
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.setup_denied(text) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_claim(3);
SELECT pg_temp.setup_denied('student forged admin metadata');
RESET ROLE;
UPDATE private.account_access SET disabled=true WHERE user_id='f3c0e200-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_claim(1);
SELECT pg_temp.setup_denied('disabled admin');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f3c0e200-0000-4000-8000-000000000001';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f3c0e200-0000-4000-8000-000000000101';
SET LOCAL ROLE authenticated;
SELECT pg_temp.setup_denied('ended admin admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f3c0e200-0000-4000-8000-000000000101';
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{}';
SELECT pg_temp.setup_error('anonymous setup EXECUTE denied',$test$ SELECT public.list_payment_instructors() $test$,'42501','permission denied for function list_payment_instructors');
RESET ROLE;
SELECT pg_temp.setup_check('order projection definition unchanged and no fixture orders created',$test$
 SELECT (SELECT definition FROM pg_temp.setup_order_contract)=pg_get_functiondef('public.get_own_order(uuid)'::regprocedure)
 AND NOT EXISTS(SELECT 1 FROM private.pending_orders WHERE buyer_id::text LIKE 'f3c0e200-%')
 AND NOT EXISTS(SELECT 1 FROM private.pending_order_operations WHERE actor_id::text LIKE 'f3c0e200-%') $test$);
DO $count$ BEGIN
 IF (SELECT count(*) FROM pg_temp.setup_results)<>79 THEN RAISE EXCEPTION 'FAIL: expected exactly 79 instructor payment assertions'; END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',79,
 'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase3_instructor_payments_report FROM pg_temp.setup_results;
ROLLBACK;
-- Existing relations only, including during additive-schema preflight rollback.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f3c0e200-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f3c0e200-%' OR user_id::text LIKE 'f3c0e200-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f3c0e200-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f3c0e200-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f3c0e200-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f3c0e200-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f3c0e200-%' OR subject_id::text LIKE 'f3c0e200-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f3c0e200-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM private.pending_orders WHERE buyer_id::text LIKE 'f3c0e200-%') AS reserved_orders_remaining,
 (SELECT count(*) FROM private.pending_order_operations WHERE actor_id::text LIKE 'f3c0e200-%') AS reserved_operations_remaining;
