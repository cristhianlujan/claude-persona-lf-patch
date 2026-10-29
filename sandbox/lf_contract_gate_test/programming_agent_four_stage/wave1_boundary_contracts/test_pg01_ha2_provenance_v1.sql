\set ON_ERROR_STOP on
-- Disposable PostgreSQL 17. Run from repository root. Never run on live DB.
-- PG-01 H-A2 provenance matrix (17 negatives + H-A3 + positives). Run twice: default (production
-- writer, gate on) and -v lift=on (gate removed in this test only). Synthetic chains, NOT authentic review.
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
\i sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/pg01_authority_programacion_fixture.sql
CREATE TEMP TABLE att_lines(n bigint GENERATED ALWAYS AS IDENTITY,line text);
\copy att_lines(line) FROM 'supabase/migrations/20261029160000_lf_pg01_authority_attestations_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'\nBEGIN;\n',E'\n'),E'\nCOMMIT;',E'\n') FROM att_lines
\gexec
GRANT SELECT ON private.lf_decision_context_asof_v1 TO programacion_verifier;
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
\if :{?lift}
\else
\set lift off
\endif
SELECT replace(replace(CASE WHEN :'lift'='on' THEN replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'\n RAISE EXCEPTION ''PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED'';','') ELSE string_agg(coalesce(line,''),E'\n' ORDER BY n) END,E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src_lines
\gexec
SELECT set_config('ha2.gate',:'gate',false), set_config('ha2.lift',:'lift',false);
\if :{?red}
\else
\set red off
\endif
SELECT set_config('ha2.red',:'red',false);
DO $g$ BEGIN IF current_setting('ha2.red')<>'on' AND current_setting('ha2.gate')<>'gate_present' THEN RAISE EXCEPTION '%',current_setting('ha2.gate'); END IF; END $g$;
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

-- ===================== H-A2 matrix (ENSAYO_NO_CERTIFICA) =====================
\pset tuples_only on
\pset format unaligned
SELECT pg_temp.putcontext('aaaaaaaa-0000-4000-8000-000000000002','PROFILE');
CREATE FUNCTION pg_temp.nrec() RETURNS bigint LANGUAGE sql AS $q$ SELECT count(*) FROM private.lf_programming_context_handoff_receipts_v1 $q$;
CREATE FUNCTION pg_temp.mkjudge(p_id text, p_ctx text DEFAULT 'aaaaaaaa-0000-4000-8000-000000000001', p_attest int DEFAULT 2) RETURNS void LANGUAGE plpgsql AS $q$ BEGIN
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at)
 VALUES(p_id,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','ANALYSIS','A9','COMPLETED',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE',
  'subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id=p_ctx::uuid),'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/'||p_ctx),now(),now());
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload) VALUES(p_id,'semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}'),(p_id,'judge_record','STEP_PASS_WITH_EVIDENCE','{}');
 PERFORM pg_temp.govern(p_id,p_attest); END $q$;
CREATE TEMP TABLE ha2_results_raw(j jsonb);
CREATE FUNCTION pg_temp.run(p_case text, p_judge text, p_note text) RETURNS text LANGUAGE plpgsql AS $q$
DECLARE n0 bigint:=pg_temp.nrec(); r jsonb; res text; BEGIN
 BEGIN r:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),p_judge);
  res:=coalesce(r->>'status','?')||'/'||coalesce(r->>'verdict','?');
 EXCEPTION WHEN OTHERS THEN res:='ERROR:'||SQLERRM; END;
  RETURN jsonb_build_object('case',p_case,'judge',p_judge,'result',res,'ledger_before',n0,'ledger_after',pg_temp.nrec(),'delta',pg_temp.nrec()-n0,'note',p_note)::text; END $q$;
-- precondition dump of the governed baseline judge
SELECT 'PRE '||jsonb_build_object('judge',to_jsonb(e)-'manifest','manifest',e.manifest)::text FROM public.lf_operation_execution e WHERE execution_id='JUDGE';

