DO $pre$ DECLARE v text; BEGIN SELECT max(version) INTO v FROM supabase_migrations.schema_migrations; IF v IS DISTINCT FROM '20260914064215' THEN RAISE EXCEPTION 'S30_QUAL_CONTRACT_LEDGER_DRIFT:%',v; END IF; END $pre$;

UPDATE public.lf_operation_contracts
SET allowed=(allowed-'allowed_lifecycle_states') || jsonb_build_object('lifecycle_action','UPDATE_STRATEGY','qualification_invalidation_on_material_change',true,'qualification_revision_function','public.lf_strategy_revision_sha256_v1'),
    blocked=blocked || jsonb_build_array('execute_with_stale_strategy_qualification'),
    required_after_write=required_after_write || jsonb_build_array('material_change_qualification_invalidation_readback'),
    updated_at=clock_timestamp(),updated_by_execution_id='EXEC-S30-UPDATE-STRATEGY-QUAL-HARDEN-20260914-001'
WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_contracts
SET allowed=allowed || jsonb_build_object('strategy_test_characteristics_store','public.lf_strategy_test_characteristics','strategy_initial_lifecycle_source','lf_ops.estados_catalogo:is_initial','qualification_required_before_execution',true,'qualification_matrix_base','TS-STRATEGY-BASE-V1'),
    blocked=blocked || jsonb_build_array('create_without_test_characteristic_classification_contract','execute_unqualified_strategy_revision'),
    required_after_write=required_after_write || jsonb_build_array('strategy_test_characteristics_materialized','strategy_qualification_required_before_execution'),
    updated_at=clock_timestamp(),updated_by_execution_id='EXEC-S30-CREATE-STRATEGY-QUAL-HARDEN-20260914-001'
WHERE operation_code='CREACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET output_payload=CASE WHEN output_payload ? 'test_characteristic_classification' THEN output_payload ELSE output_payload||jsonb_build_array('test_characteristic_classification','classification_fingerprint') END,
    required_evidence_keys=CASE WHEN required_evidence_keys ? 'test_characteristic_classification' THEN required_evidence_keys ELSE required_evidence_keys||jsonb_build_array('test_characteristic_classification','classification_fingerprint') END,
    pass_condition=pass_condition || jsonb_build_object('classification_store','public.lf_strategy_test_characteristics','all_active_characteristics_explicit_boolean_required',true),
    notes='Strategy type/scope and test-risk characteristics must be classified. Classification is persisted in public.lf_strategy_test_characteristics; NULL is not equivalent to false.',
    updated_at=clock_timestamp(),updated_by_execution_id='EXEC-S30-CREATE-STRATEGY-QUAL-HARDEN-20260914-001'
WHERE operation_code='CREACION_ESTRATEGIA_LF' AND step_id='strategy_classification' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_contracts
SET allowed=allowed || jsonb_build_object('strategy_qualification_required_for_new_execution',true,'strategy_qualification_currentness','EXACT_REVISION','strategy_qualification_binding_store','public.lf_test_requirement_bindings','strategy_qualification_receipt_store','public.lf_qualification_receipts'),
    blocked=blocked || jsonb_build_array('NEW_EXECUTION_WITHOUT_CURRENT_STRATEGY_QUALIFICATION'),
    updated_at=clock_timestamp(),updated_by_execution_id='EXEC-S30-EXEC-STRATEGY-QUAL-HARDEN-20260914-001'
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_test_suite_cases(suite_code,test_code,test_order,title,test_type,execution_mode,severity,input_payload,expected_output,status,created_by_execution_id)
VALUES
 ('TS-STRATEGY-OP-CREATE-V1','C10',100,'Created strategies require qualification before execution','DETERMINISTIC','AUTOMATED','CRITICAL','{"probe_code":"OP_CONTRACT_BOOL","key":"qualification_required_before_execution","expected":true}'::jsonb,'{"passed":true}'::jsonb,'CANDIDATO','EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001'),
 ('TS-STRATEGY-OP-UPDATE-V1','U11',110,'Material strategy changes invalidate qualification','DETERMINISTIC','AUTOMATED','CRITICAL','{"probe_code":"OP_CONTRACT_BOOL","key":"qualification_invalidation_on_material_change","expected":true}'::jsonb,'{"passed":true}'::jsonb,'CANDIDATO','EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001'),
 ('TS-STRATEGY-OP-EXECUTE-V1','E12',120,'New executions require exact revision qualification','DETERMINISTIC','AUTOMATED','CRITICAL','{"probe_code":"OP_CONTRACT_BOOL","key":"strategy_qualification_required_for_new_execution","expected":true}'::jsonb,'{"passed":true}'::jsonb,'CANDIDATO','EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001');

