DO $pre$ DECLARE v text; BEGIN SELECT max(version) INTO v FROM supabase_migrations.schema_migrations; IF v IS DISTINCT FROM '20260914064739' THEN RAISE EXCEPTION 'S30_MATRIX_REVISION_LEDGER_DRIFT:%',v; END IF; END $pre$;

CREATE OR REPLACE FUNCTION public.lf_test_suite_revision_sha256_v1(p_suite_code text)
RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE payload jsonb;
BEGIN
 SELECT jsonb_build_object(
   'suite',to_jsonb(s)-ARRAY['created_at','updated_at','created_by_execution_id','updated_by_execution_id'],
   'cases',coalesce((SELECT jsonb_agg(to_jsonb(c)-ARRAY['created_at','updated_at','created_by_execution_id','updated_by_execution_id'] ORDER BY c.test_order,c.test_code) FROM public.lf_test_suite_cases c WHERE c.suite_code=s.suite_code),'[]'::jsonb)
 ) INTO payload FROM public.lf_test_suites s WHERE s.suite_code=p_suite_code;
 IF payload IS NULL THEN RAISE EXCEPTION 'LF_TEST_SUITE_REVISION_MISSING:%',p_suite_code; END IF;
 RETURN encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_required_test_suite_fingerprint_v1(p_subject_type text,p_subject_code text)
RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE v text;
BEGIN
 SELECT string_agg(b.binding_code||':'||b.suite_code||'@'||public.lf_test_suite_revision_sha256_v1(b.suite_code)||':'||b.currentness_mode||':'||b.min_pass_rate::text||':'||b.false_pass_tolerance::text||':'||b.independent_review_required::text,'|' ORDER BY b.binding_code)
 INTO v
 FROM public.lf_test_requirement_bindings b
 WHERE b.status='ACTIVE' AND b.required AND b.effective_from<=clock_timestamp()
   AND b.subject_type=p_subject_type AND (b.subject_code='*' OR b.subject_code=p_subject_code)
   AND public.lf_test_requirement_applies_v1(b.binding_code,p_subject_type,p_subject_code);
 RETURN encode(extensions.digest(convert_to(coalesce(v,''),'UTF8'),'sha256'),'hex');
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_qualification_current_v1(p_subject_type text,p_subject_code text,p_revision_sha256 text)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE q public.lf_qualification_receipts%rowtype; qs text; fp text; sid bigint; req_count int;
BEGIN
 qs:=public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');
 SELECT count(*) INTO req_count FROM public.lf_test_requirement_bindings b
 WHERE b.status='ACTIVE' AND b.required AND b.effective_from<=clock_timestamp()
   AND b.subject_type=p_subject_type AND (b.subject_code='*' OR b.subject_code=p_subject_code)
   AND public.lf_test_requirement_applies_v1(b.binding_code,p_subject_type,p_subject_code);
 IF req_count=0 THEN RETURN false; END IF;
 SELECT * INTO q FROM public.lf_qualification_receipts
 WHERE subject_type=p_subject_type AND subject_code=p_subject_code AND revision_sha256=p_revision_sha256
   AND lifecycle_state_code=qs AND invalidated_at IS NULL
 ORDER BY qualified_at DESC NULLS LAST,created_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN false; END IF;
 fp:=public.lf_required_test_suite_fingerprint_v1(p_subject_type,p_subject_code);
 IF q.suite_set_fingerprint IS DISTINCT FROM fp THEN RETURN false; END IF;
 IF p_subject_type='STRATEGY' THEN
   SELECT id INTO sid FROM public.lf_strategy_snapshots WHERE snapshot_code=p_subject_code ORDER BY id DESC LIMIT 1;
   IF sid IS NULL OR q.classification_fingerprint IS DISTINCT FROM public.lf_strategy_classification_fingerprint_v1(sid) THEN RETURN false; END IF;
 END IF;
 IF EXISTS(
   SELECT 1 FROM public.lf_test_requirement_bindings b
   WHERE b.status='ACTIVE' AND b.required AND b.effective_from<=clock_timestamp()
     AND b.subject_type=p_subject_type AND (b.subject_code='*' OR b.subject_code=p_subject_code)
     AND public.lf_test_requirement_applies_v1(b.binding_code,p_subject_type,p_subject_code)
     AND NOT EXISTS(
       SELECT 1 FROM public.lf_test_suite_runs sr
       WHERE sr.suite_run_id=ANY(q.suite_run_ids) AND sr.suite_code=b.suite_code AND sr.status='PASSED'
         AND sr.metadata->>'subject_type'=p_subject_type
         AND sr.metadata->>'subject_code'=p_subject_code
         AND sr.metadata->>'revision_sha256'=p_revision_sha256
         AND sr.metadata->>'suite_revision_sha256'=public.lf_test_suite_revision_sha256_v1(b.suite_code)
     )
 ) THEN RETURN false; END IF;
 RETURN true;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_execution_qualification_guard_v1(p_snapshot_id bigint,p_execution_started_at timestamptz)