SAVEPOINT s; SELECT pg_temp.run('A2-N1','PROFILE','judge == producer') AS r1 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r1'::jsonb);

SAVEPOINT s; SELECT pg_temp.run('A2-N2','NO-SUCH-JUDGE','judge does not exist') AS r2 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r2'::jsonb);

SAVEPOINT s;
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at,created_by_execution_id)
 VALUES('J-R4','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','ANALYSIS','A9','COMPLETED',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE',
  'subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001'),
  'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/aaaaaaaa-0000-4000-8000-000000000001'),now(),now(),'PROFILE');
 INSERT INTO public.lf_operation_execution_steps VALUES('J-R4','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','PROFILE'),('J-R4','judge_record','STEP_PASS_WITH_EVIDENCE','{}','PROFILE');
 SELECT 'PRE '||jsonb_build_object('judge',to_jsonb(e))::text FROM public.lf_operation_execution e WHERE execution_id='J-R4';
 SELECT pg_temp.run('R4 / A2-N3','J-R4','judge row and steps written by the producer (service_role path), distinct id, passes original surface checks') AS r3 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r3'::jsonb);

SAVEPOINT s;
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at,created_by_execution_id)
 SELECT 'J-R4F',operation_code,target_type,target_code,status,manifest||jsonb_build_object('orchestrator_execution_id','ORCH-FAKE',
   'capability_binding_receipt',jsonb_build_object('ready',true,'entry_guard',jsonb_build_object('ready',true,'receipt_id',gen_random_uuid()::text))),started_at,completed_at,'ORCH-FAKE'
 FROM public.lf_operation_execution WHERE execution_id='JUDGE';
 INSERT INTO public.lf_operation_execution_steps VALUES('J-R4F','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','J-R4F'),('J-R4F','judge_record','STEP_PASS_WITH_EVIDENCE','{}','J-R4F');
 SELECT pg_temp.run('A2-N3b','J-R4F','producer-forged judge: copied manifest, real subject receipt reused, JSON-only binding, invented actor, no dispatch/binding rows') AS r4 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r4'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N4','aaaaaaaa-0000-4000-8000-000000000002');
 SELECT pg_temp.run('A2-N4','J-N4','judge governed for another subject (context 002)') AS r5 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r5'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N4B');
 WITH v AS (INSERT INTO private.lf_evidence_ledger_v1(execution_id,capability_code,gate_code,receipt_kind,subject_type,subject_ref,subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,verification_method,verification_state,receipt_payload,receipt_sha256,created_by_execution_id)
  SELECT execution_id,capability_code,gate_code,receipt_kind,'OTHER_SUBJECT_TYPE',subject_ref,subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,verification_method,'VERIFIED',receipt_payload,receipt_sha256,created_by_execution_id
  FROM private.lf_evidence_ledger_v1 WHERE receipt_id=(SELECT (manifest->>'subject_receipt_id')::uuid FROM public.lf_operation_execution WHERE execution_id='J-N4B') RETURNING receipt_id)
 UPDATE public.lf_operation_execution SET manifest=manifest||jsonb_build_object('subject_type','OTHER_SUBJECT_TYPE','subject_receipt_id',(SELECT receipt_id::text FROM v)) WHERE execution_id='J-N4B';
 SELECT pg_temp.run('A2-N4b','J-N4B','same ref/hash but subject_type of another contract (tautological check in candidate)') AS r6 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r6'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N5'); SELECT pg_temp.mkjudge('J-OTHER','aaaaaaaa-0000-4000-8000-000000000002');
 UPDATE public.lf_operation_execution SET manifest=manifest||jsonb_build_object('subject_receipt_id',(SELECT manifest->>'subject_receipt_id' FROM public.lf_operation_execution WHERE execution_id='J-OTHER')) WHERE execution_id='J-N5';
 SELECT pg_temp.run('A2-N5','J-N5','VERIFIED evidence receipt of another subject') AS r7 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r7'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N6');
 UPDATE private.lf_evidence_ledger_v1 SET verification_state='ANCHORED' WHERE receipt_id=(SELECT (manifest->>'subject_receipt_id')::uuid FROM public.lf_operation_execution WHERE execution_id='J-N6');
 SELECT pg_temp.run('A2-N6','J-N6','subject receipt ANCHORED, not VERIFIED') AS r8 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r8'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N6B');
 UPDATE private.lf_evidence_ledger_v1 SET created_by_execution_id='PROFILE' WHERE receipt_id=(SELECT (manifest->>'subject_receipt_id')::uuid FROM public.lf_operation_execution WHERE execution_id='J-N6B');
 SELECT pg_temp.run('A2-N6b','J-N6B','VERIFIED subject receipt anchored by the producer itself') AS r9 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r9'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N7A');
 UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{capability_binding_receipt,ready}','false') WHERE execution_id='J-N7A';
 SELECT pg_temp.run('A2-N7a','J-N7A','capability_binding_receipt.ready=false') AS r10 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r10'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N7B'); DELETE FROM public.lf_capability_binding WHERE execution_id='J-N7B';
 SELECT pg_temp.run('A2-N7b','J-N7B','JSON says ready=true but no lf_capability_binding row') AS r11 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r11'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N7C'); UPDATE public.lf_capability_binding SET bound_manifest_sha256=repeat('d',64) WHERE execution_id='J-N7C';
 SELECT pg_temp.run('A2-N7c','J-N7C','binding row bound to another capability manifest') AS r12 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r12'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N7D'); UPDATE private.lf_orchestrator_dispatch_receipts_v1 SET dispatch_scope='{"tampered":true}' WHERE consumer_execution_id='J-N7D';
 SELECT pg_temp.run('A2-N7d','J-N7D','dispatch receipt content does not match its digest') AS r13 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r13'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N7E'); UPDATE private.lf_orchestrator_dispatch_receipts_v1 SET consumer_execution_id='SOMEONE-ELSE' WHERE consumer_execution_id='J-N7E';
 SELECT pg_temp.run('A2-N7e','J-N7E','dispatch receipt issued for another consumer') AS r14 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r14'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N8'); UPDATE public.lf_operation_execution_steps SET created_by_execution_id='PROFILE' WHERE execution_id='J-N8';
 SELECT pg_temp.run('A2-N8','J-N8','review steps (PASS) written by the producer') AS r15 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r15'::jsonb);

