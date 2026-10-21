-- Main executes the WHOLE file on one privileged connection with ON_ERROR_STOP=1.
-- Atomic preflight: insert migration immediately after BEGIN; retain ROLLBACK.
-- No checkout policy, payment, owner mutation, Storage or delivery acceptance.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE order_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE order_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.order_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.order_replies TO authenticated;
CREATE FUNCTION pg_temp.order_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
  EXECUTE p_query INTO STRICT actual;
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
  INSERT INTO pg_temp.order_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.order_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
  END;
  IF got_state IS DISTINCT FROM p_state OR got_message IS DISTINCT FROM p_message THEN
    RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
  END IF;
  INSERT INTO pg_temp.order_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.order_claim(p_user integer) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
    'sub','f3c0e100-0000-4000-8000-'||lpad(p_user::text,12,'0'),
    'session_id','f3c0e100-0000-4000-8000-'||lpad((100+p_user)::text,12,'0'),
    'user_metadata',jsonb_build_object('role','admin','is_admin',true))::text,true);
END;
$helper$;
CREATE FUNCTION pg_temp.order_reply(p_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT value FROM pg_temp.order_replies WHERE key=p_key;
$helper$;
CREATE FUNCTION pg_temp.order_keys(p_value jsonb,p_keys text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_value) k)=
   (SELECT array_agg(k ORDER BY k) FROM unnest(p_keys) k),false);
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.order_check(text,text),pg_temp.order_error(text,text,text,text),
 pg_temp.order_claim(integer),pg_temp.order_reply(text),pg_temp.order_keys(jsonb,text[]) TO authenticated,anon;