CREATE OR REPLACE FUNCTION public.lf_eval_strategy_matrix_probe_v1(p_probe jsonb,p_subject_type text,p_subject_code text,p_revision_sha256 text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE pc text:=p_probe->>'probe_code'; ok boolean:=false; actual jsonb:='{}'::jsonb; cnt int; sid bigint; def text; rp jsonb; expb boolean; actb boolean; st text;
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
 WHEN 'QUALIFICATION_BINDING_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM public.lf_test_requirement_bindings WHERE subject_type='OPERATION' AND subject_code=p_subject_code AND status IN ('PENDING','ACTIVE')) INTO ok;
 WHEN 'ROUTER_NATURAL_ACTION' THEN rp:=public.lf_router_resolve_v1(p_probe->>'request',NULL,NULL,'STRATEGY','ROUTER'); ok:=(rp->>'action_code'=p_probe->>'expected_action'); actual:=rp;
 WHEN 'FUNCTION_TABLE_DRIVEN' THEN SELECT pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) INTO def; ok:=(def IS NOT NULL AND (strpos(def,'lf_lifecycle_resolve_transition_v1')>0 OR strpos(def,'lf_lifecycle_transition_spec_v1')>0) AND lower(def) !~ 'lifecycle_state_code\s*(=|in\s*\()\s*''strategy_(planned|active|closed|superseded)''');
 WHEN 'FUNCTION_TERMINAL_HELPER' THEN SELECT pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) INTO def; ok:=(def IS NOT NULL AND strpos(def,'lf_lifecycle_state_is_terminal_v1')>0);
 WHEN 'TRIGGER_PRESENT' THEN SELECT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=p_probe->>'table_name' AND t.tgname=p_probe->>'trigger_name' AND NOT t.tgisinternal) INTO ok;
 WHEN 'OP_CONTRACT_BOOL' THEN expb:=(p_probe->>'expected')::boolean; SELECT (c.allowed->>(p_probe->>'key'))::boolean INTO actb FROM public.lf_operation_contracts c WHERE c.operation_code=p_subject_code AND c.status='ACTIVE_ENFORCEMENT' ORDER BY c.updated_at DESC LIMIT 1; ok:=(actb IS NOT DISTINCT FROM expb); actual:=jsonb_build_object('actual',actb,'expected',expb);
 WHEN 'STRATEGY_STATE_CATALOG_VALID' THEN SELECT EXISTS(SELECT 1 FROM public.lf_strategy_snapshots s JOIN lf_ops.estados_catalogo e ON e.state_code=s.lifecycle_state_code AND e.entity_type='STRATEGY_LIFECYCLE' AND e.status='VIGENTE' WHERE s.id=sid) INTO ok;
 WHEN 'STRATEGY_NOT_TERMINAL' THEN SELECT NOT public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',lifecycle_state_code) INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_REVISION_MATCH' THEN ok:=(public.lf_strategy_revision_sha256_v1(sid)=p_revision_sha256); actual:=jsonb_build_object('actual_revision',public.lf_strategy_revision_sha256_v1(sid),'expected_revision',p_revision_sha256);
 WHEN 'STRATEGY_CHARACTERISTICS_COMPLETE' THEN SELECT NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristic_catalog k WHERE k.status='ACTIVE' AND NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristics c WHERE c.snapshot_id=sid AND c.characteristic_code=k.characteristic_code AND c.enabled IS NOT NULL)) INTO ok;
 WHEN 'STRATEGY_CONDITIONAL_BINDINGS_RESOLVED' THEN SELECT NOT EXISTS(SELECT 1 FROM public.lf_strategy_test_characteristics c WHERE c.snapshot_id=sid AND c.enabled IS TRUE AND NOT EXISTS(SELECT 1 FROM public.lf_test_requirement_bindings b WHERE b.subject_type='STRATEGY' AND b.subject_code='*' AND b.characteristic_code=c.characteristic_code AND b.status IN ('PENDING','ACTIVE'))) INTO ok;
 WHEN 'EXECUTOR_OPERATIONAL' THEN SELECT lifecycle_state_code INTO st FROM public.lf_operation_registry WHERE operation_code='EJECUCION_ESTRATEGIA_LF'; ok:=(st=public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION'));
 WHEN 'STRATEGY_POLICY_FINGERPRINT_PRESENT' THEN SELECT coalesce(metadata->>'policy_set_fingerprint','')<>'' INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_UNIQUE_CODE_VERSION' THEN SELECT count(*)=1 INTO ok FROM public.lf_strategy_snapshots s JOIN public.lf_strategy_snapshots x ON x.snapshot_code=s.snapshot_code AND x.version=s.version WHERE s.id=sid;
 WHEN 'STRATEGY_START_TRANSITION_PRESENT' THEN BEGIN PERFORM public.lf_lifecycle_transition_spec_v1('STRATEGY_LIFECYCLE',(SELECT lifecycle_state_code FROM public.lf_strategy_snapshots WHERE id=sid),'START_EXECUTION'); ok:=true; EXCEPTION WHEN OTHERS THEN ok:=false; END;
 WHEN 'STRATEGY_CURRENT_VERSION' THEN SELECT id=(SELECT max(id) FROM public.lf_strategy_snapshots x WHERE x.snapshot_code=s.snapshot_code) INTO ok FROM public.lf_strategy_snapshots s WHERE s.id=sid;
 WHEN 'STRATEGY_ASSURANCE_DECLARATION' THEN SELECT jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key'))='object' INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 WHEN 'STRATEGY_ASSURANCE_EVIDENCE' THEN SELECT jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')='array' AND jsonb_array_length(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')>0 INTO ok FROM public.lf_strategy_snapshots WHERE id=sid;
 ELSE ok:=false; actual:=jsonb_build_object('error','UNKNOWN_PROBE_CODE','probe_code',pc);
 END CASE;
 RETURN jsonb_build_object('passed',coalesce(ok,false),'probe_code',pc,'actual',actual);
END $fn$;

DO $post$ DECLARE c int; BEGIN
 SELECT count(*) INTO c FROM public.lf_test_suite_cases WHERE suite_code IN ('TS-STRATEGY-OP-CREATE-V1','TS-STRATEGY-OP-UPDATE-V1','TS-STRATEGY-OP-EXECUTE-V1','TS-STRATEGY-OP-CLOSE-V1','TS-STRATEGY-BASE-V1'); IF c<>52 THEN RAISE EXCEPTION 'S30_QUAL_CORE_CASE_COUNT:%',c; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_contracts WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT' AND allowed ? 'allowed_lifecycle_states') THEN RAISE EXCEPTION 'S30_UPDATE_LITERAL_LIFECYCLE_CONTRACT_REMAINS'; END IF;
END $post$;