SAVEPOINT s; SELECT pg_temp.mkjudge('J-N8B'); UPDATE public.lf_operation_execution_steps SET created_by_execution_id='UNKNOWN' WHERE execution_id='J-N8B';
 SELECT pg_temp.run('A2-N8b','J-N8B','review steps with unattributed author (column default UNKNOWN)') AS r16 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r16'::jsonb);

SAVEPOINT s; UPDATE lf_ops.pantallas SET estado='CANDIDATO' WHERE codigo='B2B-AUTH-001';
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,started_at,completed_at,created_by_execution_id)
 SELECT 'J-R4',operation_code,'ANALYSIS','A9',status,manifest-'producer_execution_id'-'subject_receipt_id'-'capability_binding_receipt',started_at,completed_at,'PROFILE' FROM public.lf_operation_execution WHERE execution_id='JUDGE';
 INSERT INTO public.lf_operation_execution_steps VALUES('J-R4','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','PROFILE'),('J-R4','judge_record','STEP_PASS_WITH_EVIDENCE','{}','PROFILE');
 SELECT pg_temp.run('H3-R4','J-R4','screen CANDIDATO + producer judge: H-A3 must reject first') AS r17 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r17'::jsonb);

SAVEPOINT s; UPDATE lf_ops.pantallas SET estado='CANDIDATO' WHERE codigo='B2B-AUTH-001';
 SELECT pg_temp.run('H3-GOV','JUDGE','screen CANDIDATO + sandbox-governed judge') AS r18 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r18'::jsonb);