RETURNS void LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE s public.lf_strategy_snapshots%rowtype; gate_from timestamptz; rev text;
BEGIN
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_TARGET_MISSING_ID:%',p_snapshot_id; END IF;
 gate_from:=public.lf_qualification_gate_effective_from_v1('STRATEGY');
 IF gate_from IS NOT NULL AND p_execution_started_at>=gate_from THEN
   rev:=public.lf_strategy_revision_sha256_v1(s.id);
   IF NOT public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,rev) THEN
     RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_QUALIFICATION_REQUIRED:%:%',s.snapshot_code,rev;
   END IF;
 END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_lifecycle_from_execution_step_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE x public.lf_operation_execution%rowtype; s public.lf_strategy_snapshots%rowtype; target_state text;
BEGIN
 IF NEW.step_id<>'strategy_resolve' OR NEW.status<>'PASS_CLEAN' THEN RETURN NEW; END IF;
 SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=NEW.execution_id;
 IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.target_type<>'STRATEGY' THEN RETURN NEW; END IF;
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE snapshot_code=x.target_code ORDER BY id DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_TARGET_MISSING:%',x.target_code; END IF;
 PERFORM public.lf_strategy_execution_qualification_guard_v1(s.id,x.started_at);
 target_state:=public.lf_lifecycle_resolve_transition_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'START_EXECUTION');
 IF target_state IS DISTINCT FROM s.lifecycle_state_code THEN
   UPDATE public.lf_strategy_snapshots SET lifecycle_state_code=target_state,updated_at=clock_timestamp(),updated_by_execution_id=x.execution_id WHERE id=s.id;
 END IF;
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_canary_strategy_unqualified_execution_block_v1(p_snapshot_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE s public.lf_strategy_snapshots%rowtype; qstate text; blocked boolean:=false; msg text;
BEGIN
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
 IF NOT FOUND OR public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN RETURN jsonb_build_object('passed',false,'reason','INVALID_CANARY_FIXTURE'); END IF;
 qstate:=public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');
 BEGIN
   UPDATE public.lf_qualification_receipts q
   SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'INVALIDATE_QUALIFICATION'),invalidated_at=clock_timestamp()
   WHERE q.subject_type='STRATEGY' AND q.subject_code=s.snapshot_code AND q.lifecycle_state_code=qstate AND q.invalidated_at IS NULL;
   PERFORM public.lf_strategy_execution_qualification_guard_v1(s.id,clock_timestamp());
   RAISE EXCEPTION USING ERRCODE='P0Q11',MESSAGE='S30_CANARY_EXPECTED_QUALIFICATION_BLOCK_NOT_RAISED';
 EXCEPTION WHEN SQLSTATE 'P0Q11' THEN RAISE;
   WHEN OTHERS THEN
     GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
     IF msg LIKE 'LF_STRATEGY_EXECUTION_QUALIFICATION_REQUIRED:%' THEN blocked:=true; ELSE RAISE; END IF;
 END;
 RETURN jsonb_build_object('passed',blocked,'snapshot_id',s.id,'snapshot_code',s.snapshot_code,'expected_block','LF_STRATEGY_EXECUTION_QUALIFICATION_REQUIRED');
