-- IG_CURATOR_VALIDATOR_REFACTOR_V2 M9.9 / ROLLBACK_CONDITIONS.
-- A read-only decision bound to verified provenance; NEVER a pointer switch or runtime rollback.
-- Existing governed receipt channel remains the only provenance writer.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m99_canary_rollback_decision_v1(p_signal jsonb,p_timeout_ms integer)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog','programacion'
AS $fn$
DECLARE v_reasons text[] := ARRAY[]::text[]; v_ms bigint; v_div text;
BEGIN
 IF jsonb_typeof(p_signal) IS DISTINCT FROM 'object'
 OR coalesce(p_timeout_ms,0)<=0
 OR jsonb_typeof(p_signal->'false_pass_detected') IS DISTINCT FROM 'boolean'
 OR jsonb_typeof(p_signal->'execution_error') IS DISTINCT FROM 'boolean'
 OR jsonb_typeof(p_signal->'receipt_present') IS DISTINCT FROM 'boolean'
 OR jsonb_typeof(p_signal->'receipt_verified') IS DISTINCT FROM 'boolean'
 OR coalesce(p_signal->>'divergence_level','') NOT IN ('D0','D1','D2','D3','D4','D5')
 OR coalesce(p_signal->>'elapsed_ms','') !~ '^[0-9]{1,12}$' THEN
  RETURN jsonb_build_object('schema_version','IG_CANARY_ROLLBACK_DECISION_V1',
    'action','ROLLBACK_REQUIRED','rollback_required',true,
    'reason_codes',jsonb_build_array('MALFORMED_OR_MISSING_OBSERVATION'),
    'rollback_executed',false,'release_switch_authorized',false);
 END IF;
 v_ms := (p_signal->>'elapsed_ms')::bigint; v_div := p_signal->>'divergence_level';
 IF p_signal->>'receipt_present'='false' OR p_signal->>'receipt_verified'='false' THEN
   v_reasons:=array_append(v_reasons,'RECEIPT_MISSING_OR_UNVERIFIED'); END IF;
 IF p_signal->>'false_pass_detected'='true' THEN
   v_reasons:=array_append(v_reasons,'FALSE_PASS'); END IF;
 IF v_div<>'D0' THEN v_reasons:=array_append(v_reasons,'DIVERGENCE'); END IF;
 IF v_ms>p_timeout_ms THEN v_reasons:=array_append(v_reasons,'TIMEOUT'); END IF;
 IF p_signal->>'execution_error'='true' THEN
   v_reasons:=array_append(v_reasons,'EXECUTION_ERROR'); END IF;
 RETURN jsonb_build_object('schema_version','IG_CANARY_ROLLBACK_DECISION_V1',
   'action',case when cardinality(v_reasons)>0 then 'ROLLBACK_REQUIRED' else 'CONTINUE_OBSERVATION' end,
   'rollback_required',cardinality(v_reasons)>0,'reason_codes',to_jsonb(v_reasons),
   'timeout_limit_ms',p_timeout_ms,'rollback_executed',false,
   'release_switch_authorized',false,
   'receipt_connected',p_signal->>'receipt_present'='true' and p_signal->>'receipt_verified'='true');
END $fn$;

