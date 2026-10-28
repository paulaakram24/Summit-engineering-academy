-- Whole file, one privileged connection, ON_ERROR_STOP=1. Main owns execution.
-- Insert additive migration immediately after BEGIN for atomic rollback preflight.
-- Storage fixtures below are transactional METADATA, NOT real uploaded binaries.
-- No Storage deletion, owner account changes, delivery, scan or concurrency claim.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL row_security=on;
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
SET LOCAL request.jwt.claims='{}';
CREATE TEMP TABLE upload_results(name text PRIMARY KEY,outcome text NOT NULL CHECK(outcome='PASS')) ON COMMIT DROP;
CREATE TEMP TABLE upload_replies(key text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT DROP;
GRANT SELECT,INSERT ON pg_temp.upload_results TO authenticated,anon;
GRANT SELECT,INSERT ON pg_temp.upload_replies TO authenticated;
CREATE FUNCTION pg_temp.upload_check(p_name text,p_query text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE actual boolean;
BEGIN
 EXECUTE p_query INTO STRICT actual;
 IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL [%]: expected true, got %',p_name,actual; END IF;
 INSERT INTO pg_temp.upload_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.upload_error(p_name text,p_query text,p_state text,p_message text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $helper$
DECLARE got_state text; got_message text;
BEGIN
 BEGIN EXECUTE p_query;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got_state=RETURNED_SQLSTATE,got_message=MESSAGE_TEXT;
 END;
 IF got_state IS DISTINCT FROM p_state OR (p_message IS NOT NULL AND got_message IS DISTINCT FROM p_message) THEN
  RAISE EXCEPTION 'FAIL [%]: expected % / %, got % / %',p_name,p_state,p_message,got_state,got_message;
 END IF;
 INSERT INTO pg_temp.upload_results VALUES(p_name,'PASS');
END;
$helper$;
CREATE FUNCTION pg_temp.upload_id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $helper$
 SELECT ('f2c0e700-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$helper$;
CREATE FUNCTION pg_temp.upload_claim(n integer) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.upload_id(n),
 'session_id',pg_temp.upload_id(n+100),'user_metadata',jsonb_build_object('role','admin','is_admin',true))::text,true);
END;
$helper$;
CREATE FUNCTION pg_temp.upload_reply(p_key text) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT value FROM pg_temp.upload_replies WHERE key=p_key;
$helper$;
CREATE FUNCTION pg_temp.upload_asset(p_key text) RETURNS uuid LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT (pg_temp.upload_reply(p_key)->>'asset_id')::uuid;
$helper$;
CREATE FUNCTION pg_temp.upload_path(p_key text) RETURNS text LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT pg_temp.upload_reply(p_key)->>'path';
$helper$;
CREATE FUNCTION pg_temp.upload_keys(p_value jsonb,p_keys text[]) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $helper$
 SELECT coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_value) k)=
 (SELECT array_agg(k ORDER BY k) FROM unnest(p_keys) k),false);
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.upload_check(text,text),pg_temp.upload_error(text,text,text,text),pg_temp.upload_id(integer),
 pg_temp.upload_claim(integer),pg_temp.upload_reply(text),pg_temp.upload_asset(text),pg_temp.upload_path(text),pg_temp.upload_keys(jsonb,text[]) TO authenticated,anon;

INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
SELECT pg_temp.upload_id(n),'authenticated','authenticated','material-upload-'||n||'@example.invalid',now(),
 '{"provider":"email"}'::jsonb,'{"name":"Fictional upload fixture","role":"admin"}'::jsonb,false,now(),now()
FROM generate_series(1,4) n;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after)
SELECT pg_temp.upload_id(n+100),pg_temp.upload_id(n),now(),now(),now()+interval '1 hour' FROM generate_series(1,4) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_claim(1);
SELECT public.register_device(repeat('a',64),'Upload admin fixture');
SELECT pg_temp.upload_claim(2);
SELECT public.register_device(repeat('b',64),'Upload student fixture');
SELECT pg_temp.upload_claim(3);
SELECT public.register_device(repeat('c',64),'Upload second admin fixture');
SELECT pg_temp.upload_claim(4);
SELECT public.register_device(repeat('d',64),'Upload cap admin fixture');
RESET ROLE;
UPDATE private.account_access SET role='admin' WHERE user_id IN(pg_temp.upload_id(1),pg_temp.upload_id(3),pg_temp.upload_id(4));
SELECT pg_temp.upload_claim(1);
INSERT INTO public.courses(id,title,instructor,category,level,status) VALUES
 (pg_temp.upload_id(201),'Upload live course','Fictional','Engineering','1','draft'),
 (pg_temp.upload_id(202),'Upload removed course','Fictional','Engineering','1','draft');