SAVEPOINT s; SELECT pg_temp.run('P0-SANDBOX','JUDGE','sandbox-governed judge (synthetic chain written by owner, NOT authentic)') AS r19 \gset
SELECT pg_temp.run('P0-SANDBOX-REPLAY','JUDGE','idempotent replay of the same issue') AS r20 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r19'::jsonb);
INSERT INTO ha2_results_raw VALUES (:'r20'::jsonb);


SAVEPOINT s; SELECT pg_temp.mkjudge('J-DA1','aaaaaaaa-0000-4000-8000-000000000001',0);
 SELECT pg_temp.run('DA-1_self_declared_VERIFIED','J-DA1','ledger VERIFIED via caller-declared anchor, no authenticated readback') AS rda1 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rda1'::jsonb);
SAVEPOINT s; SELECT pg_temp.mkjudge('J-DA2','aaaaaaaa-0000-4000-8000-000000000001',0);
 UPDATE public.lf_operation_execution SET manifest=manifest||jsonb_build_object('source_head_sha',repeat('2',40)) WHERE execution_id='J-DA2';
 SELECT pg_temp.run('DA-2_wrong_head','J-DA2','judge bound to a HEAD different from the verified receipt') AS rda2 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rda2'::jsonb);
SAVEPOINT s; SELECT pg_temp.mkjudge('J-DB1','aaaaaaaa-0000-4000-8000-000000000001',1);
 SELECT pg_temp.run('DB-1_no_reviewer_attestation','J-DB1','subject verified, full begin_v3-shaped chain, no authenticated reviewer') AS rdb1 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rdb1'::jsonb);
SAVEPOINT s; SELECT pg_temp.mkjudge('J-DB2');
 UPDATE public.lf_operation_execution_steps SET evidence_payload='{"verdict":"PASS","rewritten":true}' WHERE execution_id='J-DB2' AND step_id='semantic_review';
 SELECT pg_temp.run('DB-2_steps_rewritten_after_attestation','J-DB2','service_role rewrites review steps (author kept) after the auditor attested') AS rdb2 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rdb2'::jsonb);
SAVEPOINT s; SELECT pg_temp.mkjudge('J-DB3');
 UPDATE public.lf_operation_execution SET manifest=manifest||'{"injected":true}' WHERE execution_id='J-DB3';
 SELECT pg_temp.run('DB-3_manifest_changed_after_attestation','J-DB3','manifest changed after the auditor attested') AS rdb3 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rdb3'::jsonb);
SAVEPOINT s; SELECT pg_temp.mkjudge('J-DB4');
 SELECT set_config('t.db4',pg_temp.as_service($q$INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id) VALUES('J-DB4-FAKE','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','PROGRAMMING_ANALYSIS_PACKAGE','x','COMPLETED','{}','ORCH-FAKE')$q$),false);
 UPDATE public.lf_operation_execution f SET manifest=j.manifest, target_code=j.target_code, created_by_execution_id=j.created_by_execution_id FROM public.lf_operation_execution j WHERE j.execution_id='J-DB4' AND f.execution_id='J-DB4-FAKE';
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload,created_by_execution_id) VALUES('J-DB4-FAKE','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','J-DB4-FAKE'),('J-DB4-FAKE','judge_record','STEP_PASS_WITH_EVIDENCE','{}','J-DB4-FAKE');
 SELECT pg_temp.run('DB-4_clone_of_attested_judge','J-DB4-FAKE','service_role clones an attested judge (manifest, receipts, steps) under a new id') AS rdb4 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'rdb4'::jsonb);