EXCEPTION WHEN SQLSTATE 'P0Q11' THEN RETURN jsonb_build_object('passed',false,'reason','GUARD_DID_NOT_BLOCK');
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_canary_strategy_material_change_invalidates_qualification_v1(p_snapshot_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE s public.lf_strategy_snapshots%rowtype; qid uuid; initial_state text; qualifying_state text; qualified_state text; stale_state text; rev text; cf text; fp text; observed text; ok boolean:=false;
BEGIN
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
 IF NOT FOUND OR public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) THEN RETURN jsonb_build_object('passed',false,'reason','INVALID_CANARY_FIXTURE'); END IF;
 rev:=public.lf_strategy_revision_sha256_v1(s.id); cf:=public.lf_strategy_classification_fingerprint_v1(s.id); fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',s.snapshot_code);
 initial_state:=public.lf_lifecycle_initial_state_v1('QUALIFICATION_LIFECYCLE');
 qualifying_state:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',initial_state,'START_QUALIFICATION');
 qualified_state:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',qualifying_state,'PASS_QUALIFICATION');
 stale_state:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',qualified_state,'INVALIDATE_QUALIFICATION');
 BEGIN
   INSERT INTO public.lf_qualification_receipts(subject_type,subject_code,subject_ref,revision_sha256,classification_fingerprint,lifecycle_state_code,suite_set_fingerprint,created_by_execution_id)
   VALUES('STRATEGY',s.snapshot_code,format('canary://strategy/%s',s.id),rev,cf,NULL,fp,'EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001') RETURNING qualification_id INTO qid;
   UPDATE public.lf_qualification_receipts SET lifecycle_state_code=qualifying_state WHERE qualification_id=qid;
   UPDATE public.lf_qualification_receipts SET lifecycle_state_code=qualified_state,qualified_at=clock_timestamp() WHERE qualification_id=qid;
   UPDATE public.lf_strategy_snapshots SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('__qualification_invalidation_canary',clock_timestamp()::text) WHERE id=s.id;
   SELECT lifecycle_state_code INTO observed FROM public.lf_qualification_receipts WHERE qualification_id=qid;
   IF observed=stale_state THEN ok:=true; END IF;
   RAISE EXCEPTION USING ERRCODE='P0Q12',MESSAGE='S30_CANARY_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0Q12' THEN NULL;
 END;
 RETURN jsonb_build_object('passed',ok,'snapshot_id',s.id,'snapshot_code',s.snapshot_code,'observed_state',observed,'expected_state',stale_state,'persistent_mutation',false);
END $fn$;

ALTER FUNCTION public.lf_eval_strategy_matrix_probe_v1(jsonb,text,text,text) VOLATILE;