INSERT INTO public.course_sessions(id,course_id,session_number,title,status) VALUES
 (pg_temp.upload_id(301),pg_temp.upload_id(201),1,'Upload live session','draft'),
 (pg_temp.upload_id(302),pg_temp.upload_id(201),2,'Upload deleted session','draft'),
 (pg_temp.upload_id(303),pg_temp.upload_id(202),1,'Upload removed parent','draft');
UPDATE public.course_sessions SET deleted_at=now() WHERE id=pg_temp.upload_id(302);
UPDATE public.courses SET deleted_at=now() WHERE id=pg_temp.upload_id(202);
INSERT INTO public.session_materials(id,session_id,kind,title)
SELECT pg_temp.upload_id(n),CASE n WHEN 405 THEN pg_temp.upload_id(302) WHEN 406 THEN pg_temp.upload_id(303) ELSE pg_temp.upload_id(301) END,
 CASE WHEN n=403 THEN 'video' WHEN n IN(401,404,405,406) THEN 'pdf' ELSE 'file' END,'Upload material '||n
FROM generate_series(401,431) n;
UPDATE public.session_materials SET deleted_at=now(),status='archived',revision=revision+1 WHERE id=pg_temp.upload_id(404);
CREATE TEMP TABLE upload_material_snapshot AS SELECT id,revision,status FROM public.session_materials WHERE id::text LIKE 'f2c0e700-%';
GRANT SELECT ON pg_temp.upload_material_snapshot TO authenticated;

SELECT pg_temp.upload_check('new bucket private twenty MiB PDF TXT only existing bucket unchanged',$test$
 SELECT (SELECT NOT public AND file_size_limit=20971520 AND allowed_mime_types=ARRAY['application/pdf','text/plain'] FROM storage.buckets WHERE id='material-upload-quarantine')
 AND (SELECT NOT public AND file_size_limit=52428800 AND allowed_mime_types=ARRAY['application/pdf','image/jpeg','image/png'] FROM storage.buckets WHERE id='course-materials') $test$);
SELECT pg_temp.upload_check('ledger RLS and no direct client or service grants',$test$
 SELECT relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')
 FROM pg_class c WHERE oid='private.material_file_uploads'::regclass $test$);
