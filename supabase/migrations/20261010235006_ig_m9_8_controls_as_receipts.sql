-- M9.8 CONTROLS_AS_RECEIPTS: six IG-owned, typed, fail-closed control readbacks.
-- NO independent gate, NO release promotion, NO POST_PASE/SADM execution, NO forged receipts.
-- Output is derived and NOT_ANCHORED; terminal verdict persistence is a separate checkpoint.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_control_receipt_set_v1(
 p_family_run_id bigint,p_false_pass_suite_run_id uuid,p_divergence_suite_run_id uuid,
 p_bundle_sha256 text,p_adjudication_receipt_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion','public','private'
AS $body$
DECLARE v_bundle record;v_c jsonb;v_a jsonb;v_m7 boolean:=false;
 v_err boolean:=false;v_bundle_ok boolean:=false;
 v_codes text[]:=ARRAY['ZERO_ERRORS','D4_EXPLAINED_NO_HOLD','ZERO_UNRESOLVED','ZERO_FALSE_PASS','FAMILY_COVERAGE_47','M7_PASS'];
 v_states text[];v_sources text[];v_controls jsonb:='[]'::jsonb;v_i int;
BEGIN
 IF coalesce(p_bundle_sha256,'') ~ '^[0-9a-f]{64}$' THEN
  SELECT id,head_sha,receipt_sha256 INTO v_bundle
  FROM programacion.provenance_receipts
  WHERE receipt_kind='EVIDENCE_VERIFICATION'
   AND subject_type='input_governance_release_bundle'
   AND subject_sha256=p_bundle_sha256
   AND issuer_channel='EVIDENCE_VERIFIER_V1'
  ORDER BY id DESC LIMIT 1;
  v_bundle_ok:=FOUND;
 END IF;
 v_c:=programacion.fn_ig_release_criteria_controls_v1(
  p_family_run_id,p_false_pass_suite_run_id,p_divergence_suite_run_id,p_bundle_sha256);
 v_a:=CASE WHEN p_adjudication_receipt_id IS NULL
  THEN jsonb_build_object('status','BLOCKED','reason','ADJUDICATION_RECEIPT_MISSING')
  ELSE programacion.fn_ig_m96_adjudication_live_gate_v1(p_adjudication_receipt_id) END;
 SELECT w.status='DONE' INTO v_m7
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M7.13';
 SELECT count(*)=2 AND bool_and(s.status='PASSED' AND s.tests_failed=0
  AND s.tests_blocked=0 AND s.tests_total>0)
 INTO v_err FROM public.lf_test_suite_runs s
 WHERE s.suite_run_id IN (p_false_pass_suite_run_id,p_divergence_suite_run_id)
  AND p_false_pass_suite_run_id IS DISTINCT FROM p_divergence_suite_run_id;
 v_states:=ARRAY[
  -- Restricted to the two declared, verified suite receipts; not all IG errors.
  CASE WHEN v_bundle_ok AND coalesce(v_err,false)
   AND v_c#>>'{receipts,mutation,status}'='VERIFIED'
   AND v_c#>>'{receipts,divergence,status}'='VERIFIED'
   THEN 'PASS' ELSE 'BLOCKED' END,
  CASE WHEN v_bundle_ok AND v_c#>>'{criteria,unexplained_divergence,state}'='PASS'
   AND coalesce((v_c->>'adjudicated_holds_count')::int,-1)=0
   AND v_a->>'status'='PASS' THEN 'PASS' ELSE 'BLOCKED' END,
  CASE WHEN v_bundle_ok AND v_a->>'status'='PASS' THEN 'PASS' ELSE 'BLOCKED' END,
  CASE WHEN v_bundle_ok AND v_c#>>'{criteria,known_false_pass,state}'='PASS'
   THEN 'PASS' ELSE 'BLOCKED' END,
  CASE WHEN v_bundle_ok AND v_c#>>'{criteria,family_coverage,state}'='PASS'
   THEN 'PASS' ELSE 'BLOCKED' END,
  CASE WHEN v_bundle_ok AND coalesce(v_m7,false) THEN 'PASS' ELSE 'BLOCKED' END
 ];
 v_sources:=ARRAY['TWO_DECLARED_SUITE_RECEIPTS_ONLY',
  'M713_CRITERIA_AND_M96_VERIFIED_PER_FIELD_ADJUDICATION',
  'M96_VERIFIED_PER_FIELD_ADJUDICATION','M49_VERIFIED_MUTATION_SUITE',
  'CURRENT_INPUT_READINESS_47_FAMILIES','ENGINEERING_M7_13_TERMINAL_LEDGER'];
 FOR v_i IN 1..6 LOOP
  v_controls:=v_controls || jsonb_build_array(jsonb_build_object(
   'schema_version','IG_M98_CONTROL_EVIDENCE_V1',
   'control_code',v_codes[v_i],'state',v_states[v_i],
   'source_authority',v_sources[v_i],
   'scope',CASE WHEN v_i=1 THEN 'DECLARED_TWO_SUITES_ONLY' ELSE 'BOUND_CANONICAL_SOURCE' END,
   'bundle_sha256',CASE WHEN v_bundle_ok THEN p_bundle_sha256 ELSE NULL END,
   'bundle_receipt_id',CASE WHEN v_bundle_ok THEN v_bundle.id ELSE NULL END,
   'source_readback_status','DERIVED_NOT_ANCHORED',
   'release_authorized',false));
 END LOOP;
 RETURN jsonb_build_object(
  'schema_version','IG_M98_CONTROL_RECEIPT_SET_V1',
  'status',CASE WHEN array_position(v_states,'BLOCKED') IS NULL AND v_bundle_ok
   THEN 'CONTROLS_EVIDENCED_NOT_RELEASED' ELSE 'BLOCKED' END,
  'controls',v_controls,'control_count',6,'bundle_sha256',p_bundle_sha256,
  'bundle_receipt_id',CASE WHEN v_bundle_ok THEN v_bundle.id ELSE NULL END,
  'm96_adjudication',v_a,'m713_qualification_status',v_c->>'status',
  'm713_adjudicated_holds_count',v_c->'adjudicated_holds_count',
  'release_authorized',false,'own_gate_created',false,'ledger_write_performed',false);
END $body$;
COMMENT ON FUNCTION programacion.fn_ig_m98_control_receipt_set_v1(bigint,uuid,uuid,text,uuid)
 IS 'IG M9.8: reuse M7.13 / M9.6 as typed control evidence; not durable receipts or a standalone gate; no release activation.';
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_control_receipt_set_v1(bigint,uuid,uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_control_receipt_set_v1(bigint,uuid,uuid,text,uuid) TO service_role;

-- Scoped local contract repair: explicitly bind the new function and metadata.
-- No transversal contract modification: EVIDENCE_LEDGER, M7.13, M9.6 are reused unchanged.
UPDATE programacion.engineering_plan_units u
SET unit_metadata=jsonb_set(
 jsonb_set(u.unit_metadata,'{action_specs_v1,CONTROLS_AS_RECEIPTS,target,declared_objects}',
  jsonb_build_array('programacion.fn_ig_m98_control_receipt_set_v1',
   'programacion.engineering_plan_units','programacion.fn_ig_release_criteria_controls_v1',
   'programacion.fn_ig_m96_adjudication_live_gate_v1'),true),
 '{action_specs_v1,CONTROLS_AS_RECEIPTS,authoring_contract,db_targets_exact}',
 jsonb_build_array('programacion.fn_ig_m98_control_receipt_set_v1',
   'programacion.engineering_plan_units'),true)
WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.8'
  AND u.disposition='ASSIGNED';

DO $verify$
DECLARE a jsonb; b jsonb;
BEGIN
 a:=programacion.fn_ig_m98_control_receipt_set_v1(
  845,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,
  '7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
  'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
 IF a->>'control_count'<>'6' OR a->>'status'<>'BLOCKED'
  OR a#>>'{controls,3,state}'<>'PASS'
  OR a#>>'{controls,4,state}'<>'PASS'
  OR a#>>'{controls,1,state}'<>'BLOCKED'
  OR a->>'release_authorized'<>'false'
 THEN RAISE EXCEPTION 'M98_BASELINE_ASSERTION_FAILED:%',a; END IF;
 b:=programacion.fn_ig_m98_control_receipt_set_v1(
  845,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,
  '7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
  repeat('f',64),NULL);
 IF b->>'status'<>'BLOCKED' OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(b->'controls') x WHERE x->>'state'='PASS')
 THEN RAISE EXCEPTION 'M98_NEGATIVE_FALSE_PASS:%',b; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8'
  AND unit_metadata#>'{action_specs_v1,CONTROLS_AS_RECEIPTS,authoring_contract,db_targets_exact}'
   @> '["programacion.fn_ig_m98_control_receipt_set_v1"]'::jsonb)
 THEN RAISE EXCEPTION 'M98_LOCAL_CONTRACT_NOT_REBOUND'; END IF;
END $verify$;
