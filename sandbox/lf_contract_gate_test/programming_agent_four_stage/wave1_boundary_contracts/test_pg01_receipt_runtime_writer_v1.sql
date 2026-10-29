\set ON_ERROR_STOP on
-- Disposable PostgreSQL 17. Run from repository root. Never run on live DB.
-- H-A2: judges get a sandbox provenance chain (pg_temp.govern). The terminal
-- authority gate is removed IN THIS TEST ONLY (lift=on) so downstream behaviour stays covered;
-- test_pg01_ha2_provenance_v1.sql proves the gate on the production source.
BEGIN;
CREATE SCHEMA private; CREATE SCHEMA extensions; CREATE SCHEMA lf_ops;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF; END $$;
GRANT USAGE ON SCHEMA private TO service_role;
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY,decision_ref text UNIQUE,consumer_code text,subject_ref text,subject_version text,decided_at timestamptz,effective_at timestamptz,context_payload jsonb NOT NULL,context_sha256 text NOT NULL,created_by_execution_id text NOT NULL,created_at timestamptz);
CREATE FUNCTION private.test_asof_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'BLOCK_DECISION_CONTEXT_ASOF_APPEND_ONLY'; END $$;
CREATE TRIGGER test_asof_immutable BEFORE UPDATE OR DELETE ON private.lf_decision_context_asof_v1 FOR EACH ROW EXECUTE FUNCTION private.test_asof_immutable();
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,status text,manifest jsonb,started_at timestamptz,completed_at timestamptz);
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_id text,status text,evidence_payload jsonb);
CREATE TABLE lf_ops.app_shells(app_shell_id bigint PRIMARY KEY,app_shell_code text);
CREATE TABLE lf_ops.modulos(module_id bigint PRIMARY KEY,module_code text,app_shell_id bigint);
CREATE TABLE lf_ops.pantallas(id bigint PRIMARY KEY,codigo text,estado text,activa boolean,module_id bigint);
\i sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/pg01_ha2_provenance_fixture.sql
CREATE FUNCTION lf_ops.fn_screen_contract_v1(p_app_shell_code text,p_module_code text,p_screen_code text)
RETURNS TABLE(app_shell_id bigint,module_id bigint,pantalla_id integer,app_shell_code text,module_code text,screen_code text,screen_name text,screen_status text,contract_version text,contract jsonb)
LANGUAGE sql STABLE AS $q$ SELECT 1::bigint,1::bigint,1::integer,p_app_shell_code,p_module_code,p_screen_code,'test',
 (SELECT p.estado FROM lf_ops.pantallas p WHERE p.codigo=p_screen_code LIMIT 1),'v1',jsonb_build_object('metadata',jsonb_build_object('generated_at','synthetic'),'fields','[]'::jsonb) $q$;