SELECT pg_temp.upload_check('four invoker wrappers explicit empty path and authenticated execute only',$test$
 SELECT count(*)=4 AND bool_and(NOT prosecdef AND proconfig=ARRAY['search_path=""'] AND has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND proname IN('prepare_material_file_upload','get_material_file_upload','list_material_file_uploads','complete_material_file_upload') $test$);
SELECT pg_temp.upload_check('quarantine has INSERT policy only no read update delete',$test$
 SELECT count(*)=1 AND bool_and(cmd='INSERT' AND roles=ARRAY['authenticated']::name[] AND qual IS NULL
   AND with_check LIKE '%material-upload-quarantine%' AND with_check LIKE '%material_file_upload_insert_allowed%') FROM pg_policies
 WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'material_upload_quarantine%' $test$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_check('empty status list is JSON array',$test$ SELECT public.list_material_file_uploads(pg_temp.upload_id(401))='[]'::jsonb $test$);
INSERT INTO pg_temp.upload_replies VALUES
 ('pdf',public.prepare_material_file_upload(pg_temp.upload_id(401),1,'Private original.pdf','application/pdf',17,pg_temp.upload_id(501))),
 ('txt',public.prepare_material_file_upload(pg_temp.upload_id(402),1,'Private original.txt','text/plain',7,pg_temp.upload_id(502))),
 ('filepdf',public.prepare_material_file_upload(pg_temp.upload_id(402),1,'Other.pdf','application/pdf',19,pg_temp.upload_id(503)));
SELECT pg_temp.upload_check('prepare exact three fields opaque PDF path',$test$
 SELECT pg_temp.upload_keys(pg_temp.upload_reply('pdf'),ARRAY['asset_id','path','state'])
 AND pg_temp.upload_path('pdf')=pg_temp.upload_id(401)::text||'/'||pg_temp.upload_asset('pdf')::text||'.pdf'
 AND pg_temp.upload_reply('pdf')->>'state'='reserved' $test$);
SELECT pg_temp.upload_check('TXT reserve path uses material UUID asset UUID txt',$test$
 SELECT pg_temp.upload_path('txt')=pg_temp.upload_id(402)::text||'/'||pg_temp.upload_asset('txt')::text||'.txt' $test$);
SELECT pg_temp.upload_check('status exact six fields original private name declared properties',$test$
 SELECT public.get_material_file_upload(pg_temp.upload_asset('pdf'))=jsonb_build_object('asset_id',pg_temp.upload_asset('pdf'),
 'material_id',pg_temp.upload_id(401),'file_name','Private original.pdf','content_type','application/pdf','byte_length',17,'state','reserved') $test$);
INSERT INTO pg_temp.upload_replies VALUES('retry',public.prepare_material_file_upload(pg_temp.upload_id(401),1,'Private original.pdf','application/pdf',17,pg_temp.upload_id(501)));
SELECT pg_temp.upload_check('same operation exact request returns same reservation',$test$ SELECT pg_temp.upload_reply('pdf')=pg_temp.upload_reply('retry') $test$);
SELECT pg_temp.upload_error('changed operation input rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(401),1,'Changed.pdf','application/pdf',17,pg_temp.upload_id(501)) $test$,'42501','material_upload_operation_reused');
SELECT pg_temp.upload_error('reused operation invalid input cannot change request',$test$ SELECT public.prepare_material_file_upload(NULL,0,NULL,NULL,0,pg_temp.upload_id(501)) $test$,'42501','material_upload_operation_reused');
SELECT pg_temp.upload_error('PDF descriptor rejects TXT',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(401),1,'No.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('video descriptor rejects file upload',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(403),1,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('unsupported MIME rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.zip','application/zip',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('zero byte length rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.txt','text/plain',0,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('over twenty MiB rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.txt','text/plain',20971521,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('unsafe filename separator rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'../No.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('ASCII control filename rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No'||chr(10)||'.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('overlong original filename rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,repeat('n',157)||'.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('backslash traversal filename rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'..'||chr(92)||'No.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('C1 control filename rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No'||chr(159)||'.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('PDF MIME TXT extension mismatch rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.txt','application/pdf',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('TXT MIME executable extension rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.exe','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('blank filename stem rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'   .txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('Unicode blank filename stem rejected',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,chr(160)||chr(8192)||'.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('null operation invalid',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'No.txt','text/plain',1,NULL) $test$,'22023','invalid_material_upload_input');
SELECT pg_temp.upload_error('stale material revision conflicts',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),2,'No.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_conflict');
SELECT pg_temp.upload_error('missing material unavailable',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(999),1,'No.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('deleted material unavailable',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(404),2,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('deleted session unavailable',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(405),1,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('deleted course unavailable',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(406),1,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('unreserved Storage key denied',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_id(401)::text||'/'||pg_temp.upload_id(999)::text||'.pdf') $test$,'42501','new row violates row-level security policy for table "objects"');
SELECT pg_temp.upload_error('different material cannot reuse asset key',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_id(402)::text||'/'||pg_temp.upload_asset('pdf')::text||'.pdf') $test$,'42501','new row violates row-level security policy for table "objects"');
-- Metadata insertion exercises RLS only, NOT actual body/MIME/length enforcement.
INSERT INTO storage.objects(bucket_id,name,metadata) VALUES
 ('material-upload-quarantine',pg_temp.upload_path('pdf'),'{"mimetype":"application/pdf","size":17}'),
 ('material-upload-quarantine',pg_temp.upload_path('txt'),'{"mimetype":"text/plain","size":8}');
SELECT pg_temp.upload_error('duplicate key cannot overwrite existing upload',$test$ INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('material-upload-quarantine',pg_temp.upload_path('pdf'),'{"mimetype":"application/pdf","size":99}') $test$,'23505',NULL);
SELECT pg_temp.upload_check('quarantine objects invisible to client SELECT',$test$ SELECT count(*)=0 FROM storage.objects WHERE bucket_id='material-upload-quarantine' $test$);
SELECT pg_temp.upload_check('client object UPDATE cannot touch invisible quarantine',$test$ WITH changed AS(UPDATE storage.objects SET metadata='{}' WHERE bucket_id='material-upload-quarantine' RETURNING id) SELECT count(*)=0 FROM changed $test$);
SELECT pg_temp.upload_error('client object DELETE blocked by Storage protection',$test$ DELETE FROM storage.objects WHERE bucket_id='material-upload-quarantine' $test$,'42501','Direct deletion from storage tables is not allowed. Use the Storage API instead.');
INSERT INTO pg_temp.upload_replies VALUES('completed',public.complete_material_file_upload(pg_temp.upload_asset('pdf')));
SELECT pg_temp.upload_check('completion exact six fields uploaded only',$test$
 SELECT pg_temp.upload_keys(pg_temp.upload_reply('completed'),ARRAY['asset_id','material_id','file_name','content_type','byte_length','state'])
 AND pg_temp.upload_reply('completed')->>'state'='uploaded' AND pg_temp.upload_reply('completed')->>'material_id'=pg_temp.upload_id(401)::text $test$);
SELECT pg_temp.upload_check('repeat completion returns same status',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('pdf'))=pg_temp.upload_reply('completed') $test$);
INSERT INTO pg_temp.upload_replies VALUES('retry_uploaded',public.prepare_material_file_upload(pg_temp.upload_id(401),1,'Private original.pdf','application/pdf',17,pg_temp.upload_id(501)));
SELECT pg_temp.upload_check('prepare retry after completion returns same ID path current uploaded state',$test$
 SELECT pg_temp.upload_reply('retry_uploaded')->>'asset_id'=pg_temp.upload_reply('pdf')->>'asset_id'
 AND pg_temp.upload_reply('retry_uploaded')->>'path'=pg_temp.upload_path('pdf') AND pg_temp.upload_reply('retry_uploaded')->>'state'='uploaded' $test$);
SELECT pg_temp.upload_error('metadata size mismatch cannot complete',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('txt')) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('missing Storage object cannot complete',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('filepdf')) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('completed asset cannot accept new Storage INSERT',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_path('pdf')) $test$,'42501','new row violates row-level security policy for table "objects"');
RESET ROLE;
UPDATE storage.objects SET metadata='{"mimetype":"application/pdf","size":7}' WHERE bucket_id='material-upload-quarantine' AND name=pg_temp.upload_path('txt');
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('metadata type mismatch cannot complete',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('txt')) $test$,'42501','material_upload_unavailable');
RESET ROLE;
UPDATE storage.objects SET metadata='{"mimetype":"text/plain","size":"NaN"}' WHERE bucket_id='material-upload-quarantine' AND name=pg_temp.upload_path('txt');
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('malformed metadata size fails safely',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('txt')) $test$,'42501','material_upload_unavailable');
RESET ROLE;
UPDATE storage.objects SET metadata='{"mimetype":"text/plain","size":7}' WHERE bucket_id='material-upload-quarantine' AND name=pg_temp.upload_path('txt');
SET LOCAL ROLE authenticated;
SELECT public.complete_material_file_upload(pg_temp.upload_asset('txt'));
SELECT pg_temp.upload_claim(3);
SELECT pg_temp.upload_check('other admitted admin can inspect safe status without path',$test$
 SELECT public.get_material_file_upload(pg_temp.upload_asset('pdf'))=pg_temp.upload_reply('completed')
 AND jsonb_array_length(public.list_material_file_uploads(pg_temp.upload_id(401)))=1 $test$);
SELECT pg_temp.upload_error('other admin cannot complete uploader reservation',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('filepdf')) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('other admin cannot upload to reserved path',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_path('filepdf')) $test$,'42501','new row violates row-level security policy for table "objects"');
SELECT pg_temp.upload_error('private ledger has no direct admin grant',$test$ SELECT * FROM private.material_file_uploads $test$,'42501','permission denied for table material_file_uploads');
SELECT pg_temp.upload_claim(1);
SELECT pg_temp.upload_error('unknown asset uniformly unavailable',$test$ SELECT public.get_material_file_upload(pg_temp.upload_id(999)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('null asset invalid',$test$ SELECT public.get_material_file_upload(NULL) $test$,'22023','invalid_material_upload_input');
RESET ROLE;
SELECT pg_temp.upload_check('preparation and completion safe audit exactly once',$test$
 SELECT count(*)=5 AND bool_and(pg_temp.upload_keys(details,ARRAY['asset_id','material_id']))
 FROM private.security_events WHERE actor_id=pg_temp.upload_id(1) AND action IN('material_file_upload_prepared','material_file_upload_completed') $test$);
SELECT pg_temp.upload_check('ledger bound to actual actor material session course revision',$test$
 SELECT count(*)=3 AND bool_and(actor_id=pg_temp.upload_id(1) AND session_id=pg_temp.upload_id(301)
 AND course_id=pg_temp.upload_id(201) AND expected_revision=1 AND expires_at=created_at+interval '1 hour')
 FROM private.material_file_uploads WHERE actor_id=pg_temp.upload_id(1) $test$);
SELECT pg_temp.upload_check('upload never changed any descriptor revision or publication',$test$
 SELECT count(*)=31 AND bool_and(m.revision=s.revision AND m.status=s.status) FROM public.session_materials m JOIN pg_temp.upload_material_snapshot s USING(id) $test$);
-- Current metadata edits invalidate upload authorization and completion, not history reads.
UPDATE public.session_materials SET title='Edited metadata',revision=revision+1 WHERE id=pg_temp.upload_id(402);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('revision drift blocks old reserve replay',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(402),1,'Other.pdf','application/pdf',19,pg_temp.upload_id(503)) $test$,'42501','material_upload_conflict');
SELECT pg_temp.upload_error('revision drift blocks completion',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('filepdf')) $test$,'42501','material_upload_conflict');
SELECT pg_temp.upload_error('revision drift blocks Storage INSERT',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_path('filepdf')) $test$,'42501','new row violates row-level security policy for table "objects"');
SELECT pg_temp.upload_check('status reads preserve declared snapshot after metadata edit',$test$
 SELECT public.get_material_file_upload(pg_temp.upload_asset('filepdf'))->>'state'='reserved' $test$);
RESET ROLE;
-- Privileged boundary fixtures: expired reservation, actor cap, material cap and
-- >20 statuses. No real bytes and no direct changes to existing ledger identities.
INSERT INTO private.material_file_uploads(asset_id,actor_id,material_id,session_id,course_id,expected_revision,
 operation_id,request_hash,path,file_name,content_type,byte_length,expires_at)
VALUES(pg_temp.upload_id(600),pg_temp.upload_id(1),pg_temp.upload_id(407),pg_temp.upload_id(301),pg_temp.upload_id(201),1,
 pg_temp.upload_id(1600),sha256('expired'::bytea),pg_temp.upload_id(407)::text||'/'||pg_temp.upload_id(600)::text||'.txt',
 'Expired.txt','text/plain',1,now()-interval '1 second');
INSERT INTO private.material_file_uploads(asset_id,actor_id,material_id,session_id,course_id,expected_revision,
 operation_id,request_hash,path,file_name,content_type,byte_length)
SELECT pg_temp.upload_id(700+n),pg_temp.upload_id(4),pg_temp.upload_id(410+n),pg_temp.upload_id(301),pg_temp.upload_id(201),1,
 pg_temp.upload_id(1700+n),sha256(convert_to(n::text,'UTF8')),pg_temp.upload_id(410+n)::text||'/'||pg_temp.upload_id(700+n)::text||'.txt',
 'Cap.txt','text/plain',1 FROM generate_series(0,19) n;
INSERT INTO private.material_file_uploads(asset_id,actor_id,material_id,session_id,course_id,expected_revision,
 operation_id,request_hash,path,file_name,content_type,byte_length)
SELECT pg_temp.upload_id(800+n),pg_temp.upload_id(3),pg_temp.upload_id(431),pg_temp.upload_id(301),pg_temp.upload_id(201),1,
 pg_temp.upload_id(1800+n),sha256(convert_to(n::text,'UTF8')),pg_temp.upload_id(431)::text||'/'||pg_temp.upload_id(800+n)::text||'.txt',
 'Material cap.txt','text/plain',1 FROM generate_series(0,4) n;
INSERT INTO private.material_file_uploads(asset_id,actor_id,material_id,session_id,course_id,expected_revision,
 operation_id,request_hash,path,file_name,content_type,byte_length,state,uploaded_at)
SELECT pg_temp.upload_id(900+n),pg_temp.upload_id(3),pg_temp.upload_id(430),pg_temp.upload_id(301),pg_temp.upload_id(201),1,
 pg_temp.upload_id(1900+n),sha256(convert_to(n::text,'UTF8')),pg_temp.upload_id(430)::text||'/'||pg_temp.upload_id(900+n)::text||'.txt',
 'Status '||n||'.txt','text/plain',1,'uploaded',now() FROM generate_series(0,24) n;
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('expired reservation cannot finalize',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_id(600)) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('expired reservation cannot upload',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_id(407)::text||'/'||pg_temp.upload_id(600)::text||'.txt') $test$,'42501','new row violates row-level security policy for table "objects"');
SELECT pg_temp.upload_check('expired reservation status remains readable for reconciliation',$test$ SELECT public.get_material_file_upload(pg_temp.upload_id(600))->>'state'='reserved' $test$);
SELECT pg_temp.upload_error('material outstanding cap spans different upload actors',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(431),1,'Cap.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_limit');
SELECT pg_temp.upload_claim(4);
SELECT pg_temp.upload_error('actor outstanding cap spans distinct materials',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(430),1,'Cap.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_limit');
SELECT pg_temp.upload_claim(1);
SELECT pg_temp.upload_check('list bounded twenty newest deterministic UUID ties',$test$
 SELECT jsonb_array_length(public.list_material_file_uploads(pg_temp.upload_id(430)))=20
 AND public.list_material_file_uploads(pg_temp.upload_id(430))->0->>'asset_id'=pg_temp.upload_id(924)::text
 AND public.list_material_file_uploads(pg_temp.upload_id(430))->19->>'asset_id'=pg_temp.upload_id(905)::text $test$);
RESET ROLE;
CREATE TEMP TABLE upload_audit_counts AS SELECT
 (SELECT count(*) FROM private.material_file_uploads WHERE actor_id=pg_temp.upload_id(1)) AS assets,
 (SELECT count(*) FROM private.security_events WHERE actor_id=pg_temp.upload_id(1) AND action IN('material_file_upload_prepared','material_file_upload_completed')) AS events;
CREATE FUNCTION pg_temp.fail_upload_audit() RETURNS trigger LANGUAGE plpgsql AS $helper$
BEGIN
 IF NEW.actor_id=pg_temp.upload_id(1) AND NEW.action IN('material_file_upload_prepared','material_file_upload_completed') THEN
  RAISE EXCEPTION 'fixture_upload_audit_failure' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$helper$;
CREATE TRIGGER fixture_upload_audit_failure BEFORE INSERT ON private.security_events FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_upload_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('prepare audit failure rolls back reservation',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(408),1,'Rollback.txt','text/plain',1,pg_temp.upload_id(599)) $test$,'23514','fixture_upload_audit_failure');
RESET ROLE;
DROP TRIGGER fixture_upload_audit_failure ON private.security_events;
SELECT pg_temp.upload_check('failed preparation leaves no operation asset or audit',$test$
 SELECT (SELECT count(*) FROM private.material_file_uploads WHERE actor_id=pg_temp.upload_id(1))=assets
 AND (SELECT count(*) FROM private.security_events WHERE actor_id=pg_temp.upload_id(1) AND action IN('material_file_upload_prepared','material_file_upload_completed'))=events
 AND NOT EXISTS(SELECT 1 FROM private.material_file_uploads WHERE actor_id=pg_temp.upload_id(1) AND operation_id=pg_temp.upload_id(599)) FROM pg_temp.upload_audit_counts $test$);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.upload_replies VALUES('audit_complete',public.prepare_material_file_upload(pg_temp.upload_id(409),1,'Audit.txt','text/plain',3,pg_temp.upload_id(599)));
INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('material-upload-quarantine',pg_temp.upload_path('audit_complete'),'{"mimetype":"text/plain","size":3}');
RESET ROLE;
CREATE TRIGGER fixture_upload_audit_failure BEFORE INSERT ON private.security_events FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_upload_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('completion audit failure rolls back uploaded state',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('audit_complete')) $test$,'23514','fixture_upload_audit_failure');
RESET ROLE;
DROP TRIGGER fixture_upload_audit_failure ON private.security_events;
SELECT pg_temp.upload_check('failed completion preserves reservation and zero completion audit',$test$
 SELECT state='reserved' AND uploaded_at IS NULL AND NOT EXISTS(SELECT 1 FROM private.security_events e
 WHERE e.action='material_file_upload_completed' AND e.details->>'asset_id'=a.asset_id::text)
 FROM private.material_file_uploads a WHERE asset_id=pg_temp.upload_asset('audit_complete') $test$);
SELECT pg_temp.upload_error('ledger identity and original filename immutable',$test$ UPDATE private.material_file_uploads SET file_name='Changed.pdf' WHERE asset_id=pg_temp.upload_asset('pdf') $test$,'42501','material_upload_unavailable');
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.upload_replies VALUES('max',public.prepare_material_file_upload(pg_temp.upload_id(407),1,'Max.txt','text/plain',20971520,pg_temp.upload_id(560)));
SELECT pg_temp.upload_check('twenty MiB exact boundary accepted as reservation only',$test$
 SELECT public.get_material_file_upload(pg_temp.upload_asset('max'))->>'byte_length'='20971520'
 AND public.get_material_file_upload(pg_temp.upload_asset('max'))->>'state'='reserved' $test$);