-- ============ P1 via REAL begin_v3 chain in disposable DB (ENSAYO_NO_CERTIFICA, NOT authentic evidence) ============
\pset tuples_only on
\pset format unaligned
\i sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/pg01_ha2_real_governance_functions.sql
INSERT INTO public.lf_capability_current VALUES('INDEPENDENT_ASSURANCE','2.0.1',repeat('c',64),NULL,now(),'SANDBOX','sandbox');
INSERT INTO public.lf_capability_version_registry VALUES('INDEPENDENT_ASSURANCE','2.0.1',2,'{"contract":{"subject_contract":{"mode":"CONTRACT_DRIVEN_ANY_SUBJECT","subject_type_whitelist":false}}}');
INSERT INTO public.lf_capability_registry(capability_code) VALUES('INDEPENDENT_ASSURANCE');
INSERT INTO public.lf_operation_registry VALUES('ORQUESTACION_SANDBOX','ORCHESTRATION','OP_OPERATIONAL','1.0.0');
-- nrec defined above
CREATE FUNCTION pg_temp.nrec_unused() RETURNS bigint LANGUAGE sql AS $q$ SELECT count(*) FROM private.lf_programming_context_handoff_receipts_v1 $q$;
-- Subject receipt (sandbox mirror of a VERIFIED anchor by an EVIDENCE_LEDGER execution; producer != anchor actor)
CREATE FUNCTION pg_temp.subject_receipt() RETURNS uuid LANGUAGE sql AS $q$
 INSERT INTO private.lf_evidence_ledger_v1(execution_id,capability_code,gate_code,receipt_kind,subject_type,subject_ref,subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,verification_method,verification_state,receipt_payload,receipt_sha256,created_by_execution_id,verified_at)
 SELECT 'PROFILE','PROGRAMMING','PG01_SUBJECT','SUBJECT','PROGRAMMING_ANALYSIS_PACKAGE','PROGRAMMING_ANALYSIS_PACKAGE/'||context_id,context_sha256,'87e0f8736415da5fa1fdf75d60edff73e44b55ca','SANDBOX','R','P','PR','M','VERIFIED','{}',repeat('e',64),'LEDGER-SANDBOX',now()
 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001' RETURNING receipt_id $q$;
CREATE FUNCTION pg_temp.begin_judge(p_judge text, p_orch text, p_actor text) RETURNS jsonb LANGUAGE plpgsql AS $q$
DECLARE rid uuid:=pg_temp.subject_receipt(); c record; plan text:=encode(extensions.digest('plan:'||p_judge,'sha256'),'hex');
 req text:=encode(extensions.digest('req:'||p_judge,'sha256'),'hex'); m jsonb; d jsonb; b jsonb; ref text;
BEGIN
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001';
 ref:='PROGRAMMING_ANALYSIS_PACKAGE/'||c.context_id;
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id)
 VALUES(p_orch,'ORQUESTACION_SANDBOX','ORCHESTRATION','PG01','IN_PROGRESS','{}',p_orch) ON CONFLICT DO NOTHING;
 m:=jsonb_build_object('orchestrator_execution_id',p_orch,'plan_digest',plan,'required_dimensions',jsonb_build_array('MATERIAL'),'review_required',true);
 -- 1) reservation (same key begin_v3 will replay), so the orchestrator can issue its dispatch receipt
 PERFORM public.fn_lf_operation_reserve_execution_v1(p_judge,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','PROGRAMMING_ANALYSIS_PACKAGE',ref,'idem:'||p_judge,req,p_actor,null,null,
   m||jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','capability_manifest_sha256',repeat('c',64),'subject_type','PROGRAMMING_ANALYSIS_PACKAGE','subject_ref',ref,
   'subject_sha256',c.context_sha256,'source_head_sha','87e0f8736415da5fa1fdf75d60edff73e44b55ca','subject_receipt_id',rid::text,'producer_execution_id','PROFILE',
   'runtime_activation',false,'production_activation',false,'business_effect_allowed',false));
 d:=public.fn_lf_orchestrator_dispatch_receipt_v1(p_orch,p_judge,'INDEPENDENT_ASSURANCE',plan,'{"scope":"PG01"}',p_orch);
 -- 2) real begin_v3
 b:=public.lf_independent_review_begin_v3(p_judge,'PROGRAMMING_ANALYSIS_PACKAGE',ref,c.context_sha256,'87e0f8736415da5fa1fdf75d60edff73e44b55ca',rid,'PROFILE',
   repeat('c',64),plan,(d->>'receipt_id')::uuid,req,'idem:'||p_judge,p_actor,m);
 -- 3) the judge records its own review steps and completes (sandbox stand-in for the reviewer runtime)
 INSERT INTO public.lf_operation_execution_steps VALUES(p_judge,'semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}',p_judge),(p_judge,'judge_record','STEP_PASS_WITH_EVIDENCE','{}',p_judge);
 UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=now() WHERE execution_id=p_judge;
 IF pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',format('INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES(%L,%L)',rid,c.context_id))<>'OK'
 OR pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',format('INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES(%L)',p_judge))<>'OK' THEN
  RAISE EXCEPTION 'P1_ATTESTATION_FAILED'; END IF;
 RETURN jsonb_build_object('dispatch',d,'begin_v3',b); END $q$;