-- D7 must be the REAL migration, not a hand-written stub.
\i supabase/migrations/20261026173901_lf_programming_context_handoff_receipt_ledger_v1.sql
-- Load the actual #3181 migration, previously applied in the intended stack.
-- Its BEGIN/COMMIT are removed only for the disposable test transaction.
CREATE TEMP TABLE src_lines(n bigint GENERATED ALWAYS AS IDENTITY,line text);
\copy src_lines(line) FROM 'supabase/migrations/20261027091000_lf_programming_admission_envelope_v2_resolver_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src_lines
\gexec
TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261027120000_lf_programming_receipt_runtime_writer_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
-- H-A2: the production writer has exactly one terminal authority gate.
SELECT CASE WHEN (SELECT count(*) FROM src_lines WHERE line=' RAISE EXCEPTION ''PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED'';')=1 THEN 'gate_present' ELSE 'TEST_FAIL:00_authority_gate_count' END AS gate \gset
\set lift on
SELECT replace(replace(CASE WHEN :'lift'='on' THEN replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'\n RAISE EXCEPTION ''PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED'';','') ELSE string_agg(coalesce(line,''),E'\n' ORDER BY n) END,E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src_lines
\gexec
SELECT set_config('ha2.gate',:'gate',false), set_config('ha2.lift',:'lift',false);
DO $g$ BEGIN IF current_setting('ha2.gate')<>'gate_present' THEN RAISE EXCEPTION '%',current_setting('ha2.gate'); END IF; END $g$;
CREATE TEMP TABLE passed(id int PRIMARY KEY);
-- Permission checks MUST precede owner calls to the new functions.
DO $$ DECLARE denied boolean:=false; BEGIN
 PERFORM set_config('role','service_role',true);
 BEGIN PERFORM private.fn_lf_programming_context_handoff_receive_v1('aaaaaaaa-0000-4000-8000-000000000001',repeat('a',64)); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM set_config('role','none',true);
 IF denied IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:01_receiver_acl'; END IF;
 INSERT INTO passed VALUES(1);
END $$;
DO $$ DECLARE denied boolean:=false; BEGIN
 PERFORM set_config('role','service_role',true);
 BEGIN PERFORM private.fn_lf_programming_context_handoff_receipt_record_core_v1('{}','{}','{}','x'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM set_config('role','none',true);
 IF denied IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:02_core_acl'; END IF;
 INSERT INTO passed VALUES(2);
END $$;
DO $$ BEGIN
 IF NOT has_function_privilege('service_role','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('anon','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('authenticated','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE') THEN
  RAISE EXCEPTION 'TEST_FAIL:03_runtime_acl'; END IF; INSERT INTO passed VALUES(3); END $$;
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES('TRAIN','ACTUALIZACION_DB_LF','MIGRATION','test','IN_PROGRESS','{"producer":"lf-migration-merge-train"}',now(),NULL);
INSERT INTO lf_ops.app_shells VALUES(1,'B2B_APP_SHELL');
INSERT INTO lf_ops.modulos VALUES(1,'B2B_AUTENTICACION',1);
INSERT INTO lf_ops.pantallas VALUES(1,'B2B-AUTH-001','VIGENTE',true,1);
CREATE FUNCTION pg_temp.fields() RETURNS text[] LANGUAGE sql AS $q$
 SELECT ARRAY['objective','target_granularity','target','authority_state','implementation_state','requirements','authority_bindings','implementability_schema','applicable_rules','applicable_invariants','preserve','material_front_coverage','decision_context','analysis_stop_rule','scope_readiness','scope_front_matrix','package_readiness','unresolved_material_items','source_refs','currentness_refs','snapshot_schema_digest_sha256','authority_fingerprint_sha256','source_snapshot_sha256'] $q$;
CREATE FUNCTION pg_temp.payload(p_missing text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $q$
DECLARE k text; s jsonb:='{}'::jsonb; BEGIN
 FOREACH k IN ARRAY pg_temp.fields() LOOP s:=s||jsonb_build_object(k,CASE
 WHEN k='snapshot_schema_digest_sha256' THEN to_jsonb('d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'::text)
 WHEN k='scope_readiness' THEN '[{"scope_id":"S1","scope_kind":"COMPONENT","status":"READY","depends_on_scope_ids":[]}]'::jsonb
 WHEN k='package_readiness' THEN '"READY"'::jsonb ELSE '[]'::jsonb END); END LOOP;
 IF p_missing IS NOT NULL THEN s:=s-p_missing; END IF;
 RETURN jsonb_build_object('extensions',jsonb_build_object('programming_context_snapshot',s||'{"schema_version":"PROGRAMMING_CONTEXT_SNAPSHOT_V1"}'::jsonb)); END $q$;
CREATE FUNCTION pg_temp.putcontext(p_id uuid,p_actor text,p_missing text DEFAULT NULL,p_bad boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $q$
DECLARE payload jsonb:=pg_temp.payload(p_missing); BEGIN
 INSERT INTO private.lf_decision_context_asof_v1(context_id,context_payload,context_sha256,created_by_execution_id)
 VALUES(p_id,payload,CASE WHEN p_bad THEN repeat('f',64) ELSE encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') END,p_actor); END $q$;
CREATE FUNCTION pg_temp.binding() RETURNS jsonb LANGUAGE sql AS $q$
 SELECT jsonb_build_object('channel','PROGRAMACION','binding_sha256','sha256:synthetic') $q$;
CREATE FUNCTION pg_temp.handoff(p_id uuid) RETURNS jsonb LANGUAGE sql AS $q$
 SELECT jsonb_build_object('context_id',p_id::text,'context_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id=p_id),
 'target_ref','lf-screen-contract://B2B_APP_SHELL/B2B_AUTENTICACION/B2B-AUTH-001',
 'requested_scope_ids',jsonb_build_array('S1'),'producer_execution_ref','PROFILE',
 'entry_contract_digest_sha256','d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8') $q$;
-- Selector binding as written by #3183: receipt = sha256((result - receipt)::text).
CREATE FUNCTION pg_temp.selection(p_code text) RETURNS jsonb LANGUAGE sql AS $q$
 SELECT jsonb_build_object('screen_selection_schema_version','LF_PROFILE_SCREEN_SELECTOR_BINDING_V1',
  'screen_selection_result',r||jsonb_build_object('semantic_receipt_sha256',encode(extensions.digest(convert_to(r::text,'UTF8'),'sha256'),'hex')),
  'screen_selection_validation',jsonb_build_object('status','VALID','decision','SELECTED','selected_screen_code',p_code))
 FROM (SELECT jsonb_build_object('schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_RESULT_V1','decision','SELECTED',
  'selected_screen_code',p_code,'ambiguous_screen_codes','[]'::jsonb) r) x $q$;
CREATE FUNCTION pg_temp.setup_profile(p_id text DEFAULT 'PROFILE') RETURNS void LANGUAGE sql AS $q$
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES(p_id,'EJECUCION_PERFIL_LF','PERFIL','A9','COMPLETED',jsonb_build_object(
 'router_profile_handoff',jsonb_build_object('channel','PROGRAMACION','semantic_request',jsonb_build_object('router_action_binding',pg_temp.binding())))
 ||pg_temp.selection('B2B-AUTH-001'),now(),now()) $q$;
SELECT pg_temp.setup_profile();
SELECT pg_temp.putcontext('aaaaaaaa-0000-4000-8000-000000000001','PROFILE');
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES('JUDGE','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','ANALYSIS','A9','COMPLETED',
 jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 LIMIT 1),
 'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/aaaaaaaa-0000-4000-8000-000000000001'),now(),now());
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload) VALUES('JUDGE','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}'),('JUDGE','judge_record','STEP_PASS_WITH_EVIDENCE','{}');
SELECT pg_temp.govern('JUDGE'); -- H-A2 adaptation: sandbox provenance
DO $$ DECLARE r jsonb; BEGIN
 r:=private.fn_lf_programming_context_handoff_receive_v1('aaaaaaaa-0000-4000-8000-000000000001',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 LIMIT 1));
 IF r#>>'{receipt,verdict}' IS DISTINCT FROM 'ACCEPT' OR jsonb_array_length(r#>'{receipt,validated_material_paths}') IS DISTINCT FROM 23 THEN
  RAISE EXCEPTION 'TEST_FAIL:04_receiver %',r; END IF; INSERT INTO passed VALUES(4); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 IF r->>'status' IS DISTINCT FROM 'RECORDED' OR r->>'verdict' IS DISTINCT FROM 'ACCEPT' THEN RAISE EXCEPTION 'TEST_FAIL:05_recorded %',r; END IF;
 INSERT INTO passed VALUES(5); END $$;
DO $$ DECLARE a jsonb; b jsonb; BEGIN
 a:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 b:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 IF a->>'status' IS DISTINCT FROM 'IDEMPOTENT_REPLAY' OR a->>'receipt_record_id' IS DISTINCT FROM b->>'receipt_record_id' THEN
 RAISE EXCEPTION 'TEST_FAIL:06_replay % %',a,b; END IF; INSERT INTO passed VALUES(6); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_receipt_record_runtime_v1('PROFILE','{}',pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RUNTIME_SOURCE_EXECUTION_INVALID%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:07_binding'; END IF; INSERT INTO passed VALUES(7); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001')||'{"extra":1}','JUDGE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RUNTIME_HANDOFF_INVALID%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:08_handoff'; END IF; INSERT INTO passed VALUES(8); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),jsonb_set(pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'{target_ref}','"OTHER"'),'JUDGE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RUNTIME_TARGET_SCREEN_MISMATCH%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:09_target'; END IF; INSERT INTO passed VALUES(9); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'OTHER-JUDGE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RUNTIME_JUDGE_INVALID%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:10_judge'; END IF; INSERT INTO passed VALUES(10); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),jsonb_set(pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'{requested_scope_ids}','["OTHER"]'),'JUDGE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RUNTIME_SCOPE_NOT_READY%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:11_scope'; END IF; INSERT INTO passed VALUES(11); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'));
 IF (r->>'found')::boolean IS DISTINCT FROM true OR (r->>'admissible')::boolean IS DISTINCT FROM true
    OR r->>'reason' IS DISTINCT FROM 'PG01_V2_ADMITTED' THEN RAISE EXCEPTION 'TEST_FAIL:12_resolver_admits %',r; END IF;
 INSERT INTO passed VALUES(12); END $$;
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1('{}','{}','{}','PROFILE');
 EXCEPTION WHEN OTHERS THEN blocked:=SQLERRM LIKE 'PG01_RECEIPT_WRITER_EXECUTION_NOT_AUTHORIZED%'; END;
 IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:13_train_wrapper'; END IF; INSERT INTO passed VALUES(13); END $$;