-- Assert shipped closure BEFORE temporarily granting anything, even in this rollback.
SELECT pg_temp.order_check('creation closed at wrapper and private helper',$test$
 SELECT count(*)=2 AND bool_and(NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p WHERE p.oid IN('public.create_pending_order(text,uuid,uuid)'::regprocedure,'private.create_pending_order(text,uuid,uuid)'::regprocedure) $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_error('shipped wrapper denies authenticated creation',$test$
 SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'42501','permission denied for function create_pending_order');
SELECT pg_temp.order_error('shipped helper denies authenticated bypass',$test$
 SELECT private.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'42501','permission denied for function create_pending_order');
RESET ROLE;
SELECT pg_temp.order_check('public RPCs invoker correct volatility and empty paths',$test$
 SELECT count(*)=3 AND bool_and(NOT prosecdef AND proconfig=ARRAY['search_path=""']
 AND provolatile::text=CASE WHEN proname='create_pending_order' THEN 'v' ELSE 's' END)
 FROM pg_proc WHERE oid IN('public.create_pending_order(text,uuid,uuid)'::regprocedure,
 'public.get_own_order(uuid)'::regprocedure,'public.list_own_orders(timestamptz,uuid,integer)'::regprocedure) $test$);
SELECT pg_temp.order_check('creation helper private definer empty path',$test$
 SELECT prosecdef AND proconfig=ARRAY['search_path=""'] FROM pg_proc WHERE oid='private.create_pending_order(text,uuid,uuid)'::regprocedure $test$);
SELECT pg_temp.order_check('creation accepts only kind target operation never buyer or price',$test$
 SELECT count(*)=2 AND bool_and(pronargs=3 AND proargnames=ARRAY['p_kind','p_target_id','p_operation_id']::text[])
 FROM pg_proc WHERE oid IN('public.create_pending_order(text,uuid,uuid)'::regprocedure,'private.create_pending_order(text,uuid,uuid)'::regprocedure) $test$);
SELECT pg_temp.order_check('both private tables RLS enabled owner policies no admin exception',$test$
 SELECT (SELECT count(*)=2 AND bool_and(relrowsecurity) FROM pg_class WHERE oid IN('private.pending_orders'::regclass,'private.pending_order_operations'::regclass))
 AND (SELECT count(*)=2 AND bool_and(cmd='SELECT' AND roles=ARRAY['authenticated']::name[] AND qual LIKE '%is_active%' AND qual NOT LIKE '%is_admin%') FROM pg_policies WHERE schemaname='private' AND tablename IN('pending_orders','pending_order_operations')) $test$);
SELECT pg_temp.order_check('narrow own history SELECT no client writes or ledger access',$test$
 SELECT has_table_privilege('authenticated','private.pending_orders','SELECT')
 AND NOT has_table_privilege('authenticated','private.pending_orders','INSERT,UPDATE,DELETE,TRUNCATE')
 AND NOT has_table_privilege('authenticated','private.pending_order_operations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 AND NOT has_table_privilege('anon','private.pending_orders','SELECT,INSERT,UPDATE,DELETE') $test$);
SELECT pg_temp.order_check('history RPC authenticated only not anonymous or public',$test$
 SELECT count(*)=2 AND bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p WHERE oid IN('public.get_own_order(uuid)'::regprocedure,'public.list_own_orders(timestamptz,uuid,integer)'::regprocedure) $test$);

-- Plain inserts fail on collisions. Only reserved fictional identities are changed.
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT ('f3c0e100-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
 'pending-order-'||n::text||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
 '{"name":"Fictional pending-order fixture","role":"admin"}'::jsonb,false,now(),now()
FROM generate_series(1,3) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT ('f3c0e100-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
 ('f3c0e100-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now(),now(),now()+interval '1 hour'
FROM generate_series(1,3) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_claim(1);
SELECT public.register_device(repeat('a',64),'Pending-order admin fixture');
SELECT pg_temp.order_claim(2);
SELECT public.register_device(repeat('b',64),'Pending-order student fixture');
SELECT pg_temp.order_claim(3);
SELECT public.register_device(repeat('c',64),'Pending-order other fixture');
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id='f3c0e100-0000-4000-8000-000000000001';
SELECT pg_temp.order_claim(1);
INSERT INTO public.courses(id,title,description,instructor,category,level,price_piasters,position,status)
SELECT ('f3c0e100-0000-4000-8000-'||lpad((200+n)::text,12,'0'))::uuid,
 'Order course '||n::text,'Never copy this live description','Fictional instructor','Engineering','1',
 CASE n WHEN 5 THEN 0 WHEN 6 THEN 2147483647 ELSE 12345 END,n,
 CASE n WHEN 2 THEN 'draft' WHEN 3 THEN 'archived' ELSE 'published' END
FROM generate_series(1,6) n;
UPDATE public.courses SET deleted_at=now() WHERE id='f3c0e100-0000-4000-8000-000000000204';
INSERT INTO public.course_sessions(id,course_id,session_number,title,description,price_piasters,position,status)
SELECT ('f3c0e100-0000-4000-8000-'||lpad((300+n)::text,12,'0'))::uuid,
 CASE WHEN n=5 THEN 'f3c0e100-0000-4000-8000-000000000202'::uuid ELSE 'f3c0e100-0000-4000-8000-000000000201'::uuid END,
 n,'Order session '||n::text,'Never copy this session description',5678,n,
 CASE n WHEN 2 THEN 'draft' WHEN 3 THEN 'archived' ELSE 'published' END
FROM generate_series(1,5) n;
UPDATE public.course_sessions SET deleted_at=now() WHERE id='f3c0e100-0000-4000-8000-000000000304';
-- Rollback-only test enablement; this is NEVER part of the migration or rollout.
GRANT EXECUTE ON FUNCTION public.create_pending_order(text,uuid,uuid),private.create_pending_order(text,uuid,uuid) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_claim(2);
SELECT pg_temp.order_check('student authority ignores forged metadata',$test$
 SELECT private.is_active() AND NOT private.is_admin() AND public.get_access_context()->>'role'='student' $test$);
SELECT pg_temp.order_check('empty own history terminal envelope',$test$
 SELECT public.list_own_orders()='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
INSERT INTO pg_temp.order_replies VALUES
 ('course',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401')),
 ('session',public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000301','f3c0e100-0000-4000-8000-000000000402')),
 ('zero',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000205','f3c0e100-0000-4000-8000-000000000403')),
 ('max',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000206','f3c0e100-0000-4000-8000-000000000404'));
SELECT pg_temp.order_check('exact ten order fields no buyer ledger or media metadata',$test$
 SELECT bool_and(pg_temp.order_keys(value,ARRAY['id','kind','course_id','session_id','course_title_snapshot','session_title_snapshot','price_piasters','currency','state','created_at'])) FROM pg_temp.order_replies $test$);
SELECT pg_temp.order_check('course UUID title server price currency pending exact',$test$
 SELECT pg_temp.order_reply('course')-ARRAY['id','created_at']=
 '{"kind":"course","course_id":"f3c0e100-0000-4000-8000-000000000201","session_id":null,"course_title_snapshot":"Order course 1","session_title_snapshot":null,"price_piasters":12345,"currency":"EGP","state":"pending"}'::jsonb
 AND (pg_temp.order_reply('course')->>'id')::uuid IS NOT NULL AND (pg_temp.order_reply('course')->>'created_at')::timestamptz=now() $test$);
SELECT pg_temp.order_check('session retains exact immutable parent UUID and own price',$test$
 SELECT pg_temp.order_reply('session')-ARRAY['id','created_at']=
 '{"kind":"session","course_id":"f3c0e100-0000-4000-8000-000000000201","session_id":"f3c0e100-0000-4000-8000-000000000301","course_title_snapshot":"Order course 1","session_title_snapshot":"Order session 1","price_piasters":5678,"currency":"EGP","state":"pending"}'::jsonb $test$);
SELECT pg_temp.order_check('zero price remains only pending intent',$test$
 SELECT pg_temp.order_reply('zero')->'price_piasters'='0'::jsonb AND pg_temp.order_reply('zero')->>'state'='pending' AND (SELECT count(*) FROM public.session_materials)=0 $test$);
SELECT pg_temp.order_check('int32 maximum price safely snapshotted',$test$
 SELECT pg_temp.order_reply('max')->'price_piasters'='2147483647'::jsonb $test$);
INSERT INTO pg_temp.order_replies VALUES('retry',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401'));
SELECT pg_temp.order_check('same operation returns original snapshot',$test$
 SELECT pg_temp.order_reply('retry')=pg_temp.order_reply('course') $test$);
SELECT pg_temp.order_error('operation changed target rejected',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000205','f3c0e100-0000-4000-8000-000000000401') $test$,'22023','order_operation_reused');
SELECT pg_temp.order_error('operation changed kind rejected',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'22023','order_operation_reused');
SELECT pg_temp.order_error('null kind invalid',$test$ SELECT public.create_pending_order(NULL,'f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000410') $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('bundle kind not supported',$test$ SELECT public.create_pending_order('bundle','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000410') $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('null target invalid',$test$ SELECT public.create_pending_order('course',NULL,'f3c0e100-0000-4000-8000-000000000410') $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('null operation invalid',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201',NULL) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('null history order ID invalid',$test$ SELECT public.get_own_order(NULL) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('draft course unavailable',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000202','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('archived course unavailable',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000203','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('deleted course unavailable',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000204','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('missing course unavailable',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000999','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('draft session unavailable',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000302','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('archived session unavailable',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000303','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('deleted session unavailable',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000304','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('published session under draft course unavailable',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000305','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_error('missing session unavailable',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000999','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
-- Repeated distinct operations below are pagination fixtures, NOT approved checkout policy.
INSERT INTO pg_temp.order_replies
SELECT 'extra_'||n::text,public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201',
 ('f3c0e100-0000-4000-8000-'||lpad((500+n)::text,12,'0'))::uuid) FROM generate_series(1,21) n;
INSERT INTO pg_temp.order_replies VALUES('page1',public.list_own_orders());
INSERT INTO pg_temp.order_replies VALUES('page2',public.list_own_orders(
 (pg_temp.order_reply('page1')->'next_cursor'->>'created_at')::timestamptz,
 (pg_temp.order_reply('page1')->'next_cursor'->>'id')::uuid));
SELECT pg_temp.order_check('first page twenty with exact envelope',$test$
 SELECT pg_temp.order_keys(pg_temp.order_reply('page1'),ARRAY['items','has_more','next_cursor']) AND jsonb_array_length(pg_temp.order_reply('page1')->'items')=20 AND pg_temp.order_reply('page1')->'has_more'='true'::jsonb $test$);
SELECT pg_temp.order_check('cursor last returned row not lookahead',$test$
 SELECT pg_temp.order_reply('page1')->'next_cursor'=jsonb_build_object('created_at',pg_temp.order_reply('page1')->'items'->19->>'created_at','id',pg_temp.order_reply('page1')->'items'->19->>'id') $test$);
SELECT pg_temp.order_check('second page five terminal cursor',$test$
 SELECT jsonb_array_length(pg_temp.order_reply('page2')->'items')=5 AND pg_temp.order_reply('page2')->'has_more'='false'::jsonb AND pg_temp.order_reply('page2')->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.order_check('tied timestamps paginate all UUIDs descending without duplicates',$test$
 SELECT count(*)=25 AND count(DISTINCT item->>'id')=25
 AND bool_and(previous_id IS NULL OR previous_id>(item->>'id')::uuid)
 FROM (SELECT item,lag((item->>'id')::uuid) OVER(ORDER BY seq) previous_id FROM (
 SELECT item,ord AS seq FROM jsonb_array_elements(pg_temp.order_reply('page1')->'items') WITH ORDINALITY x(item,ord)
 UNION ALL SELECT item,ord+20 FROM jsonb_array_elements(pg_temp.order_reply('page2')->'items') WITH ORDINALITY x(item,ord)) all_items) ordered $test$);
SELECT pg_temp.order_check('max fifty and exact-limit page have terminal cursor',$test$
 SELECT jsonb_array_length(public.list_own_orders(p_limit=>50)->'items')=25 AND public.list_own_orders(p_limit=>25)->'next_cursor'='null'::jsonb $test$);
SELECT pg_temp.order_error('null page limit invalid',$test$ SELECT public.list_own_orders(p_limit=>NULL) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('zero page limit invalid',$test$ SELECT public.list_own_orders(p_limit=>0) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('over fifty page limit invalid',$test$ SELECT public.list_own_orders(p_limit=>51) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('cursor date requires ID',$test$ SELECT public.list_own_orders(p_before_created_at=>now()) $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('cursor ID requires date',$test$ SELECT public.list_own_orders(p_before_id=>'f3c0e100-0000-4000-8000-000000000999') $test$,'22023','invalid_order_input');
SELECT pg_temp.order_error('infinite cursor invalid',$test$ SELECT public.list_own_orders('infinity','f3c0e100-0000-4000-8000-000000000999') $test$,'22023','invalid_order_input');
SELECT pg_temp.order_claim(3);
SELECT pg_temp.order_check('cross-owner detail indistinguishable from missing',$test$
 SELECT public.get_own_order((pg_temp.order_reply('course')->>'id')::uuid) IS NULL AND public.get_own_order('f3c0e100-0000-4000-8000-000000000999') IS NULL AND public.list_own_orders()='{"items":[],"has_more":false,"next_cursor":null}'::jsonb $test$);
INSERT INTO pg_temp.order_replies VALUES('other',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401'));
SELECT pg_temp.order_check('operation UUID scoped to actor not borrowed response',$test$
 SELECT pg_temp.order_reply('other')->>'id'<>pg_temp.order_reply('course')->>'id' AND jsonb_array_length(public.list_own_orders()->'items')=1 $test$);
SELECT pg_temp.order_claim(1);
SELECT pg_temp.order_error('admin purchase denied even in test enabled mode',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'42501','order_student_required');
SELECT pg_temp.order_check('admin cannot inspect other buyer orders',$test$
 SELECT count(*)=0 AND public.get_own_order((pg_temp.order_reply('course')->>'id')::uuid) IS NULL FROM private.pending_orders $test$);
RESET ROLE;
SELECT pg_temp.order_check('one order operation and safe audit per committed creation',$test$
 SELECT (SELECT count(*) FROM private.pending_orders WHERE buyer_id::text LIKE 'f3c0e100-%')=26
 AND (SELECT count(*) FROM private.pending_order_operations WHERE actor_id::text LIKE 'f3c0e100-%')=26
 AND (SELECT count(*)=26 AND bool_and(pg_temp.order_keys(details,ARRAY['order_id','operation_id'])) FROM private.security_events WHERE actor_id::text LIKE 'f3c0e100-%' AND action='pending_order_created') $test$);
SELECT pg_temp.order_check('restrictive history FKs and indexed ownership course session',$test$
 SELECT (SELECT count(*)=5 AND bool_and(confdeltype='r') FROM pg_constraint WHERE conrelid IN('private.pending_orders'::regclass,'private.pending_order_operations'::regclass) AND contype='f')
 AND (SELECT count(*)=3 FROM pg_indexes WHERE schemaname='private' AND indexname IN('pending_orders_buyer_history_idx','pending_orders_course_idx','pending_orders_session_idx')) $test$);
SELECT pg_temp.order_error('order snapshot immutable even privileged update',$test$ UPDATE private.pending_orders SET price_piasters=1 WHERE buyer_id='f3c0e100-0000-4000-8000-000000000002' $test$,'42501','order_immutable');
SELECT pg_temp.order_error('completed operation immutable even privileged delete',$test$ DELETE FROM private.pending_order_operations WHERE actor_id='f3c0e100-0000-4000-8000-000000000002' $test$,'42501','order_immutable');
SELECT pg_temp.order_claim(1);
UPDATE public.courses SET title='Changed unpublished title',price_piasters=99999,deleted_at=now() WHERE id='f3c0e100-0000-4000-8000-000000000201';
UPDATE public.course_sessions SET title='Changed unpublished session',price_piasters=88888 WHERE id='f3c0e100-0000-4000-8000-000000000301';
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_claim(2);
INSERT INTO pg_temp.order_replies VALUES('hidden_retry',public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401'));
SELECT pg_temp.order_check('retry after removal price and title change original snapshot',$test$
 SELECT pg_temp.order_reply('hidden_retry')=pg_temp.order_reply('course') AND public.get_own_order((pg_temp.order_reply('session')->>'id')::uuid)=pg_temp.order_reply('session') $test$);
SELECT pg_temp.order_error('new session intent denied once parent removed',$test$ SELECT public.create_pending_order('session','f3c0e100-0000-4000-8000-000000000301','f3c0e100-0000-4000-8000-000000000410') $test$,'42501','order_target_unavailable');
SELECT pg_temp.order_check('hidden history contains original snapshots not current metadata',$test$
 SELECT jsonb_array_length(public.list_own_orders(p_limit=>50)->'items')=25
 AND public.list_own_orders(p_limit=>50)::text NOT LIKE '%Changed unpublished%'
 AND public.list_own_orders(p_limit=>50)::text NOT LIKE '%Never copy%' $test$);
SELECT pg_temp.order_error('direct client price tampering denied',$test$ UPDATE private.pending_orders SET price_piasters=0 WHERE buyer_id=auth.uid() $test$,'42501','permission denied for table pending_orders');
SELECT pg_temp.order_error('client cannot forge operation ledger',$test$ SELECT * FROM private.pending_order_operations $test$,'42501','permission denied for table pending_order_operations');
RESET ROLE;
-- Fail only this fictional actor's pending-order audit, inside the rollback fixture.
CREATE FUNCTION pg_temp.fail_pending_order_audit() RETURNS trigger LANGUAGE plpgsql AS $helper$
BEGIN
 IF NEW.action='pending_order_created' AND NEW.actor_id='f3c0e100-0000-4000-8000-000000000002' THEN
   RAISE EXCEPTION 'fixture_order_audit_failure' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$helper$;
CREATE TRIGGER fixture_pending_order_audit_failure BEFORE INSERT ON private.security_events
 FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_pending_order_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_error('audit failure aborts creation',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000205','f3c0e100-0000-4000-8000-000000000410') $test$,'23514','fixture_order_audit_failure');
RESET ROLE;
DROP TRIGGER fixture_pending_order_audit_failure ON private.security_events;
SELECT pg_temp.order_check('audit failure rolls back order ledger and event together',$test$
 SELECT (SELECT count(*) FROM private.pending_orders WHERE buyer_id='f3c0e100-0000-4000-8000-000000000002')=25
 AND NOT EXISTS(SELECT 1 FROM private.pending_order_operations WHERE actor_id='f3c0e100-0000-4000-8000-000000000002' AND operation_id='f3c0e100-0000-4000-8000-000000000410')
 AND (SELECT count(*) FROM private.security_events WHERE actor_id='f3c0e100-0000-4000-8000-000000000002' AND action='pending_order_created')=25 $test$);

-- Two checks per denied context; sequential mutations and reads use separate statements.
CREATE FUNCTION pg_temp.order_denied(p_label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
 PERFORM pg_temp.order_error(p_label||' create denied',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'42501','order_access_required');
 PERFORM pg_temp.order_error(p_label||' list denied',$test$ SELECT public.list_own_orders() $test$,'42501','order_access_required');
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.order_denied(text) TO authenticated;
UPDATE private.account_access SET disabled=true WHERE user_id='f3c0e100-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_denied('disabled student');
SELECT pg_temp.order_error('disabled student detail denied',$test$ SELECT public.get_own_order((pg_temp.order_reply('course')->>'id')::uuid) $test$,'42501','order_access_required');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id='f3c0e100-0000-4000-8000-000000000002';
UPDATE private.devices SET revoked_at=now() WHERE user_id='f3c0e100-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_denied('revoked device');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id='f3c0e100-0000-4000-8000-000000000002';
UPDATE private.session_access SET ended_at=now() WHERE session_id='f3c0e100-0000-4000-8000-000000000102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_denied('ended admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id='f3c0e100-0000-4000-8000-000000000102';
UPDATE private.account_access SET role='admin' WHERE user_id='f3c0e100-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.order_error('promoted buyer cannot replay creation as admin',$test$ SELECT public.create_pending_order('course','f3c0e100-0000-4000-8000-000000000201','f3c0e100-0000-4000-8000-000000000401') $test$,'42501','order_student_required');
SELECT pg_temp.order_check('promoted buyer retains own history without other buyers',$test$
 SELECT public.get_own_order((pg_temp.order_reply('course')->>'id')::uuid)=pg_temp.order_reply('course') AND jsonb_array_length(public.list_own_orders(p_limit=>50)->'items')=25 AND public.get_own_order((pg_temp.order_reply('other')->>'id')::uuid) IS NULL $test$);
RESET ROLE;
-- Restore the real deployment's CLOSED privilege state before the final report.
REVOKE ALL ON FUNCTION public.create_pending_order(text,uuid,uuid),private.create_pending_order(text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{}';
SELECT pg_temp.order_error('anonymous history EXECUTE denied',$test$ SELECT public.list_own_orders() $test$,'42501','permission denied for function list_own_orders');
RESET ROLE;
SELECT pg_temp.order_check('fixture grants removed creation remains closed',$test$
 SELECT NOT has_function_privilege('authenticated','public.create_pending_order(text,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','private.create_pending_order(text,uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.create_pending_order(text,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('service_role','private.create_pending_order(text,uuid,uuid)','EXECUTE') $test$);
DO $count$ BEGIN
 IF (SELECT count(*) FROM pg_temp.order_results)<>70 THEN RAISE EXCEPTION 'FAIL: expected exactly 70 pending order assertions'; END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',70,
 'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase3_pending_orders_report
FROM pg_temp.order_results;
ROLLBACK;
-- Existing relations only: also works when the new tables disappear after preflight.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f3c0e100-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f3c0e100-%' OR user_id::text LIKE 'f3c0e100-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f3c0e100-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f3c0e100-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f3c0e100-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f3c0e100-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f3c0e100-%' OR subject_id::text LIKE 'f3c0e100-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f3c0e100-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM public.course_sessions WHERE id::text LIKE 'f3c0e100-%') AS reserved_content_sessions_remaining;