SELECT pg_temp.upload_claim(3);
INSERT INTO pg_temp.upload_replies VALUES('actor3_sameop',public.prepare_material_file_upload(pg_temp.upload_id(408),1,'Own.txt','text/plain',1,pg_temp.upload_id(501)));
SELECT pg_temp.upload_check('same operation UUID across actors is independent',$test$
 SELECT pg_temp.upload_asset('actor3_sameop')<>pg_temp.upload_asset('pdf') AND pg_temp.upload_reply('actor3_sameop')->>'state'='reserved' $test$);
SELECT pg_temp.upload_claim(1);
RESET ROLE;
UPDATE public.course_sessions SET deleted_at=now() WHERE id=pg_temp.upload_id(301);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_error('live-parent recheck denies completion after session removal',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('audit_complete')) $test$,'42501','material_upload_unavailable');
SELECT pg_temp.upload_error('live-parent recheck denies asset status after session removal',$test$ SELECT public.get_material_file_upload(pg_temp.upload_asset('pdf')) $test$,'42501','material_upload_unavailable');
RESET ROLE;
UPDATE public.course_sessions SET deleted_at=NULL WHERE id=pg_temp.upload_id(301);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.upload_replies VALUES('uppercase',public.prepare_material_file_upload(pg_temp.upload_id(410),1,repeat('N',156)||'.PDF','application/pdf',1,pg_temp.upload_id(561)));
SELECT pg_temp.upload_check('160 codepoint filename uppercase extension accepted preserved',$test$
 SELECT public.get_material_file_upload(pg_temp.upload_asset('uppercase'))->>'file_name'=repeat('N',156)||'.PDF'
 AND pg_temp.upload_path('uppercase')=pg_temp.upload_id(410)::text||'/'||pg_temp.upload_asset('uppercase')::text||'.pdf' $test$);