-- Claude review additions (27-oct): cases 14-20 of the requested matrix.
CREATE FUNCTION pg_temp.ctx(p_id uuid,p_actor text,p_missing text DEFAULT NULL,p_scope_status text DEFAULT 'READY') RETURNS void LANGUAGE plpgsql AS $q$
DECLARE payload jsonb:=pg_temp.payload(p_missing); BEGIN
 payload:=jsonb_set(payload,'{extensions,programming_context_snapshot,scope_readiness}',
   jsonb_build_array(jsonb_build_object('scope_id','S1','scope_kind','COMPONENT','status',p_scope_status,'depends_on_scope_ids','[]'::jsonb)));
 INSERT INTO private.lf_decision_context_asof_v1(context_id,context_payload,context_sha256,created_by_execution_id)
 VALUES(p_id,payload,encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),p_actor); END $q$;
CREATE FUNCTION pg_temp.ho(p_id uuid,p_producer text) RETURNS jsonb LANGUAGE sql AS $q$
 SELECT jsonb_set(pg_temp.handoff(p_id),'{producer_execution_ref}',to_jsonb(p_producer)) $q$;
CREATE FUNCTION pg_temp.judge(p_judge text,p_id uuid) RETURNS void LANGUAGE sql AS $q$
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES(p_judge,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','ANALYSIS','A9','COMPLETED',
  jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id=p_id),
  'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/'||p_id::text),now(),now());
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload) VALUES(p_judge,'semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}'),(p_judge,'judge_record','STEP_PASS_WITH_EVIDENCE','{}');
 SELECT pg_temp.govern(p_judge) $q$; -- H-A2 adaptation
