BEGIN;

-- IG M9.6: governed per-field adjudication admission, without activating the consumer.
-- Produces no human decision and no evidence receipt. Only real, verified source receipts can PASS.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m96_adjudication_structure_v1(p_case_set jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path TO 'pg_catalog'
AS $body$
DECLARE v_diffs jsonb; v_diff jsonb; v_n int; v_i int:=0; v_level text; v_ref text; v_seen text[]:=array[]::text[];
BEGIN
 IF jsonb_typeof(p_case_set) IS DISTINCT FROM 'object'
 OR p_case_set->>'schema_version' IS DISTINCT FROM 'IG_SHADOW_FIELD_DIFF_SET_V1'
 OR nullif(btrim(coalesce(p_case_set->>'producer_receipt_ref','')),'') IS NULL
 OR coalesce(p_case_set->>'source_head_sha','') !~ '^[0-9a-f]{40}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','INVALID_TYPED_PRODUCER_ENVELOPE'); END IF;
 v_diffs:=p_case_set->'field_diffs';
 IF jsonb_typeof(v_diffs) IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_case_set->'coverage') IS DISTINCT FROM 'object'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','MISSING_FIELD_DIFF_UNIVERSE'); END IF;
 v_n:=jsonb_array_length(v_diffs);
 IF p_case_set#>>'{coverage,status}' IS DISTINCT FROM 'COMPLETE'
 OR coalesce(p_case_set#>>'{coverage,difference_count}','') !~ '^[0-9]+$'
 OR (p_case_set#>>'{coverage,difference_count}')::integer IS DISTINCT FROM v_n
 OR coalesce(p_case_set#>>'{coverage,examined_field_count}','') !~ '^[1-9][0-9]*$'
 OR (p_case_set#>>'{coverage,examined_field_count}')::integer<v_n
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','INCOMPLETE_OR_UNPROVEN_COVERAGE'); END IF;
 FOR v_diff IN SELECT value FROM jsonb_array_elements(v_diffs) LOOP
  v_i:=v_i+1;
  v_ref:=v_diff->>'diff_ref';
  IF jsonb_typeof(v_diff) IS DISTINCT FROM 'object'
  OR nullif(btrim(coalesce(v_ref,'')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'consumer_code','')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'subject_scope','')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'family_code','')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'field_path','')),'') IS NULL
  OR coalesce(v_diff->>'current_sha256','') !~ '^[0-9a-f]{64}$'
  OR coalesce(v_diff->>'candidate_sha256','') !~ '^[0-9a-f]{64}$'
  OR coalesce(v_diff->>'diff_sha256','') !~ '^[0-9a-f]{64}$'
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','DIFF_IDENTITY_OR_DIGEST_MISSING','index',v_i); END IF;
  IF v_ref=ANY(v_seen) THEN RETURN jsonb_build_object('status','BLOCKED','reason','DUPLICATE_DIFF_IDENTITY','index',v_i); END IF;
  v_seen:=array_append(v_seen,v_ref);
  v_level:=v_diff->>'level_code';
  IF v_level IS NULL OR v_level NOT IN ('D0','D1','D2','D3','D4','D5')
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','DIVERGENCE_LEVEL_UNCLASSIFIED','index',v_i); END IF;
  IF v_level='D4' THEN RETURN jsonb_build_object('status','BLOCKED','reason','D4_FALSE_PASS_RISK','index',v_i); END IF;
  IF v_level='D0' OR v_diff->>'current_sha256'=v_diff->>'candidate_sha256'
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','D0_OR_IDENTICAL_VALUE_NOT_A_DIVERGENCE','index',v_i); END IF;
  IF nullif(btrim(coalesce(v_diff->>'policy_ref','')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'mapping_ref','')),'') IS NULL
  OR nullif(btrim(coalesce(v_diff->>'decision_receipt_id','')),'') IS NULL
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','ADJUDICATION_POLICY_OR_RECEIPT_MISSING','index',v_i); END IF;
 END LOOP;
 RETURN jsonb_build_object('status','STRUCTURAL_READY_NOT_ADMITTED','diff_count',v_n,
  'requires','VERIFIED_PRODUCER_AND_PER_FIELD_AUTHORITY_RECEIPTS');
END $body$;

