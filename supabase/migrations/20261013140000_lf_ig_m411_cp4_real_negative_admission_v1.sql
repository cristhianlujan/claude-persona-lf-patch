-- IG M4.11 CP4: test actual oracle admission, negative missing root using
-- exception-subtransaction ROLLBACK, persist genuine assertion + canonical transition.
-- Train ONLY. No live activation, no oracle rewrite, no permanent registry mutation.
-- EKB: AUD-045, IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001,
-- IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001,
-- IG-ENGINEERING-TRANSITION-EMPTY-EVIDENCE-001.
DO $m411cp4$
DECLARE
 v_u record; v_state record; v_reg record; v_meta jsonb; v_cp4 jsonb;
 v_spec jsonb; v_boot jsonb; v_after jsonb; v_live jsonb;
 v_assert jsonb; v_out jsonb; v_present boolean:=false;
 v_rejected boolean:=false; v_new_ref text; v_root text;
 v_source_hash text; v_after_hash text; v_current_ver text;
 v_evidence text; v_test_path text:=
 'supabase/migrations/20261013140000_lf_ig_m411_cp4_real_negative_admission_v1.sql';
 v_schema text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_run_id constant bigint:=213;
 v_family constant text:='APPLICABILITY_READINESS';
 v_fake_root constant text:='programacion.fn_nonexistent_oracle_for_cp4_v1(integer,text,bigint)';