CREATE FUNCTION pg_temp.run_unused(p_case text, p_judge text, p_note text) RETURNS text LANGUAGE plpgsql AS $q$
DECLARE n0 bigint:=pg_temp.nrec(); r jsonb; res text; BEGIN
 BEGIN r:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),p_judge);
  res:=coalesce(r->>'status','?')||'/'||coalesce(r->>'verdict','?');
 EXCEPTION WHEN OTHERS THEN res:='ERROR:'||SQLERRM; END;
 RETURN jsonb_build_object('case',p_case,'judge',p_judge,'result',res,'ledger_before',n0,'ledger_after',pg_temp.nrec(),'delta',pg_temp.nrec()-n0,'note',p_note)::text; END $q$;

SAVEPOINT s;
 SELECT 'CHAIN '||pg_temp.begin_judge('J-P1','ORCH-P1','ORCH-P1')::text;
 SELECT 'MANIFEST '||jsonb_build_object('created_by',created_by_execution_id,'target_type',target_type,'status',status,'manifest',manifest)::text FROM public.lf_operation_execution WHERE execution_id='J-P1';
 SELECT pg_temp.run('P1-SANDBOX-BEGIN_V3','J-P1','judge built by the real begin_v3/dispatch/bind functions, orchestrator actor') AS r21 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r21'::jsonb);

SAVEPOINT s;
 SELECT 'CHAIN '||pg_temp.begin_judge('J-P1N','ORCH-P1N','PROFILE')::text;
 SELECT pg_temp.run('P1-N3-REAL','J-P1N','real begin_v3 but reservation actor = producer (begin_v3 accepts it)') AS r22 \gset
ROLLBACK TO SAVEPOINT s;
INSERT INTO ha2_results_raw VALUES (:'r22'::jsonb);