CREATE OR REPLACE FUNCTION programacion.fn_ig_m96_adjudication_live_gate_v1(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $body$
DECLARE r record; v_policy jsonb; v_cases jsonb; v_check jsonb; v_diff jsonb; v_decision_uuid uuid; v_match boolean;
BEGIN
 SELECT receipt_id,verification_state,verification_payload,receipt_payload,source_head_sha
 INTO r FROM private.lf_evidence_ledger_v1 WHERE receipt_id=p_receipt_id
 AND gate_code='IG_SHADOW_CANDIDATE_COMPARE' AND receipt_kind='IG_SHADOW_COMPARISON';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_RECEIPT_MISSING'); END IF;
 IF r.verification_state<>'VERIFIED'
 OR r.verification_payload->>'comparison_scope' IS DISTINCT FROM 'PER_FIELD_CURRENT_CANDIDATE'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_ONLY_BUNDLE_DIGEST_OR_UNVERIFIED'); END IF;
 v_cases:=r.receipt_payload->'typed_evidence';
 IF v_cases->>'producer_receipt_ref' IS DISTINCT FROM r.receipt_id::text
 OR v_cases->>'source_head_sha' IS DISTINCT FROM r.source_head_sha
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_IDENTITY_OR_SOURCE_MISMATCH'); END IF;
 v_check:=programacion.fn_ig_m96_adjudication_structure_v1(v_cases);
 IF v_check->>'status'<>'STRUCTURAL_READY_NOT_ADMITTED' THEN RETURN v_check; END IF;
 SELECT especificacion INTO v_policy FROM programacion.contratos
 WHERE contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT'
 ORDER BY version_id DESC,id DESC LIMIT 1;
 IF v_policy->>'status' IS DISTINCT FROM 'ACTIVATED'
 OR jsonb_typeof(v_policy->'declarations') IS DISTINCT FROM 'array'
 OR jsonb_array_length(coalesce(v_policy->'declarations','[]'::jsonb))=0
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CONSUMER_FIELD_POLICY_NOT_ACTIVATED'); END IF;
 FOR v_diff IN SELECT value FROM jsonb_array_elements(v_cases->'field_diffs') LOOP
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(v_policy->'declarations') m(value)
    WHERE m.value->>'consumer_code'=v_diff->>'consumer_code'
    AND m.value->>'subject_scope'=v_diff->>'subject_scope'
    AND m.value->>'field_path'=v_diff->>'field_path'
    AND m.value->>'level_code'=v_diff->>'level_code'
    AND m.value->>'policy_ref'=v_diff->>'policy_ref'
    AND m.value->>'mapping_ref'=v_diff->>'mapping_ref') INTO v_match;
   IF NOT v_match THEN RETURN jsonb_build_object('status','BLOCKED','reason','CURRENT_POLICY_MAPPING_MISSING','diff_ref',v_diff->>'diff_ref'); END IF;
   IF coalesce(v_diff->>'decision_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   THEN RETURN jsonb_build_object('status','BLOCKED','reason','DECISION_RECEIPT_INVALID','diff_ref',v_diff->>'diff_ref'); END IF;
   v_decision_uuid:=(v_diff->>'decision_receipt_id')::uuid;
   SELECT EXISTS(SELECT 1 FROM private.lf_evidence_ledger_v1 d WHERE d.receipt_id=v_decision_uuid
     AND d.verification_state='VERIFIED'
     AND d.gate_code='IG_SHADOW_FIELD_ADJUDICATION'
     AND d.receipt_kind='IG_SHADOW_FIELD_ADJUDICATION'
     AND d.subject_ref=v_diff->>'diff_ref'
     AND d.subject_sha256=v_diff->>'diff_sha256'
     AND d.source_head_sha=r.source_head_sha
     AND d.authority_ref LIKE '%DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001%') INTO v_match;
   IF NOT v_match THEN RETURN jsonb_build_object('status','BLOCKED','reason','GOVERNED_DECISION_RECEIPT_NOT_VERIFIED','diff_ref',v_diff->>'diff_ref'); END IF;
 END LOOP;
 RETURN jsonb_build_object('status','PASS','adjudicated_count',jsonb_array_length(v_cases->'field_diffs'),
  'verified_producer_receipt_id',p_receipt_id,'source_head_sha',r.source_head_sha);
END $body$;
COMMENT ON FUNCTION programacion.fn_ig_m96_adjudication_structure_v1(jsonb)
 IS 'Structural-only dynamic per-field D0-D5 test; never final admission. No fixed screen/family list, D4 and missing receipt fail closed.';
COMMENT ON FUNCTION programacion.fn_ig_m96_adjudication_live_gate_v1(uuid)
 IS 'Live M9.6 gate: verified per-field producer, activated current consumer policy, verified M1.7 decision receipts. Bundle digests alone are insufficient.';
REVOKE ALL ON FUNCTION programacion.fn_ig_m96_adjudication_live_gate_v1(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION programacion.fn_ig_m96_adjudication_structure_v1(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m96_adjudication_live_gate_v1(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m96_adjudication_structure_v1(jsonb) TO service_role;

UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(
   jsonb_set(unit_metadata,'{action_specs_v1,ADJUDICATE_EACH,target,declared_objects}',
    '["programacion.human_decisions","private.lf_evidence_ledger_v1","programacion.fn_ig_m96_adjudication_structure_v1","programacion.fn_ig_m96_adjudication_live_gate_v1"]'::jsonb,true),
   '{action_specs_v1,ADJUDICATE_EACH,authoring_contract,db_targets_exact}',
   '["programacion.human_decisions","private.lf_evidence_ledger_v1","programacion.engineering_plan_units","programacion.fn_ig_m96_adjudication_structure_v1","programacion.fn_ig_m96_adjudication_live_gate_v1"]'::jsonb,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.6' AND disposition='ASSIGNED';


DO $tests$
DECLARE v jsonb:=jsonb_build_object('schema_version','IG_SHADOW_FIELD_DIFF_SET_V1','producer_receipt_ref','ig://fixture','source_head_sha',repeat('e',40),
 'coverage',jsonb_build_object('status','COMPLETE','difference_count',1,'examined_field_count',2),
 'field_diffs',jsonb_build_array(jsonb_build_object('diff_ref','ig://screen/42/FIELDS/a','consumer_code','IG',
 'subject_scope','screen','family_code','FIELDS','field_path','payload.a','current_sha256',repeat('a',64),
 'candidate_sha256',repeat('b',64),'diff_sha256',repeat('c',64),'level_code','D2',
 'policy_ref','policy://v1','mapping_ref','mapping://current','decision_receipt_id','00000000-0000-4000-8000-000000000001')));
 v_n jsonb; v_g jsonb;
BEGIN
 IF programacion.fn_ig_m96_adjudication_structure_v1(v)->>'status'<>'STRUCTURAL_READY_NOT_ADMITTED' THEN RAISE EXCEPTION 'POSITIVE_CORE_FAIL'; END IF;
 v_n:=jsonb_set(v,'{field_diffs,0,level_code}','"D4"'::jsonb);
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'D4_FALSE_PASS_RISK' THEN RAISE EXCEPTION 'NEG_D4_FAIL'; END IF;
 v_n:=v-'coverage';
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'MISSING_FIELD_DIFF_UNIVERSE' THEN RAISE EXCEPTION 'NEG_COVERAGE_FAIL'; END IF;
 v_n:=jsonb_set(v,'{field_diffs,0,decision_receipt_id}','null'::jsonb);
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'ADJUDICATION_POLICY_OR_RECEIPT_MISSING' THEN RAISE EXCEPTION 'NEG_DECISION_MISSING_FAIL'; END IF;
 v_n:=jsonb_set(v,'{field_diffs,0,diff_sha256}','null'::jsonb);
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'DIFF_IDENTITY_OR_DIGEST_MISSING' THEN RAISE EXCEPTION 'NEG_DIGEST_FAIL'; END IF;
 v_n:=jsonb_set(v,'{field_diffs}',(v->'field_diffs')||(v->'field_diffs'));
 v_n:=jsonb_set(v_n,'{coverage,difference_count}','2'::jsonb);
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'DUPLICATE_DIFF_IDENTITY' THEN RAISE EXCEPTION 'NEG_DUPLICATE_FAIL'; END IF;
 v_n:=jsonb_set(v,'{coverage,examined_field_count}','0'::jsonb);
 IF programacion.fn_ig_m96_adjudication_structure_v1(v_n)->>'reason'<>'INCOMPLETE_OR_UNPROVEN_COVERAGE' THEN RAISE EXCEPTION 'NEG_BAD_UNIVERSE_FAIL'; END IF;
 v_g:=programacion.fn_ig_m96_adjudication_live_gate_v1('00000000-0000-4000-8000-000000000099');
 IF v_g->>'reason'<>'PRODUCER_RECEIPT_MISSING' THEN RAISE EXCEPTION 'NEG_LIVE_NO_PRODUCER_FAIL'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.6'
 AND unit_metadata#>'{action_specs_v1,ADJUDICATE_EACH,target,declared_objects}'
 @> '["programacion.fn_ig_m96_adjudication_live_gate_v1"]'::jsonb)
 THEN RAISE EXCEPTION 'CONTRACT_BINDING_FAIL'; END IF;
END $tests$;
COMMIT;