CREATE FUNCTION pg_temp.expect(p_call text,p_code text) RETURNS boolean LANGUAGE plpgsql AS $q$
BEGIN EXECUTE p_call; RETURN false; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM LIKE p_code||'%'; END $q$;
-- 14 BLOCK verdict is recorded for audit and resolve_v2 refuses it.
SELECT pg_temp.setup_profile('PROFILE2');
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000002','PROFILE2','preserve');
SELECT pg_temp.judge('JUDGE2','aaaaaaaa-0000-4000-8000-000000000002');
DO $$ DECLARE r jsonb; v jsonb; BEGIN
 r:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE2',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000002','PROFILE2'),'JUDGE2');
 v:=private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000002','PROFILE2'));
 IF r->>'status' IS DISTINCT FROM 'RECORDED' OR r->>'verdict' IS DISTINCT FROM 'BLOCK'
    OR NOT (r->'block_reasons' @> '["MATERIAL_FIELD_MISSING:preserve"]') OR v->>'reason' IS DISTINCT FROM 'PG01_V2_RECEIPT_NOT_ACCEPT' THEN
  RAISE EXCEPTION 'TEST_FAIL:14_block % %',r,v; END IF; INSERT INTO passed VALUES(14); END $$;
-- 15 Snapshot written by another execution.
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000003','SOMEONE-ELSE');
DO $$ BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000003','PROFILE'),'JUDGE')$c$,'PG01_RUNTIME_SNAPSHOT_NOT_FROM_SOURCE')
 THEN RAISE EXCEPTION 'TEST_FAIL:15_snapshot_source'; END IF; INSERT INTO passed VALUES(15); END $$;
-- 16 Screen selection receipt missing (selected code present, sha absent).
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES('PROFILE3','EJECUCION_PERFIL_LF','PERFIL','A9','COMPLETED',jsonb_build_object(
 'router_profile_handoff',jsonb_build_object('channel','PROGRAMACION','semantic_request',jsonb_build_object('router_action_binding',pg_temp.binding())),
 'screen_selection_result',jsonb_build_object('selected_screen_code','B2B-AUTH-001')),now(),now());
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000004','PROFILE3');
DO $$ BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE3',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000004','PROFILE3'),'JUDGE')$c$,'PG01_RUNTIME_SCREEN_SELECTION_MISSING')
 THEN RAISE EXCEPTION 'TEST_FAIL:16_screen_selection'; END IF; INSERT INTO passed VALUES(16); END $$;