-- ===================== assertions =====================
CREATE TEMP TABLE ha2_expected(case_id text PRIMARY KEY, gated text, lifted text);
INSERT INTO ha2_expected VALUES
('DA-2_wrong_head','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED'),
('DA-1_self_declared_VERIFIED','ERROR:PG01_RUNTIME_SUBJECT_VERIFICATION_UNATTESTED','ERROR:PG01_RUNTIME_SUBJECT_VERIFICATION_UNATTESTED'),
('DB-1_no_reviewer_attestation','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED'),
('DB-2_steps_rewritten_after_attestation','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED'),
('DB-3_manifest_changed_after_attestation','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED','ERROR:PG01_RUNTIME_JUDGE_ACTOR_UNATTESTED'),
('DB-4_clone_of_attested_judge','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID'),
('A2-N1','ERROR:PG01_RUNTIME_JUDGE_NOT_INDEPENDENT','ERROR:PG01_RUNTIME_JUDGE_NOT_INDEPENDENT'),
('A2-N2','ERROR:PG01_RUNTIME_JUDGE_INVALID','ERROR:PG01_RUNTIME_JUDGE_INVALID'),
('R4 / A2-N3','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID'),
('A2-N3b','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID'),
('A2-N4','ERROR:PG01_RUNTIME_JUDGE_INVALID','ERROR:PG01_RUNTIME_JUDGE_INVALID'),
('A2-N4b','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID'),
('A2-N5','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED'),
('A2-N6','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED'),
('A2-N6b','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED','ERROR:PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED'),
('A2-N7a','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID'),
('A2-N7b','ERROR:PG01_RUNTIME_JUDGE_CAPABILITY_BINDING_INVALID','ERROR:PG01_RUNTIME_JUDGE_CAPABILITY_BINDING_INVALID'),
('A2-N7c','ERROR:PG01_RUNTIME_JUDGE_CAPABILITY_BINDING_INVALID','ERROR:PG01_RUNTIME_JUDGE_CAPABILITY_BINDING_INVALID'),
('A2-N7d','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID'),
('A2-N7e','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID','ERROR:PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID'),
('A2-N8','ERROR:PG01_RUNTIME_JUDGE_REVIEW_RESULT_UNPROVEN','ERROR:PG01_RUNTIME_JUDGE_REVIEW_RESULT_UNPROVEN'),
('A2-N8b','ERROR:PG01_RUNTIME_JUDGE_REVIEW_RESULT_UNPROVEN','ERROR:PG01_RUNTIME_JUDGE_REVIEW_RESULT_UNPROVEN'),
('P1-N3-REAL','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID','ERROR:PG01_RUNTIME_JUDGE_PROVENANCE_INVALID'),
('H3-R4','ERROR:PG01_RUNTIME_DEFINITION_NOT_CURRENT','ERROR:PG01_RUNTIME_DEFINITION_NOT_CURRENT'),
('H3-GOV','ERROR:PG01_RUNTIME_DEFINITION_NOT_CURRENT','ERROR:PG01_RUNTIME_DEFINITION_NOT_CURRENT'),
('P0-SANDBOX','ERROR:PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED','RECORDED/ACCEPT'),
('P0-SANDBOX-REPLAY','ERROR:PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED','IDEMPOTENT_REPLAY/ACCEPT'),
('P1-SANDBOX-BEGIN_V3','ERROR:PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED','RECORDED/ACCEPT');
CREATE FUNCTION pg_temp.ha2_assert() RETURNS text LANGUAGE plpgsql AS $a$
DECLARE r record; exp text; got text; d bigint; bad text[]:='{}'; n int:=0; lifted boolean:=current_setting('ha2.lift')='on';
BEGIN
 FOR r IN SELECT * FROM ha2_expected ORDER BY case_id LOOP
  exp:=CASE WHEN lifted THEN r.lifted ELSE r.gated END;
  SELECT j->>'result',(j->>'delta')::bigint INTO got,d FROM ha2_results_raw WHERE j->>'case'=r.case_id;
  IF got IS NULL THEN bad:=bad||(r.case_id||'=NOT_RUN');
  ELSIF got IS DISTINCT FROM exp THEN bad:=bad||(r.case_id||'='||got);
  ELSIF got LIKE 'ERROR:%' AND d<>0 THEN bad:=bad||(r.case_id||'=LEDGER_WRITE_AFTER_REJECT');
  ELSIF got='RECORDED/ACCEPT' AND d<>1 THEN bad:=bad||(r.case_id||'=EXPECTED_ONE_ROW');
  ELSE n:=n+1; END IF;
 END LOOP;
 IF (SELECT count(*) FROM ha2_results_raw)<>(SELECT count(*) FROM ha2_expected) THEN bad:=bad||'UNEXPECTED_CASE_COUNT'::text; END IF;
 IF cardinality(bad)>0 THEN RAISE EXCEPTION 'TEST_FAIL:HA2 passed=% failed=% :: %',n,cardinality(bad),array_to_string(bad,' | '); END IF;
 RETURN format('PG01_HA2_PROVENANCE_TESTS_PASSED:%s lift=%s',n,current_setting('ha2.lift'));
END $a$;
SELECT pg_temp.ha2_assert();
\echo PG01_HA2_DONE
ROLLBACK;
