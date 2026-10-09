-- M7.13 checkpoint 5: repair false missing dependency M9.0 (DONE 5/5).
-- Current release qualification not asserted: M4.10 adjudicated HOLD remains BLOCKING.
-- Binds preexisting M9.0 verified as-of bundle receipt, not a new gate.
CREATE OR REPLACE FUNCTION programacion.fn_ig_release_criteria_controls_v1(p_family_run_id bigint, p_false_pass_suite_run_id uuid, p_divergence_suite_run_id uuid, p_bundle_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
DECLARE v_family_count integer:=0;v_assessment_count integer:=0;
DECLARE v_run record;v_coverage_ok boolean:=false;
DECLARE v_false_ok boolean:=false;v_divergence_ok boolean:=false;
DECLARE v_bundle_ok boolean:=false;
DECLARE v_false_bundle jsonb;v_div_bundle jsonb;
DECLARE v_oracle_divergences integer:=-1;v_adjudicated_holds integer:=0;
BEGIN
 v_bundle_ok:=coalesce(p_bundle_sha256 ~ '^[0-9a-f]{64}$',false);
 IF p_family_run_id IS NOT NULL THEN
   SELECT status,invalidated_at,family_count INTO v_run
   FROM programacion.input_readiness_runs WHERE id=p_family_run_id;
   IF FOUND THEN
     SELECT count(distinct family_code),count(*)
       INTO v_family_count,v_assessment_count
     FROM programacion.input_family_assessments WHERE run_id=p_family_run_id;
     v_coverage_ok:=v_run.status='COMPLETED' AND v_run.invalidated_at IS NULL
       AND programacion.fn_input_readiness_run_is_current(p_family_run_id) IS TRUE
       AND v_run.family_count=47 AND v_family_count=47 AND v_assessment_count=47;
   END IF;
 END IF;
 IF p_false_pass_suite_run_id IS NOT NULL THEN
   v_false_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(p_false_pass_suite_run_id);
   -- M7.7 is FUSED -> M4.9 (PAULO-063). The canonical M4.9 suite has
   -- 10 mutation cases, each storing detected + false_pass as typed booleans.
   -- A PASSED suite with even one false_pass=true is NEVER acceptable.
   SELECT (
     count(DISTINCT tr.test_code)=10
     AND count(ar.assertion_result_id)=10
     AND coalesce(bool_and(
       tr.status='PASS'
       AND ar.status='PASS'
       AND ar.actual_value->>'detected'='true'
       AND ar.actual_value->>'false_pass'='false'
     ),false)
   ) INTO v_false_ok
   FROM public.lf_test_suite_runs sr
   JOIN public.lf_test_runs tr ON tr.suite_run_id=sr.suite_run_id
   JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
   WHERE sr.suite_run_id=p_false_pass_suite_run_id
     AND sr.suite_code='INPUT_GOVERNANCE_REGRESSION'
     AND sr.status='PASSED'
     AND sr.tests_total=10 AND sr.tests_passed=10 AND sr.tests_failed=0 AND sr.tests_blocked=0
     AND sr.metadata->>'unit_code'='M4.9'
     AND sr.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
     AND tr.test_code ~ '^M4_9_T(0[1-9]|10)_'
     AND ar.assertion_code=tr.test_code||'_ASSERT'
     AND (v_false_bundle->>'status')='VERIFIED';
 END IF;
 IF p_divergence_suite_run_id IS NOT NULL THEN
   v_div_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(p_divergence_suite_run_id);
   -- Canonical T-EQUIV evidence: M4.10 is DONE; 3 shadow divergences
   -- screen=58 have exact independent HOLD_BLOCK adjudications.
   -- Explained does not imply authorized: every HOLD remains a release blocker.
   SELECT coalesce(sum(
     CASE WHEN (screen->>'oracle_divergence_count') ~ '^[0-9]+$'
       THEN (screen->>'oracle_divergence_count')::integer ELSE -100000 END
   ),-1) INTO v_oracle_divergences
   FROM public.lf_test_suite_runs sr
   JOIN public.lf_test_runs tr ON tr.suite_run_id=sr.suite_run_id
   JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
   CROSS JOIN LATERAL jsonb_array_elements(ar.actual_value->'screens') screen
   WHERE sr.suite_run_id=p_divergence_suite_run_id
     AND sr.suite_code='INPUT_GOVERNANCE_REGRESSION'
     AND sr.status='PASSED' AND sr.tests_total=1 AND sr.tests_passed=1
     AND sr.tests_failed=0 AND sr.tests_blocked=0
     AND sr.metadata->>'unit_code'='M4.10'
     AND sr.metadata->>'checkpoint_code'='SHADOW_BY_MODULE'
     AND tr.test_code='ENGINEERING_T_EQUIV_SHADOW_CORPUS'
     AND tr.status='PASS' AND ar.status='PASS'
     AND ar.assertion_code='ENGINEERING_T_EQUIV_SHADOW_CORPUS_ASSERT'
     AND (v_div_bundle->>'status')='VERIFIED';
   SELECT count(*) INTO v_adjudicated_holds
   FROM transversal.decision_log dl
   WHERE dl.adr LIKE 'DEC-IG-M4.10-ADJ-%'
     AND dl.estado='VIGENTE'
     AND dl.decision LIKE 'HOLD_BLOCK.%';
   v_divergence_ok := v_oracle_divergences=3
     AND v_adjudicated_holds=v_oracle_divergences
     AND (v_div_bundle->>'status')='VERIFIED';
 END IF;
 IF p_false_pass_suite_run_id IS NOT NULL AND p_false_pass_suite_run_id=p_divergence_suite_run_id
 THEN
   -- Two distinct obligations must be independently supported (no one-receipt shortcut).
   v_false_ok:=false;v_divergence_ok:=false;
 END IF;
 RETURN jsonb_build_object(
  'schema_version','IG_M713_QUALIFICATION_CRITERIA_V1',
  'status',CASE WHEN v_coverage_ok AND v_false_ok AND v_divergence_ok AND v_bundle_ok
          AND v_adjudicated_holds=0 THEN 'CANDIDATE_EVIDENCED' ELSE 'BLOCKED' END,
  'qualification_framework','QUALIFICATION_FRAMEWORK',
  'closure_gate','CLOSURE_GATE',
  'consumer_unit','M9.0','release_authorized',false,
  'adjudicated_holds_block_release',v_adjudicated_holds>0,
  'adjudicated_holds_count',v_adjudicated_holds,
  'evidence_as_of_only',true,
  'bundle_sha256',CASE WHEN v_bundle_ok THEN p_bundle_sha256 ELSE null END,
  'criteria',jsonb_build_object(
   'family_coverage',jsonb_build_object('state',CASE WHEN v_coverage_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'observed_families',v_family_count,'observed_assessments',v_assessment_count,'required',47,
       'run_id',p_family_run_id),
   'known_false_pass',jsonb_build_object('state',CASE WHEN v_false_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'suite_run_id',p_false_pass_suite_run_id,'required',0),
   'unexplained_divergence',jsonb_build_object('state',CASE WHEN v_divergence_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'suite_run_id',p_divergence_suite_run_id,'required',0)
  ),
  'receipts',jsonb_build_object(
    'mutation',coalesce(v_false_bundle,'{}'::jsonb),
    'divergence',coalesce(v_div_bundle,'{}'::jsonb))
 );
END
$function$
;

UPDATE programacion.engineering_plan_units u
SET unit_metadata=jsonb_set(
 jsonb_set(u.unit_metadata,
  '{source_pack_v1,checkpoint_inputs,QUAL_RECEIPT_READBACK}',
  jsonb_build_object('inputs',jsonb_build_object(
    'assets',jsonb_build_array('QUALIFICATION_FRAMEWORK','CLOSURE_GATE'),
    'events','[]'::jsonb,
    'queries',jsonb_build_array(
      'select id,head_sha,subject_sha256,receipt_sha256,payload from programacion.provenance_receipts where id=187',
      'select work_code,status from programacion.engineering_work_items where id=461',
      'select programacion.fn_ig_release_criteria_controls_v1(845, ''980a2228-24ad-4d14-a63c-e8fbb251b783''::uuid, ''7469c5cb-745b-41aa-80d0-638c32965fa9''::uuid, ''db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'')'),
    'artifacts','[]'::jsonb,
    'db_objects',jsonb_build_array('programacion.provenance_receipts',
      'programacion.fn_ig_release_criteria_controls_v1',
      'public.lf_qualification_receipts')),
    'missing','[]'::jsonb,'missing_typed','[]'::jsonb)),
 '{action_specs_v1,QUAL_RECEIPT_READBACK}',
 programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.13','QUAL_RECEIPT_READBACK')
 || jsonb_build_object(
   'status','READY',
   'expected','Read M9.0 verified as-of bundle SHA and evaluate M7.13 candidate evidence. HOLD_BLOCK is expected to deny release; publication remains M9.0.',
   'qualification_candidate_readback_contract_v1',jsonb_build_object(
     'source_unit','M9.0','source_work_id',461,'source_state','DONE',
     'receipt_table','programacion.provenance_receipts','receipt_id',187,
     'subject_type','input_governance_release_bundle',
     'subject_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
     'head_sha_asof','5a8ff982539bc5f9f102c16c1c5d4661c66e26a0',
     'qualification_receipt_not_yet_qualified',true,
     'candidate_readback_does_not_claim_release',true,
     'three_m410_adjudicated_holds_block_release',true,
     'closure_boundary','M713_BUILDER_NOT_M9_PROMOTION')))
WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M7.13';

UPDATE programacion.engineering_work_checkpoints
SET title='Readback del bundle M9.0 verificado as-of y de los tres criterios de M7.13: HOLD bloquea release sin impedir cierre del constructor',
updated_at=now(),updated_by_execution_id='IG_M713_CP5_CONTRACT_REPAIR_20261009'
WHERE work_item_id=246 AND checkpoint_code='QUAL_RECEIPT_READBACK'
 AND status IN ('PENDING','IN_PROGRESS');