CREATE OR REPLACE FUNCTION public.lf_eval_strategy_matrix_probe_v1(p_probe jsonb,p_subject_type text,p_subject_code text,p_revision_sha256 text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE pc text:=p_probe->>'probe_code'; ok boolean:=false; actual jsonb:='{}'::jsonb; cnt int; sid bigint; def text; rp jsonb; expb boolean; actb boolean; st text; canary jsonb;
BEGIN
 IF p_subject_type='STRATEGY' THEN SELECT id INTO sid FROM public.lf_strategy_snapshots WHERE snapshot_code=p_subject_code ORDER BY id DESC LIMIT 1; END IF;
 CASE pc
 WHEN 'OP_REGISTRY_STATE_VALID' THEN SELECT EXISTS(SELECT 1 FROM public.lf_operation_registry r JOIN lf_ops.estados_catalogo s ON s.state_code=r.lifecycle_state_code AND s.entity_type='OPERATION_LIFECYCLE' AND s.status='VIGENTE' WHERE r.operation_code=p_subject_code) INTO ok;
 WHEN 'ROUTER_ACTIVE' THEN SELECT EXISTS(SELECT 1 FROM public.lf_router_action_registry WHERE operation_code=p_subject_code AND status='ACTIVE') INTO ok;
 WHEN 'ACTIVE_CONTRACT_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM public.lf_operation_contracts WHERE operation_code=p_subject_code AND status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) INTO ok;
 WHEN 'ACTIVE_STEPS_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM public.lf_operation_step_contracts WHERE operation_code=p_subject_code AND status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) INTO ok;
 WHEN 'ALL_ACTIVE_STEPS_JUDGED' THEN SELECT NOT EXISTS(SELECT 1 FROM public.lf_operation_step_contracts s WHERE s.operation_code=p_subject_code AND s.status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO') AND (s.mini_judge_code IS NULL OR NOT EXISTS(SELECT 1 FROM public.lf_operation_judges j WHERE j.operation_code=p_subject_code AND j.judge_code=s.mini_judge_code AND j.status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')))) INTO ok;
 WHEN 'STEP_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM public.lf_operation_step_contracts WHERE operation_code=p_subject_code AND step_id=p_probe->>'step_id' AND status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) INTO ok;
 WHEN 'INITIAL_LIFECYCLE_TABLE_DRIVEN' THEN SELECT count(*) INTO cnt FROM information_schema.columns WHERE table_schema='public' AND table_name=p_probe->>'table_name' AND column_name='lifecycle_state_code' AND column_default IS NULL; ok:=(cnt=1 AND public.lf_lifecycle_initial_state_v1(p_probe->>'entity_type') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=p_probe->>'table_name' AND t.tgname LIKE '%initial_lifecycle%' AND NOT t.tgisinternal));
 WHEN 'QUALIFICATION_BINDING_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM public.lf_test_requirement_bindings WHERE subject_type='OPERATION' AND subject_code=p_subject_code AND status='ACTIVE') INTO ok;
 WHEN 'ROUTER_NATURAL_ACTION' THEN rp:=public.lf_router_resolve_v1(p_probe->>'request',NULL,NULL,'STRATEGY','ROUTER'); ok:=(rp->>'action_code'=p_probe->>'expected_action'); actual:=rp;
 WHEN 'FUNCTION_TABLE_DRIVEN' THEN SELECT pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) INTO def; ok:=(def IS NOT NULL AND (strpos(def,'lf_lifecycle_resolve_transition_v1')>0 OR strpos(def,'lf_lifecycle_transition_spec_v1')>0) AND lower(def) !~ 'lifecycle_state_code\s*(=|in\s*\()\s*''strategy_(planned|active|closed|superseded)''');
 WHEN 'FUNCTION_TERMINAL_HELPER' THEN SELECT pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) INTO def; ok:=(def IS NOT NULL AND strpos(def,'lf_lifecycle_state_is_terminal_v1')>0);
 WHEN 'TRIGGER_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=p_probe->>'table_name' AND t.tgname=p_probe->>'trigger_name' AND NOT t.tgisinternal) INTO ok;
 WHEN 'OP_CONTRACT_BOOL' THEN expb:=(p_probe->>'expected')::boolean; SELECT (c.allowed->>(p_probe->>'key'))::boolean INTO actb FROM public.lf_operation_contracts c WHERE c.operation_code=p_subject_code AND c.status='ACTIVE_ENFORCEMENT' ORDER BY c.updated_at DESC LIMIT 1; ok:=(actb IS NOT DISTINCT FROM expb); actual:=jsonb_build_object('actual',actb,'expected',expb);
 WHEN 'STRATEGY_STATE_CATALOG_VALID' THEN SELECT EXISTS(SELECT 1 FROM public.lf_strategy_snapshots s JOIN lf_ops.estados_catalogo e ON e.state_code=s.lifecycle_state_code AND e.entity_type='STRATEGY_LIFECYCLE' AND e.status='VIGENTE' WHERE s.id=sid) INTO ok;
 WHEN 'STRATEGY_NOT_TERMINAL' THEN SELECT NOT public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',lifecycle_state_code) INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_REVISION_MATCH' THEN ok:=(public.lf_strategy_revision_sha256_v1(sid)=p_revision_sha256); actual:=jsonb_build_object('actual_revision',public.lf_strategy_revision_sha256_v1(sid),'expected_revision',p_revision_sha256);
 WHEN 'STRATEGY_CHARACTERISTICS_COMPLETE' THEN SELECT NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristic_catalog k WHERE k.status='ACTIVE' AND NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristics c WHERE c.snapshot_id=sid AND c.characteristic_code=k.characteristic_code AND c.enabled IS NOT NULL)) INTO ok;
 WHEN 'STRATEGY_CONDITIONAL_BINDINGS_RESOLVED' THEN SELECT NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristics c WHERE c.snapshot_id=sid AND c.enabled IS TRUE AND NOT EXISTS(SELECT 1 FROM public.lf_test_requirement_bindings b WHERE b.subject_type='STRATEGY' AND b.subject_code='*' AND b.characteristic_code=c.characteristic_code AND b.status='ACTIVE')) INTO ok;
 WHEN 'EXECUTOR_OPERATIONAL' THEN SELECT lifecycle_state_code INTO st FROM public.lf_operation_registry WHERE operation_code='EJECUCION_ESTRATEGIA_LF'; ok:=(st=public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION'));
 WHEN 'STRATEGY_POLICY_FINGERPRINT_PRESENT' THEN SELECT coalesce(metadata->>'policy_set_fingerprint','')<>'' INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_UNIQUE_CODE_VERSION' THEN SELECT count(*)=1 INTO ok FROM public.lf_strategy_snapshots s JOIN public.lf_strategy_snapshots x ON x.snapshot_code=s.snapshot_code AND x.version=s.version WHERE s.id=sid;
 WHEN 'STRATEGY_START_TRANSITION_PRESENT' THEN BEGIN PERFORM public.lf_lifecycle_transition_spec_v1('STRATEGY_LIFECYCLE',(SELECT lifecycle_state_code FROM public.lf_strategy_snapshots WHERE id=sid),'START_EXECUTION'); ok:=true; EXCEPTION WHEN OTHERS THEN ok:=false; END;
 WHEN 'STRATEGY_CURRENT_VERSION' THEN SELECT id=(SELECT max(id) FROM public.lf_strategy_snapshots x WHERE x.snapshot_code=s.snapshot_code) INTO ok FROM public.lf_strategy_snapshots s WHERE s.id=sid;
 WHEN 'STRATEGY_ASSURANCE_DECLARATION' THEN SELECT jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key'))='object' INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_ASSURANCE_EVIDENCE' THEN SELECT jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')='array' AND jsonb_array_length(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')>0 INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_UNQUALIFIED_EXECUTION_BLOCK' THEN canary:=public.lf_canary_strategy_unqualified_execution_block_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 WHEN 'STRATEGY_QUALIFICATION_INVALIDATION' THEN canary:=public.lf_canary_strategy_material_change_invalidates_qualification_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 ELSE ok:=false; actual:=jsonb_build_object('error','UNKNOWN_PROBE_CODE','probe_code',pc);
 END CASE;
 RETURN jsonb_build_object('passed',coalesce(ok,false),'probe_code',pc,'actual',actual);