BEGIN
 SELECT u.id,u.work_item_id,u.unit_metadata,w.status INTO STRICT v_u
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code=v_schema AND u.unit_code='M4.11' AND u.disposition='ASSIGNED'
 FOR UPDATE OF u,w;
 IF v_u.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,version}' IS DISTINCT FROM '3.0.0'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,cp4_negative}' IS DISTINCT FROM
 'NO_SEMANTIC_PASS_WITHOUT_ADMITTED_ORACLE'
 THEN RAISE EXCEPTION 'M411_CP4_GOVERNANCE_NOT_3_0_0'; END IF;
 SELECT c.status,c.evidence_ref INTO STRICT v_state
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id
 AND c.checkpoint_code='NO_PASS_WITHOUT_ORACLE_NEG'
 FOR UPDATE;
 IF v_state.status IS DISTINCT FROM 'PENDING' OR v_state.evidence_ref IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND checkpoint_code='DECISIONAL_BINDING_VIA_RELEASE'
 AND status='DONE' AND evidence_ref LIKE '%PASS_ENGINEERING_BOUNDARY%'
 AND evidence_ref LIKE '%decisional_oracle_authorized=false%')
 OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND sequence_no>=5
 AND (status<>'PENDING' OR evidence_ref IS NOT NULL))
 THEN RAISE EXCEPTION 'M411_CP4_CHECKPOINT_ORDER_OR_CP3_PROOF_DRIFT'; END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_schema,'M4.11');
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
 OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NO_PASS_WITHOUT_ORACLE_NEG'
 OR (v_boot#>>'{state,done_checkpoint_count}')::integer<>3
 OR (v_boot#>>'{state,checkpoint_count}')::integer<>6
 OR (v_boot#>>'{state,open_blockers}')::integer<>0
 OR (v_boot#>>'{state,unmet_deps}')::integer<>0
 THEN RAISE EXCEPTION 'M411_CP4_BOOTSTRAP_DRIFT'; END IF;

 -- Frozen historical test input: candidate 213 with APPLICABILITY_READINESS.
 SELECT r.id,r.version_id,r.status,a.family_code INTO STRICT v_reg
 FROM programacion.input_readiness_runs r
 JOIN programacion.input_family_assessments a ON a.run_id=r.id
 WHERE r.id=v_run_id AND r.version_id=19 AND r.status='COMPLETED'
 AND a.family_code=v_family;
 IF (SELECT count(*) FROM programacion.input_family_assessments
 WHERE run_id=v_run_id AND family_code=v_family)<>1
 THEN RAISE EXCEPTION 'M411_CP4_RUN_NOT_UNIQUE'; END IF;
 SELECT c.especificacion->'families'->v_family->'validator_oracle_strategy' INTO STRICT v_cp4
 FROM programacion.contratos c
 WHERE c.id=46 AND c.version_id=19 AND c.estado='defined'
 AND c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY';
 IF v_cp4->>'strategy' IS DISTINCT FROM 'SHADOW_FAMILY_POLICY_ORACLE_V2'
 OR v_cp4->>'activation_state' IS DISTINCT FROM 'DECLARED_FOR_M4_INDEPENDENT_ORACLE'
 OR v_cp4->>'current_validator_independence_claim' IS DISTINCT FROM 'false'
 OR v_cp4->>'priority_oracle_function' IS DISTINCT FROM
 'programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)'
 OR to_regprocedure(v_cp4->>'priority_oracle_function') IS NULL
 THEN RAISE EXCEPTION 'M411_CP4_ORACLE_REFERENCE_NOT_CANONICAL'; END IF;
 IF (SELECT id FROM programacion.contratos c
 WHERE c.version_id=19 AND c.estado='defined'
 AND c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
 ORDER BY id DESC LIMIT 1)<>46
 THEN RAISE EXCEPTION 'M411_CP4_CONTRACT_SELECTION_CHANGED'; END IF;
 SELECT version INTO STRICT v_current_ver FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_current_ver IS DISTINCT FROM '1.0.0'
 OR (SELECT payload->>'promotion_authorized' FROM public.lf_eventos WHERE id=20635)
 IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP4_NO_PROMOTION_CURRENTNESS_DRIFT'; END IF;

 -- Fix CP4 contract together with governance: remove nonexistent Python
 -- artifact and aggregate query proxy; material actual DB test remains compulsory.
 v_meta:=v_u.unit_metadata;
 v_cp4:=v_meta#>'{action_specs_v1,NO_PASS_WITHOUT_ORACLE_NEG}';
 IF v_cp4->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR v_cp4#>>'{assertion_contract,pass_when,adversarial_case_executed}' IS DISTINCT FROM 'true'
 OR v_cp4#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M411_CP4_PREVIOUS_TEST_CONTRACT_CHANGED'; END IF;
 v_cp4:=v_cp4||jsonb_build_object(
  'status','READY',
  'precision','M411_CP4_GOVERNED_SQL_NEGATIVE_V1',
  'action_kind','DECISION_GATE',
  'contract_family','GOVERNED_TRANSACTIONAL_ADMISSION_NEGATIVE',
  'recipe_mode','GOVERNED_SQL_NEGATIVE_AND_CANONICAL_ASSERTION_V1',
  'mutation_policy','GOVERNED_TEST_SUBTRANSACTION_ONLY',
  'requires_material_execution',true,
  'expected','Run 213 APPLICABILITY_READINESS: original admission refuses semantic PASS/promotion; forged missing oracle root fails specifically IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING; transactional rollback restores policy exactly; assertion receipt and canonical DONE only after genuine test.',
  'action_steps',jsonb_build_array(
   'PIN_EXISTING_RUN_213_AND_FAMILY_APPLICABILITY_READINESS',
   'EXECUTE_LIVE_ORACLE_ADMISSION_ON_CANONICAL_POLICY',
   'INJECT_NONEXISTENT_ORACLE_ROOT_IN_EXCEPTION_SUBTRANSACTION',
   'ASSERT_SPECIFIC_MISSING_ORACLE_REJECTION_AND_ROLLBACK',
   'ASSERT_ORIGINAL_CANONICAL_POLICY_HASH_UNCHANGED',
   'RECORD_REAL_ASSERTION_AND_TEST_EVIDENCE',
   'PERSIST_CP4_ONLY_VIA_CANONICAL_TRANSITION'
  ),
  'verification_queries',jsonb_build_array(
   'select id,version_id,status from programacion.input_readiness_runs where id=213',
   'select family_code,validator_outcome,applicability from programacion.input_family_assessments where run_id=213 and family_code=''APPLICABILITY_READINESS''',
   'select especificacion#>>''{families,APPLICABILITY_READINESS,validator_oracle_strategy,priority_oracle_function}'' from programacion.contratos where id=46'
  ),
  'test_execution_contract',jsonb_build_object(
   'mode','GOVERNED_TRANSACTIONAL_SQL_NEGATIVE_V1',
   'test_code','ENG_M4_11_NO_PASS_WITHOUT_ORACLE_NEG',
   'test_path','cristhianlujan/claude-persona-lf-patch:'||v_test_path,
   'actual_execution_required',true,
   'source','GIT_EXACT_HEAD_THROUGH_LF_MIGRATION_MERGE_TRAIN',
   'test_run_id',v_run_id,'test_family_code',v_family,
   'test_negative_case','MISSING_ORACLE_ROOT',
   'expected_exception','IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING',
   'rollback_required',true,'registry_snapshot_restored_required',true,
   'authoring_required',false,'synthetic_pass','FORBIDDEN',
   'semantic_authority','ORACLE_ADMISSION_RUNTIME_FAIL_CLOSED_V1',
   'no_production_activation',true
  ),
  'target',jsonb_build_object(
   'checkpoint','NO_PASS_WITHOUT_ORACLE_NEG',
   'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
   'declared_objects',jsonb_build_array(
    'programacion.fn_input_validator_oracle_admission_v1',
    'programacion.input_readiness_runs',
    'programacion.input_family_assessments',
    'programacion.contratos',
    'programacion.engineering_plan_units',
    'programacion.engineering_work_checkpoints',
    'programacion.fn_engineering_checkpoint_assertion_record_v1',
    'programacion.fn_engineering_checkpoint_transition_v1'),
   'declared_artifacts',jsonb_build_array(
     jsonb_build_object('path',
     'cristhianlujan/claude-persona-lf-patch:'||v_test_path,
     'role','MUTATION_TARGET','purpose','TRANSACTIONAL_SQL_TEST_AND_CP4_CLOSEOUT',
     'target_kind','EXACT_GOVERNED_MIGRATION')),
   'mutation_artifacts',jsonb_build_array(
     jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:'||v_test_path,
     'role','MUTATION_TARGET','purpose','GOVERNED_SQL_TEST_AND_CP4_CLOSEOUT',
     'target_kind','EXACT_GOVERNED_MIGRATION'))
  ),
  'handler_requirement',jsonb_build_object(
   'existing_exact_case_set_found',true,
   'exact_scenario','RUN_213_APPLICABILITY_READINESS_MISSING_ORACLE',
   'evidence_persistence','ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_AND_EVIDENCE_REF',
   'fallback_case_discovery','FORBIDDEN',
   'freeform_scenario_inference','FORBIDDEN')
 );
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NO_PASS_WITHOUT_ORACLE_NEG}',v_cp4,true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,NO_PASS_WITHOUT_ORACLE_NEG,inputs,queries}',
 v_cp4->'verification_queries',true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,NO_PASS_WITHOUT_ORACLE_NEG,inputs,db_objects}',
 v_cp4#>'{target,declared_objects}',true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,NO_PASS_WITHOUT_ORACLE_NEG,inputs,artifacts}',
 v_cp4#>'{target,declared_artifacts}',true);
 v_meta:=jsonb_set(v_meta,'{m411_admission_boundary_v1}',
 coalesce(v_meta->'m411_admission_boundary_v1','{}'::jsonb)||
 jsonb_build_object('version','3.1.0',
 'cp4_method','GOVERNED_TRANSACTIONAL_SQL_MISSING_ORACLE_NEGATIVE',
 'cp4_test_run',v_run_id,'cp4_test_family',v_family,
 'cp4_must_have_assertion_receipt',true,'cp4_rollback_no_residue',true,
 'cp4_real_admission_authority','programacion.fn_input_validator_oracle_admission_v1',
 'decisional_promotion','NOT_AUTHORIZED','production_activation','NOT_AUTHORIZED'),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_meta WHERE id=v_u.id;
 UPDATE programacion.engineering_work_items
 SET acceptance_criteria=jsonb_set(acceptance_criteria,'{2}',
 to_jsonb('CP4 real runtime negative in governed Train: historical run 213 APPLICABILITY_READINESS; oracle missing => exact missing-root rejection, exception-subtransaction rollback no residue, independent admission comparison-only, material assertion receipt and evidence required. No semantic PASS/promotion.'::text),false)
 WHERE id=v_u.work_item_id AND acceptance_criteria->>2 LIKE 'CP4 real negative%';

 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
 v_schema,'M4.11','NO_PASS_WITHOUT_ORACLE_NEG');
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
 OR v_spec->>'precision' IS DISTINCT FROM 'M411_CP4_GOVERNED_SQL_NEGATIVE_V1'
 OR v_spec->>'requires_material_execution' IS DISTINCT FROM 'true'
 OR v_spec#>>'{test_execution_contract,mode}' IS DISTINCT FROM 'GOVERNED_TRANSACTIONAL_SQL_NEGATIVE_V1'
 OR v_spec#>>'{assertion_contract,pass_when,adversarial_case_executed}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M411_CP4_CONTRACT_NOT_COMPILED'; END IF;

 -- Read original admission behaviour in real sandbox authority.
 v_live:=programacion.fn_input_validator_oracle_admission_v1(v_run_id,v_family);
 IF v_live->>'schema_version' IS DISTINCT FROM 'IG_INDEPENDENT_ORACLE_ADMISSION_V1'
 OR v_live->>'comparison_only' IS DISTINCT FROM 'true'
 OR v_live->>'semantic_pass_authorized' IS DISTINCT FROM 'false'
 OR v_live->>'promotion_authorized' IS DISTINCT FROM 'false'
 OR v_live->>'production_authorized' IS DISTINCT FROM 'false'
 OR v_live->>'independent_receipt_persisted' IS DISTINCT FROM 'false'
 OR (v_live->>'admission_status') NOT IN (
 'ADMITTED_COMPARISON_ONLY','BLOCKED_NOT_INDEPENDENT',
 'BLOCKED_VERSION_DRIFT','BLOCKED_ORACLE_NOT_IMPLEMENTED')
 THEN RAISE EXCEPTION 'M411_CP4_CURRENT_ADMISSION_CONTRADICTS_SHADOW_BOUNDARY:%',v_live; END IF;

 -- Actual adversarial scenario: temporarily change JUST this one family's
 -- oracle reference. Exception subtransaction rolls the mutation back.
 SELECT c.especificacion INTO STRICT v_reg FROM programacion.contratos c WHERE c.id=46;
 v_source_hash:=md5(v_reg.especificacion::text);
 BEGIN
  UPDATE programacion.contratos c
     SET especificacion=jsonb_set(c.especificacion,
       '{families,APPLICABILITY_READINESS,validator_oracle_strategy,priority_oracle_function}',
       to_jsonb(v_fake_root),false)
   WHERE c.id=46 AND c.version_id=19 AND c.estado='defined';
  IF NOT FOUND THEN RAISE EXCEPTION 'M411_CP4_NEGATIVE_MUTATION_NO_ROW'; END IF;
  PERFORM programacion.fn_input_validator_oracle_admission_v1(v_run_id,v_family);
  RAISE EXCEPTION 'M411_CP4_MISSING_ORACLE_FALSE_PASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING:%'
  THEN v_rejected:=true;
  ELSE RAISE; END IF;
 END;
 IF NOT v_rejected THEN RAISE EXCEPTION 'M411_CP4_MISSING_ORACLE_NOT_REJECTED'; END IF;
 SELECT md5(c.especificacion::text) INTO STRICT v_after_hash
 FROM programacion.contratos c WHERE c.id=46;
 IF v_after_hash IS DISTINCT FROM v_source_hash
 OR (SELECT c.especificacion#>>'{families,APPLICABILITY_READINESS,validator_oracle_strategy,priority_oracle_function}'
 FROM programacion.contratos c WHERE c.id=46) IS DISTINCT FROM
 'programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)'
 THEN RAISE EXCEPTION 'M411_CP4_NEGATIVE_TEST_LEFT_POLICY_RESIDUE'; END IF;

 v_evidence:='supabase://programacion.fn_input_validator_oracle_admission_v1/213/APPLICABILITY_READINESS'
 ||';test_code=ENG_M4_11_NO_PASS_WITHOUT_ORACLE_NEG'
 ||';test=GOVERNED_SQL_REAL_RUN'
 ||';original_admission_status='||(v_live->>'admission_status')
 ||';comparison_only=true'
 ||';semantic_pass_authorized=false'
 ||';negative_missing_oracle=IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING'
 ||';rollback=EXCEPTION_SUBTRANSACTION_NO_RESIDUE'
 ||';registry_id=46'
 ||';governance=v3.1.0'
 ||';decisional_promotion=false;production_activation=false';

 -- Negative material-assertion test must refuse falsified observed exit code.
 BEGIN
  PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
   v_schema,'M4.11','NO_PASS_WITHOUT_ORACLE_NEG',
   jsonb_build_object('status','PASS','evidence_ref',v_evidence,
     'observed',jsonb_build_object('test_passed',true,'test_exit_code',1,
       'semantic_authority_bound',true,'adversarial_case_executed',true)),
   'IG_M411_CP4_ASSERTION_NEGATIVE');
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%' THEN
   v_present:=true;
  ELSE RAISE; END IF;
 END;
 IF NOT v_present THEN RAISE EXCEPTION 'M411_CP4_FORGED_ASSERTION_ACCEPTED'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id
 AND checkpoint_code='NO_PASS_WITHOUT_ORACLE_NEG'
 AND assertion_receipt IS NOT NULL)
 THEN RAISE EXCEPTION 'M411_CP4_FAILED_ASSERTION_LEFT_RESIDUE'; END IF;

 -- Valid assertion depends on actual executed current + injected negative case.
 v_assert:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 v_schema,'M4.11','NO_PASS_WITHOUT_ORACLE_NEG',
 jsonb_build_object('status','PASS','evidence_ref',v_evidence,
   'observed',jsonb_build_object('test_passed',true,'test_exit_code',0,
     'semantic_authority_bound',true,'adversarial_case_executed',true,
     'run_id',v_run_id,'family_code',v_family,
     'observed_admission_status',v_live->>'admission_status',
     'negative_missing_oracle_rejected',v_rejected,
     'rollback_residue_count',0)),
 'IG_M411_CP4_TRAIN_GENUINE_ASSERTION');
 IF v_assert->>'passed' IS DISTINCT FROM 'true'
 OR v_assert->>'evidence_ref' IS DISTINCT FROM v_evidence
 THEN RAISE EXCEPTION 'M411_CP4_ASSERTION_RECORD_NOT_VERIFIED'; END IF;

 v_out:=programacion.fn_engineering_checkpoint_transition_v1(
 v_schema,'M4.11','NO_PASS_WITHOUT_ORACLE_NEG','DONE',v_evidence,
 'IG_M411_CP4_TRAIN_CANONICAL',
 'Actual run 213 and family APPLICABILITY_READINESS no semantic PASS; '
 || 'missing oracle fails specifically and policy restored by subtransaction; '
 || 'forged assertion rejected; valid receipt recorded. No promotion.');
 IF v_out#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 OR v_out#>>'{transition,checkpoint_code}' IS DISTINCT FROM 'NO_PASS_WITHOUT_ORACLE_NEG'
 THEN RAISE EXCEPTION 'M411_CP4_CANONICAL_TRANSITION_FAILED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id AND c.checkpoint_code='NO_PASS_WITHOUT_ORACLE_NEG'
 AND c.status='DONE' AND c.evidence_ref=v_evidence
 AND c.completed_at IS NOT NULL AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_receipt_sha256 IS NOT NULL)
 THEN RAISE EXCEPTION 'M411_CP4_MATERIAL_RECEIPT_POSTREADBACK_FAIL'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id AND c.sequence_no>=5 AND
 (c.status<>'PENDING' OR c.evidence_ref IS NOT NULL))
 THEN RAISE EXCEPTION 'M411_CP4_CP5_PLUS_MUTATED'; END IF;
 v_after:=programacion.fn_engineering_unit_bootstrap_v3(v_schema,'M4.11');
 IF (v_after#>>'{state,done_checkpoint_count}')::integer<>4
 OR (v_after#>>'{state,checkpoint_count}')::integer<>6
 OR v_after#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'FAMILY_COVERAGE_47'
 OR v_after#>>'{state,status}' IS DISTINCT FROM 'IN_PROGRESS'
 OR (SELECT version FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE')
 IS DISTINCT FROM v_current_ver
 THEN RAISE EXCEPTION 'M411_CP4_POST_BOOTSTRAP_OR_AUTHORITY_DRIFT'; END IF;

 INSERT INTO transversal.error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,
 severidad,lote_origen,pr,estado,evidencia,lifecycle_phase,source_ref)
 SELECT
 'IG-M411-CP4-AGGREGATE-PROXY-NO-EXECUTABLE-NEGATIVE-001',
 'CONTRATO_GOBERNANZA',
 'CP4 exigia prueba negativa ejecutable pero solo consultaba agregados y apuntaba a runner inexistente',
 'El contrato con archivo Python ausente no permitia probar rechazo de oracle ausente; consultas agregadas no testean admision.',
 'Confundir observacion historica agregada con prueba adversarial de fn_input_validator_oracle_admission_v1.',
 'Usar run y familia reales con oracle root inexistente inyectado solo en subtransaccion reversible; exigir error exacto y cero residuo; registrar asercion material genuina antes de DONE. Conservar CAPABILITY_CUTOVER separado.',
 'Run 213 APPLICABILITY_READINESS; missing oracle => IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING; rollback restored policy; forged assertion rejected; genuine assertion plus canonical transition DONE.',
 'ALTA','M4.11','PR_M411_CP4_GOVERNED_SQL_NEGATIVE',
 'VERIFICADO',v_evidence,'construction',
 'supabase/migrations/20261013140000_lf_ig_m411_cp4_real_negative_admission_v1.sql'
 WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M411-CP4-AGGREGATE-PROXY-NO-EXECUTABLE-NEGATIVE-001');
END;
$m411cp4$;