RESET ROLE;
-- Four exact denial assertions per identity/admission context. JWT metadata never
-- grants authoring authority; only fictional rows are changed between statements.
CREATE FUNCTION pg_temp.upload_denied(p_label text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $helper$
BEGIN
 PERFORM pg_temp.upload_error(p_label||' prepare denied',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(401),1,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'42501','material_upload_access_required');
 PERFORM pg_temp.upload_error(p_label||' get denied',$test$ SELECT public.get_material_file_upload(pg_temp.upload_asset('pdf')) $test$,'42501','material_upload_access_required');
 PERFORM pg_temp.upload_error(p_label||' list denied',$test$ SELECT public.list_material_file_uploads(pg_temp.upload_id(401)) $test$,'42501','material_upload_access_required');
 PERFORM pg_temp.upload_error(p_label||' complete denied',$test$ SELECT public.complete_material_file_upload(pg_temp.upload_asset('audit_complete')) $test$,'42501','material_upload_access_required');
END;
$helper$;
GRANT EXECUTE ON FUNCTION pg_temp.upload_denied(text) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_claim(2);
SELECT pg_temp.upload_denied('student forged admin metadata');
SELECT pg_temp.upload_error('student Storage INSERT denied',$test$ INSERT INTO storage.objects(bucket_id,name) VALUES('material-upload-quarantine',pg_temp.upload_path('max')) $test$,'42501','new row violates row-level security policy for table "objects"');
RESET ROLE;
UPDATE private.account_access SET disabled=true WHERE user_id=pg_temp.upload_id(1);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_claim(1);
SELECT pg_temp.upload_denied('disabled admin');
RESET ROLE;
UPDATE private.account_access SET disabled=false WHERE user_id=pg_temp.upload_id(1);
UPDATE private.devices SET revoked_at=now() WHERE user_id=pg_temp.upload_id(1);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_denied('revoked admin device');
RESET ROLE;
UPDATE private.devices SET revoked_at=NULL WHERE user_id=pg_temp.upload_id(1);
UPDATE auth.sessions SET not_after=now()-interval '1 second' WHERE id=pg_temp.upload_id(101);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_denied('expired Auth session');
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id=pg_temp.upload_id(101);
UPDATE private.session_access SET ended_at=now() WHERE session_id=pg_temp.upload_id(101);
SET LOCAL ROLE authenticated;
SELECT pg_temp.upload_denied('ended admin admission');
RESET ROLE;
UPDATE private.session_access SET ended_at=NULL WHERE session_id=pg_temp.upload_id(101);
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims='{}';
SELECT pg_temp.upload_error('anonymous prepare EXECUTE denied',$test$ SELECT public.prepare_material_file_upload(pg_temp.upload_id(401),1,'No.pdf','application/pdf',1,pg_temp.upload_id(599)) $test$,'42501','permission denied for function prepare_material_file_upload');
SELECT pg_temp.upload_error('anonymous get EXECUTE denied',$test$ SELECT public.get_material_file_upload(pg_temp.upload_asset('pdf')) $test$,'42501','permission denied for function get_material_file_upload');
RESET ROLE;
SELECT pg_temp.upload_check('all upload helpers empty paths and no PUBLIC anon service execution',$test$
 SELECT count(*)=7 AND bool_and(proconfig=ARRAY['search_path=""'] AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE grantee=0 AND privilege_type='EXECUTE'))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private'
 AND proname IN('material_upload_file_name_valid','guard_material_file_upload','material_file_upload_status','material_file_upload_insert_allowed','prepare_material_file_upload','read_material_file_upload','complete_material_file_upload') $test$);