END $fn$;

INSERT INTO public.lf_test_suite_cases(suite_code,test_code,test_order,title,test_type,execution_mode,severity,input_payload,expected_output,status,created_by_execution_id)
VALUES
 ('TS-STRATEGY-BASE-V1','S11',110,'Unqualified exact revision is blocked from new execution','NEGATIVE_CANARY','AUTOMATED','CRITICAL','{"probe_code":"STRATEGY_UNQUALIFIED_EXECUTION_BLOCK"}'::jsonb,'{"passed":true}'::jsonb,'CANDIDATO','EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001'),
 ('TS-STRATEGY-BASE-V1','S12',120,'Material strategy change invalidates existing qualification','ROLLBACK_CANARY','AUTOMATED','CRITICAL','{"probe_code":"STRATEGY_QUALIFICATION_INVALIDATION"}'::jsonb,'{"passed":true}'::jsonb,'CANDIDATO','EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001');

CREATE OR REPLACE FUNCTION public.lf_run_strategy_matrix_suite_v1(p_suite_code text,p_subject_type text,p_subject_code text,p_revision_sha256 text,p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE sr uuid; c public.lf_test_suite_cases%rowtype; ev jsonb; st text; passed int:=0; failed int:=0; reviews int:=0; total int:=0; startv timestamptz:=clock_timestamp(); suite_rev text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_test_suites WHERE suite_code=p_suite_code) THEN RAISE EXCEPTION 'LF_MATRIX_SUITE_MISSING:%',p_suite_code; END IF;
 suite_rev:=public.lf_test_suite_revision_sha256_v1(p_suite_code);
 INSERT INTO public.lf_test_suite_runs(suite_code,execution_id,environment,application_version,rule_set_version,executor_type,executor_name,status,started_at,manifest,metadata,created_by_execution_id)
 VALUES(p_suite_code,p_execution_id,'SUPABASE_LIVE','S30_STRATEGY_QUALIFICATION_V1','S30-QM-v1','DETERMINISTIC_DB','lf_run_strategy_matrix_suite_v1','IN_PROGRESS',startv,jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),p_execution_id) RETURNING suite_run_id INTO sr;
 FOR c IN SELECT * FROM public.lf_test_suite_cases WHERE suite_code=p_suite_code AND status='CANDIDATO' ORDER BY test_order LOOP
   total:=total+1;
   IF c.execution_mode='INDEPENDENT_REVIEW' THEN st:='REVIEW_REQUIRED'; reviews:=reviews+1; ev:=jsonb_build_object('passed',false,'review_required',true,'probe_code',c.input_payload->>'probe_code');
   ELSE ev:=public.lf_eval_strategy_matrix_probe_v1(c.input_payload,p_subject_type,p_subject_code,p_revision_sha256); IF coalesce((ev->>'passed')::boolean,false) THEN st:='PASS'; passed:=passed+1; ELSE st:='FAIL'; failed:=failed+1; END IF; END IF;
   INSERT INTO public.lf_test_runs(suite_run_id,suite_code,test_code,execution_id,operation_code,environment,application_version,rule_set_version,executor_type,executor_name,status,input_payload,expected_output,actual_output,severity,started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id)
   VALUES(sr,p_suite_code,c.test_code,p_execution_id,CASE WHEN p_subject_type='OPERATION' THEN p_subject_code ELSE NULL END,'SUPABASE_LIVE','S30_STRATEGY_QUALIFICATION_V1','S30-QM-v1','DETERMINISTIC_DB','lf_run_strategy_matrix_suite_v1',st,c.input_payload,c.expected_output,ev,c.severity,clock_timestamp(),clock_timestamp(),0,ev,jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),p_execution_id);
 END LOOP;
 UPDATE public.lf_test_suite_runs SET status=CASE WHEN failed>0 THEN 'FAILED' WHEN reviews>0 THEN 'REVIEW_REQUIRED' ELSE 'PASSED' END,completed_at=clock_timestamp(),duration_ms=(extract(epoch from (clock_timestamp()-startv))*1000)::bigint,tests_total=total,tests_passed=passed,tests_failed=failed,tests_blocked=0,tests_review_required=reviews,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE suite_run_id=sr;
 RETURN jsonb_build_object('suite_run_id',sr,'suite_code',p_suite_code,'suite_revision_sha256',suite_rev,'status',CASE WHEN failed>0 THEN 'FAILED' WHEN reviews>0 THEN 'REVIEW_REQUIRED' ELSE 'PASSED' END,'tests_total',total,'tests_passed',passed,'tests_failed',failed,'tests_review_required',reviews);
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_run_operation_qualification_v1(p_operation_code text,p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE rev text; qid uuid; qstate text; b public.lf_test_requirement_bindings%rowtype; rr jsonb; ids uuid[]:='{}'::uuid[]; any_fail boolean:=false; any_review boolean:=false; fp text;
BEGIN
 rev:=public.lf_operation_revision_sha256_v1(p_operation_code); fp:=public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code);
 INSERT INTO public.lf_qualification_receipts(subject_type,subject_code,subject_ref,revision_sha256,lifecycle_state_code,suite_set_fingerprint,created_by_execution_id) VALUES('OPERATION',p_operation_code,'supabase://public/lf_operation_registry/'||p_operation_code,rev,NULL,fp,p_execution_id) RETURNING qualification_id INTO qid;
 qstate:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',public.lf_lifecycle_initial_state_v1('QUALIFICATION_LIFECYCLE'),'START_QUALIFICATION'); UPDATE public.lf_qualification_receipts SET lifecycle_state_code=qstate,updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 FOR b IN SELECT * FROM public.lf_test_requirement_bindings WHERE subject_type='OPERATION' AND subject_code=p_operation_code AND status='ACTIVE' AND required AND effective_from<=clock_timestamp() ORDER BY binding_code LOOP rr:=public.lf_run_strategy_matrix_suite_v1(b.suite_code,'OPERATION',p_operation_code,rev,p_execution_id); ids:=array_append(ids,(rr->>'suite_run_id')::uuid); IF rr->>'status'='FAILED' THEN any_fail:=true; ELSIF rr->>'status'='REVIEW_REQUIRED' THEN any_review:=true; END IF; END LOOP;
 UPDATE public.lf_qualification_receipts SET suite_run_ids=ids,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 IF any_fail THEN UPDATE public.lf_qualification_receipts SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',lifecycle_state_code,'FAIL_QUALIFICATION'),findings=findings||jsonb_build_array(jsonb_build_object('type','MATRIX_FAILED')),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 ELSIF NOT any_review THEN UPDATE public.lf_qualification_receipts SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',lifecycle_state_code,'PASS_QUALIFICATION'),qualified_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid; END IF;
 RETURN (SELECT jsonb_build_object('qualification_id',qualification_id,'subject_code',subject_code,'revision_sha256',revision_sha256,'lifecycle_state_code',lifecycle_state_code,'suite_run_ids',suite_run_ids,'suite_set_fingerprint',suite_set_fingerprint) FROM public.lf_qualification_receipts WHERE qualification_id=qid);
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_run_strategy_qualification_v1(p_snapshot_id bigint,p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE s public.lf_strategy_snapshots%rowtype; rev text; cf text; qid uuid; qstate text; b public.lf_test_requirement_bindings%rowtype; rr jsonb; ids uuid[]:='{}'::uuid[]; any_fail boolean:=false; any_review boolean:=false; fp text;
BEGIN
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id; IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_TARGET_MISSING:%',p_snapshot_id; END IF;
 rev:=public.lf_strategy_revision_sha256_v1(p_snapshot_id); cf:=public.lf_strategy_classification_fingerprint_v1(p_snapshot_id); fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',s.snapshot_code);
 INSERT INTO public.lf_qualification_receipts(subject_type,subject_code,subject_ref,revision_sha256,classification_fingerprint,lifecycle_state_code,suite_set_fingerprint,created_by_execution_id) VALUES('STRATEGY',s.snapshot_code,format('supabase://public/lf_strategy_snapshots/%s',s.id),rev,cf,NULL,fp,p_execution_id) RETURNING qualification_id INTO qid;
 qstate:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',public.lf_lifecycle_initial_state_v1('QUALIFICATION_LIFECYCLE'),'START_QUALIFICATION'); UPDATE public.lf_qualification_receipts SET lifecycle_state_code=qstate,updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 FOR b IN SELECT * FROM public.lf_test_requirement_bindings b WHERE b.subject_type='STRATEGY' AND (b.subject_code='*' OR b.subject_code=s.snapshot_code) AND b.status='ACTIVE' AND b.required AND b.effective_from<=clock_timestamp() AND public.lf_test_requirement_applies_v1(b.binding_code,'STRATEGY',s.snapshot_code) ORDER BY b.binding_code LOOP rr:=public.lf_run_strategy_matrix_suite_v1(b.suite_code,'STRATEGY',s.snapshot_code,rev,p_execution_id); ids:=array_append(ids,(rr->>'suite_run_id')::uuid); IF rr->>'status'='FAILED' THEN any_fail:=true; ELSIF rr->>'status'='REVIEW_REQUIRED' THEN any_review:=true; END IF; END LOOP;
 UPDATE public.lf_qualification_receipts SET suite_run_ids=ids,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 IF any_fail THEN UPDATE public.lf_qualification_receipts SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',lifecycle_state_code,'FAIL_QUALIFICATION'),findings=findings||jsonb_build_array(jsonb_build_object('type','MATRIX_FAILED')),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid;
 ELSIF NOT any_review THEN UPDATE public.lf_qualification_receipts SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',lifecycle_state_code,'PASS_QUALIFICATION'),qualified_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE qualification_id=qid; END IF;
 RETURN (SELECT jsonb_build_object('qualification_id',qualification_id,'subject_code',subject_code,'revision_sha256',revision_sha256,'classification_fingerprint',classification_fingerprint,'lifecycle_state_code',lifecycle_state_code,'suite_run_ids',suite_run_ids,'suite_set_fingerprint',suite_set_fingerprint) FROM public.lf_qualification_receipts WHERE qualification_id=qid);
END $fn$;

DO $post$ DECLARE c int; BEGIN SELECT count(*) INTO c FROM public.lf_test_suite_cases WHERE suite_code='TS-STRATEGY-BASE-V1'; IF c<>12 THEN RAISE EXCEPTION 'S30_BASE_MATRIX_CASE_COUNT:%',c; END IF; END $post$;