-- 17 ACCEPT package without any READY scope.
SELECT pg_temp.setup_profile('PROFILE5');
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000005','PROFILE5',NULL,'BLOCKED');
SELECT pg_temp.judge('JUDGE5','aaaaaaaa-0000-4000-8000-000000000005');
DO $$ BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE5',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000005','PROFILE5'),'JUDGE5')$c$,'PG01_RUNTIME_NO_READY_SCOPE')
 THEN RAISE EXCEPTION 'TEST_FAIL:17_no_ready_scope'; END IF; INSERT INTO passed VALUES(17); END $$;
-- 18 Stored context_sha256 that does not match its payload.
SELECT pg_temp.putcontext('aaaaaaaa-0000-4000-8000-000000000006','PROFILE',NULL,true);
DO $$ BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_context_handoff_receive_v1('aaaaaaaa-0000-4000-8000-000000000006',repeat('f',64))$c$,'PG01_RECEIVER_CONTEXT_DIGEST_MISMATCH')
 THEN RAISE EXCEPTION 'TEST_FAIL:18_digest'; END IF; INSERT INTO passed VALUES(18); END $$;
-- 19 D7 Train wrapper still records through the core.
DO $$ DECLARE rc jsonb; r jsonb; BEGIN
 rc:=private.fn_lf_programming_context_handoff_receive_v1('aaaaaaaa-0000-4000-8000-000000000001',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001'));
 r:=private.fn_lf_programming_context_handoff_receipt_record_v1(rc->'receipt','{"schema_version":"TEST"}',
   jsonb_set(pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'{target_ref}','"TRAIN-TARGET"'),'TRAIN');
 IF r->>'status' IS DISTINCT FROM 'RECORDED' OR r->>'created_by_execution_id' IS DISTINCT FROM 'TRAIN' THEN
  RAISE EXCEPTION 'TEST_FAIL:19_train_positive %',r; END IF; INSERT INTO passed VALUES(19); END $$;
-- 20 (H-A3) Screen no longer VIGENTE: the writer now rejects BEFORE reading or replaying the ledger.
-- Previous expectation (87e0f87): IDEMPOTENT_REPLAY with warning DEFINITION_NOT_CURRENT_AT_ISSUE.
-- The existing receipt stays byte-identical and resolve_v2 still refuses it on currentness.
UPDATE lf_ops.pantallas SET estado='CANDIDATO' WHERE codigo='B2B-AUTH-001';
DO $$ DECLARE v jsonb; n0 bigint; n1 bigint; h0 text; h1 text; BEGIN
 SELECT count(*), md5(string_agg(to_jsonb(r)::text,'|' ORDER BY receipt_record_id)) INTO n0,h0 FROM private.lf_programming_context_handoff_receipts_v1 r;
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE')$c$,'PG01_RUNTIME_DEFINITION_NOT_CURRENT')
 THEN RAISE EXCEPTION 'TEST_FAIL:20_candidate_replay_not_rejected'; END IF;
 SELECT count(*), md5(string_agg(to_jsonb(r)::text,'|' ORDER BY receipt_record_id)) INTO n1,h1 FROM private.lf_programming_context_handoff_receipts_v1 r;
 v:=private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'));
 IF n0 IS DISTINCT FROM n1 OR h0 IS DISTINCT FROM h1 OR v->>'reason' IS DISTINCT FROM 'PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED' THEN
  RAISE EXCEPTION 'TEST_FAIL:20_candidate % % % %',n0,n1,h0=h1,v; END IF;
 RAISE NOTICE 'HA3_EVIDENCE:20:{"receipts_before":%,"receipts_after":%,"ledger_unchanged":%,"resolve_reason":"%"}',n0,n1,h0=h1,v->>'reason';
 INSERT INTO passed VALUES(20); END $$;
-- 21 Selector receipt that does not match its result (tampered after binding).
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at) VALUES('PROFILE7','EJECUCION_PERFIL_LF','PERFIL','A9','COMPLETED',jsonb_build_object(
 'router_profile_handoff',jsonb_build_object('channel','PROGRAMACION','semantic_request',jsonb_build_object('router_action_binding',pg_temp.binding())))
 ||jsonb_set(pg_temp.selection('B2B-AUTH-001'),'{screen_selection_result,semantic_receipt_sha256}',to_jsonb(repeat('a',64))),now(),now());
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000007','PROFILE7');
SELECT pg_temp.judge('JUDGE7','aaaaaaaa-0000-4000-8000-000000000007');
DO $$ BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE7',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000007','PROFILE7'),'JUDGE7')$c$,'PG01_RUNTIME_SCREEN_SELECTION_INVALID')
 THEN RAISE EXCEPTION 'TEST_FAIL:21_selection_receipt'; END IF; INSERT INTO passed VALUES(21); END $$;