SELECT pg_temp.upload_check('publication and paid delivery still closed',$test$
 SELECT NOT EXISTS(SELECT 1 FROM public.session_materials WHERE id::text LIKE 'f2c0e700-%' AND kind IN('pdf','file') AND status='published')
 AND NOT has_function_privilege('authenticated','public.create_pending_order(text,uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege('service_role','private.create_pending_order(text,uuid,uuid)','EXECUTE') $test$);
DO $count$ BEGIN
 IF (SELECT count(*) FROM pg_temp.upload_results)<>99 THEN RAISE EXCEPTION 'FAIL: expected exactly 99 material file upload assertions'; END IF;
END; $count$;
SELECT jsonb_build_object('status','PASS','passed',count(*),'expected',99,
 'tests',jsonb_agg(jsonb_build_object('name',name,'outcome',outcome) ORDER BY name)) AS phase2_material_file_uploads_report
FROM pg_temp.upload_results;
ROLLBACK;
-- Existing tables only: valid after either deployed rollback or schema preflight.
-- Restrictive actor/material FKs also prevent orphan ledger fixtures surviving.
SELECT
 (SELECT count(*) FROM auth.users WHERE id::text LIKE 'f2c0e700-%') AS reserved_users_remaining,
 (SELECT count(*) FROM auth.sessions WHERE id::text LIKE 'f2c0e700-%' OR user_id::text LIKE 'f2c0e700-%') AS reserved_sessions_remaining,
 (SELECT count(*) FROM private.account_access WHERE user_id::text LIKE 'f2c0e700-%') AS reserved_accounts_remaining,
 (SELECT count(*) FROM private.devices WHERE user_id::text LIKE 'f2c0e700-%') AS reserved_devices_remaining,
 (SELECT count(*) FROM private.session_access WHERE user_id::text LIKE 'f2c0e700-%') AS reserved_admissions_remaining,
 (SELECT count(*) FROM public.profiles WHERE id::text LIKE 'f2c0e700-%') AS reserved_profiles_remaining,
 (SELECT count(*) FROM private.security_events WHERE actor_id::text LIKE 'f2c0e700-%' OR subject_id::text LIKE 'f2c0e700-%') AS reserved_events_remaining,
 (SELECT count(*) FROM public.courses WHERE id::text LIKE 'f2c0e700-%') AS reserved_courses_remaining,
 (SELECT count(*) FROM public.course_sessions WHERE id::text LIKE 'f2c0e700-%') AS reserved_content_sessions_remaining,
 (SELECT count(*) FROM public.session_materials WHERE id::text LIKE 'f2c0e700-%') AS reserved_materials_remaining,
 (SELECT count(*) FROM storage.objects WHERE bucket_id='material-upload-quarantine' AND split_part(name,'/',1) LIKE 'f2c0e700-%') AS reserved_object_metadata_remaining;