CREATE OR REPLACE FUNCTION programacion.fn_ig_m99_canary_receipt_gate_v1(
 p_receipt_id bigint,p_expected_sha256 text,p_cohort_type_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog','programacion','public'
AS $fn$
DECLARE r programacion.provenance_receipts%rowtype; v_timeout_ms integer; v_observation jsonb;
BEGIN
 IF p_receipt_id IS NULL OR coalesce(p_expected_sha256,'') !~ '^[0-9a-f]{64}$'
 OR nullif(btrim(coalesce(p_cohort_type_code,'')),'') IS NULL THEN
   RETURN jsonb_build_object('action','ROLLBACK_REQUIRED','rollback_required',true,
      'reason_codes',jsonb_build_array('INVALID_RECEIPT_SELECTOR'),
      'rollback_executed',false,'release_switch_authorized',false); END IF;
 SELECT (unit_metadata#>>'{canary_rollback_policy_v1,timeout_limit_ms}')::integer
 INTO v_timeout_ms FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF v_timeout_ms IS NULL OR v_timeout_ms<=0 THEN
   RETURN jsonb_build_object('action','ROLLBACK_REQUIRED','rollback_required',true,
      'reason_codes',jsonb_build_array('TIMEOUT_POLICY_NOT_CURRENT'),
      'rollback_executed',false,'release_switch_authorized',false); END IF;
 SELECT * INTO r FROM programacion.provenance_receipts WHERE id=p_receipt_id;
 IF NOT FOUND
 OR r.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION'
 OR r.subject_type IS DISTINCT FROM 'IG_CANARY_OBSERVATION'
 OR r.subject_ref IS DISTINCT FROM ('IG_CANARY:'||p_cohort_type_code)
 OR r.subject_sha256 IS DISTINCT FROM p_expected_sha256
 OR r.issuer_channel IS DISTINCT FROM 'EVIDENCE_VERIFIER_V1'
 OR r.payload->>'schema_version' IS DISTINCT FROM 'IG_CANARY_OBSERVATION_V1'
 OR r.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
 OR nullif(btrim(coalesce(r.payload->>'verifier_identity','')),'') IS NULL
 OR r.payload->>'head_sha' IS DISTINCT FROM r.head_sha
 OR r.payload->>'subject_sha256' IS DISTINCT FROM p_expected_sha256
 OR r.payload->>'cohort_type_code' IS DISTINCT FROM p_cohort_type_code
 OR NOT EXISTS (
    SELECT 1 FROM programacion.input_governance_cohort_types ct
      JOIN programacion.input_governance_cohort_memberships cm USING(cohort_type_code)
    WHERE ct.cohort_type_code=p_cohort_type_code
      AND ct.status='ACTIVE' AND cm.status='ACTIVE'
      AND nullif(ct.authority_ref,'') IS NOT NULL
      AND nullif(cm.authority_ref,'') IS NOT NULL)
 THEN
   RETURN jsonb_build_object('action','ROLLBACK_REQUIRED','rollback_required',true,
      'reason_codes',jsonb_build_array('RECEIPT_MISSING_STALE_OR_UNATTESTED'),
      'rollback_executed',false,'release_switch_authorized',false); END IF;
 v_observation:=coalesce(r.payload->'observation','{}'::jsonb)
               ||jsonb_build_object('receipt_present',true,'receipt_verified',true);
 RETURN programacion.fn_ig_m99_canary_rollback_decision_v1(v_observation,v_timeout_ms)
    ||jsonb_build_object('receipt_id',r.id,'receipt_sha256',r.receipt_sha256,
      'subject_sha256',r.subject_sha256,'readback_only',true);
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('action','ROLLBACK_REQUIRED','rollback_required',true,
    'reason_codes',jsonb_build_array('RECEIPT_GATE_FAILED_CLOSED'),
    'rollback_executed',false,'release_switch_authorized',false);
END $fn$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m99_canary_rollback_decision_v1(jsonb,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION programacion.fn_ig_m99_canary_receipt_gate_v1(bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m99_canary_rollback_decision_v1(jsonb,integer) TO service_role;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m99_canary_receipt_gate_v1(bigint,text,text) TO service_role;

DO $contract$
DECLARE v_spec jsonb;
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,ROLLBACK_CONDITIONS}' INTO v_spec
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
 OR v_spec->>'action_kind' IS DISTINCT FROM 'MATERIALIZE_DECLARED_DELIVERABLE'
 THEN RAISE EXCEPTION 'M99_ROLLBACK_CONTRACT_DRIFT'; END IF;
 v_spec:=jsonb_set(v_spec,'{target,declared_assets}',
   '["INPUT_GOVERNANCE","TIMEOUT_PHASE_BUDGET_POLICY"]'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{target,declared_objects}',
   '["programacion.provenance_receipts","programacion.fn_ig_m99_canary_rollback_decision_v1","programacion.fn_ig_m99_canary_receipt_gate_v1","programacion.input_governance_cohort_memberships","programacion.input_governance_cohort_types"]'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{authoring_contract,db_targets_exact}',
   '["programacion.fn_ig_m99_canary_rollback_decision_v1","programacion.fn_ig_m99_canary_receipt_gate_v1","programacion.engineering_plan_units"]'::jsonb,true);
 v_spec:=v_spec||jsonb_build_object(
   'expected','Five reversible signals evaluated against verified provenance. No automatic switch or rollback is claimed until the independent runtime execution checkpoint is proven.',
   'checkpoint_contract_boundary','RECEIPT_DECISION_ONLY_NO_POINTER_MUTATION');
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(
   jsonb_set(
     jsonb_set(unit_metadata,'{action_specs_v1,ROLLBACK_CONDITIONS}',v_spec,true),
     '{source_pack_v1,checkpoint_inputs,ROLLBACK_CONDITIONS,inputs,db_objects}',
     '["programacion.provenance_receipts","programacion.fn_ig_m99_canary_rollback_decision_v1","programacion.fn_ig_m99_canary_receipt_gate_v1","programacion.input_governance_cohort_memberships"]'::jsonb,true),
   '{canary_rollback_policy_v1}',jsonb_build_object(
     'schema_version','IG_CANARY_ROLLBACK_POLICY_V1','timeout_limit_ms',150000,
     'source_ref','M9.9 ROLLBACK_TRIGGER_NEGATIVE >150s; TIMEOUT_PHASE_BUDGET_POLICY inventoried READ_ONLY',
     'runtime_activation',false,'switch_execution_authorized',false),true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF NOT FOUND THEN RAISE EXCEPTION 'M99_CONTRACT_UPDATE_MISSING'; END IF;
END $contract$;