-- ============ H-A3 regressions (22-27) ============================================
-- Fresh profile/context/judge; the screen is CANDIDATO at this point (set in test 20).
SELECT pg_temp.setup_profile('PROFILE8');
SELECT pg_temp.ctx('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8');
SELECT pg_temp.judge('JUDGE8','aaaaaaaa-0000-4000-8000-000000000008');
CREATE FUNCTION pg_temp.nrec(p_ctx uuid DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $q$
 SELECT count(*) FROM private.lf_programming_context_handoff_receipts_v1 WHERE p_ctx IS NULL OR context_id=p_ctx $q$;
-- 22 G1+G2: issue on CANDIDATO is rejected with the new code and leaves zero rows.
DO $$ DECLARE a bigint:=pg_temp.nrec(); c bigint:=pg_temp.nrec('aaaaaaaa-0000-4000-8000-000000000008'); BEGIN
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE8',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'JUDGE8')$c$,'PG01_RUNTIME_DEFINITION_NOT_CURRENT')
 THEN RAISE EXCEPTION 'TEST_FAIL:22_candidate_issue_not_rejected'; END IF;
 IF pg_temp.nrec() IS DISTINCT FROM a OR pg_temp.nrec('aaaaaaaa-0000-4000-8000-000000000008') IS DISTINCT FROM 0 OR c IS DISTINCT FROM 0 THEN
  RAISE EXCEPTION 'TEST_FAIL:22_rows_persisted % %',a,pg_temp.nrec(); END IF;
 RAISE NOTICE 'HA3_EVIDENCE:22:{"receipts_before":%,"receipts_after":%,"rows_for_context":%}',a,pg_temp.nrec(),pg_temp.nrec('aaaaaaaa-0000-4000-8000-000000000008');
 INSERT INTO passed VALUES(22); END $$;
-- 23 G3: after promotion to VIGENTE the SAME binding records normally (no replay conflict).
UPDATE lf_ops.pantallas SET estado='VIGENTE' WHERE codigo='B2B-AUTH-001';
DO $$ DECLARE a bigint:=pg_temp.nrec(); r jsonb; BEGIN
 r:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE8',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'JUDGE8');
 IF r->>'status' IS DISTINCT FROM 'RECORDED' OR r->>'verdict' IS DISTINCT FROM 'ACCEPT' OR jsonb_array_length(r->'warnings') IS DISTINCT FROM 0
    OR pg_temp.nrec() IS DISTINCT FROM a+1 OR pg_temp.nrec('aaaaaaaa-0000-4000-8000-000000000008') IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'TEST_FAIL:23_promotion % %',r,pg_temp.nrec(); END IF;
 RAISE NOTICE 'HA3_EVIDENCE:23:{"status":"%","receipts_before":%,"receipts_after":%}',r->>'status',a,pg_temp.nrec();
 INSERT INTO passed VALUES(23); END $$;
-- 24 G5: identical re-issue keeps IDEMPOTENT_REPLAY semantics (same row, no new row).
DO $$ DECLARE a bigint:=pg_temp.nrec(); r1 jsonb; r2 jsonb; BEGIN
 r1:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE8',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'JUDGE8');
 r2:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE8',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'JUDGE8');
 IF r1->>'status' IS DISTINCT FROM 'IDEMPOTENT_REPLAY' OR r2->>'status' IS DISTINCT FROM 'IDEMPOTENT_REPLAY'
    OR r1->>'receipt_record_id' IS DISTINCT FROM r2->>'receipt_record_id' OR r1->>'binding_key_sha256' IS DISTINCT FROM r2->>'binding_key_sha256'
    OR pg_temp.nrec() IS DISTINCT FROM a THEN RAISE EXCEPTION 'TEST_FAIL:24_idempotent % %',r1,r2; END IF;
 RAISE NOTICE 'HA3_EVIDENCE:24:{"status":"%","receipts_before":%,"receipts_after":%}',r2->>'status',a,pg_temp.nrec();
 INSERT INTO passed VALUES(24); END $$;
-- 25 G4: resolve_v2 admits while VIGENTE and fails closed when the definition is no longer current;
--    the writer then rejects again without touching the stored row.
DO $$ DECLARE v1 jsonb; v2 jsonb; h0 text; h1 text; a bigint; BEGIN
 v1:=private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'));
 UPDATE lf_ops.pantallas SET estado='CANDIDATO' WHERE codigo='B2B-AUTH-001';
 v2:=private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'));
 SELECT md5(to_jsonb(r)::text) INTO h0 FROM private.lf_programming_context_handoff_receipts_v1 r WHERE context_id='aaaaaaaa-0000-4000-8000-000000000008';
 a:=pg_temp.nrec();
 IF NOT pg_temp.expect($c$SELECT private.fn_lf_programming_receipt_record_runtime_v1('PROFILE8',pg_temp.binding(),pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'JUDGE8')$c$,'PG01_RUNTIME_DEFINITION_NOT_CURRENT')
 THEN RAISE EXCEPTION 'TEST_FAIL:25_writer_not_rejected'; END IF;
 SELECT md5(to_jsonb(r)::text) INTO h1 FROM private.lf_programming_context_handoff_receipts_v1 r WHERE context_id='aaaaaaaa-0000-4000-8000-000000000008';
 IF v1->>'reason' IS DISTINCT FROM 'PG01_V2_ADMITTED' OR (v1->>'admissible')::boolean IS DISTINCT FROM true
    OR v2->>'reason' IS DISTINCT FROM 'PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED' OR (v2->>'admissible')::boolean IS DISTINCT FROM false
    OR h0 IS DISTINCT FROM h1 OR pg_temp.nrec() IS DISTINCT FROM a THEN RAISE EXCEPTION 'TEST_FAIL:25_resolve % %',v1,v2; END IF;
 RAISE NOTICE 'HA3_EVIDENCE:25:{"vigente":"%","candidato":"%","row_unchanged":%}',v1->>'reason',v2->>'reason',h0=h1;
 INSERT INTO passed VALUES(25); END $$;
-- 26 G7 Train: the D7 Train wrapper is untouched (records with the Train actor even on CANDIDATO;
--    a non-Train actor is still refused).
DO $$ DECLARE rc jsonb; r jsonb; a bigint:=pg_temp.nrec(); BEGIN
 rc:=private.fn_lf_programming_context_handoff_receive_v1('aaaaaaaa-0000-4000-8000-000000000008',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000008'));
 r:=private.fn_lf_programming_context_handoff_receipt_record_v1(rc->'receipt','{"schema_version":"TEST"}',
   jsonb_set(pg_temp.ho('aaaaaaaa-0000-4000-8000-000000000008','PROFILE8'),'{target_ref}','"TRAIN-TARGET-8"'),'TRAIN');
 IF r->>'status' IS DISTINCT FROM 'RECORDED' OR pg_temp.nrec() IS DISTINCT FROM a+1
  OR NOT pg_temp.expect($c$SELECT private.fn_lf_programming_context_handoff_receipt_record_v1('{}','{}','{}','PROFILE8')$c$,'PG01_RECEIPT_WRITER_EXECUTION_NOT_AUTHORIZED')
 THEN RAISE EXCEPTION 'TEST_FAIL:26_train %',r; END IF;
 INSERT INTO passed VALUES(26); END $$;
-- 27 G7 permissions: SECURITY DEFINER kept and EXECUTE only for service_role (same as test 03 and the migration post-check).
DO $$ BEGIN
 IF (SELECT prosecdef FROM pg_proc WHERE oid='private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)'::regprocedure) IS DISTINCT FROM true
 OR NOT has_function_privilege('service_role','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('anon','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('authenticated','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 THEN RAISE EXCEPTION 'TEST_FAIL:27_permissions'; END IF; INSERT INTO passed VALUES(27); END $$;
DO $$ DECLARE n int; BEGIN SELECT count(*) INTO n FROM passed; IF n IS DISTINCT FROM 27 THEN RAISE EXCEPTION 'TEST_FAIL:COUNT_%',n; END IF;
 RAISE NOTICE 'PG01_RUNTIME_WRITER_TESTS_PASSED:%',n; END $$;
ROLLBACK;
