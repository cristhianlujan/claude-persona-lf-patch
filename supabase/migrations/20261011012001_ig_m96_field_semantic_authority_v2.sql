-- IG M9.6 governed repair: exact semantic authority, no M1.7 plan drift as shadow per-field authority.
-- No evidence ledger inserts, no consumer activation, no product-rule mutation.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m96_verified_field_decision_match_v1(
 p_decision jsonb,p_diff jsonb,p_producer_source_head_sha text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog'
AS $policy$
 SELECT coalesce(
   p_decision->>'verification_state'='VERIFIED'
   AND p_decision->>'gate_code'='IG_SHADOW_FIELD_ADJUDICATION'
   AND p_decision->>'receipt_kind'='IG_SHADOW_FIELD_ADJUDICATION'
   AND p_decision->>'subject_ref'=p_diff->>'diff_ref'
   AND p_decision->>'subject_sha256'=p_diff->>'diff_sha256'
   AND p_decision->>'source_head_sha'=p_producer_source_head_sha
   AND nullif(p_diff->>'policy_ref','') IS NOT NULL
   AND p_decision->>'authority_ref'=p_diff->>'policy_ref'
   AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,outcome}'='NON_BLOCKING_ACCEPTED'
   AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,level_code}'=p_diff->>'level_code'
 ,false);
$policy$;
COMMENT ON FUNCTION programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb,jsonb,text)
 IS 'Pure, testable receipt predicate. In live use receipt must be read from private governed evidence ledger; D4 and UNRESOLVED remain blocked by existing structure gate.';
REVOKE ALL ON FUNCTION programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb,jsonb,text) TO service_role;
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
   SELECT EXISTS(SELECT 1 FROM private.lf_evidence_ledger_v1 d
    WHERE d.receipt_id=v_decision_uuid
    AND programacion.fn_ig_m96_verified_field_decision_match_v1(to_jsonb(d),v_diff,r.source_head_sha)) INTO v_match;
   IF NOT v_match THEN RETURN jsonb_build_object('status','BLOCKED','reason','GOVERNED_DECISION_RECEIPT_NOT_VERIFIED','diff_ref',v_diff->>'diff_ref'); END IF;
 END LOOP;
 RETURN jsonb_build_object('status','PASS','adjudicated_count',jsonb_array_length(v_cases->'field_diffs'),
  'verified_producer_receipt_id',p_receipt_id,'source_head_sha',r.source_head_sha);
END $body$;

COMMENT ON FUNCTION programacion.fn_ig_m96_adjudication_live_gate_v1(uuid)
 IS 'M9.6 fail-closed: verified per-field producer, activated dynamic consumer policy, exact policy_ref independent VERIFIED NON_BLOCKING_ACCEPTED adjudication; M1.7 only plan/currentness.';
INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M96-FIELD-AUTHORITY-ALIGNMENT-20261010',
 'M9.6 autoridad semantica shadow por campo, separada de drift de plan',
 'M1.7 corresponde exclusivamente a PLAN_AUTHORITY/currentness; no es autoridad de divergencia semantica shadow. El gate por campo consume politica vigente ACTIVATED del INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT, policy_ref exacto por campo, recibo IG_SHADOW_FIELD_ADJUDICATION VERIFIED de autoridad independiente y resultado NON_BLOCKING_ACCEPTED con nivel concordante. M4.10 HOLD_BLOCK historicos permanecen; no se fabrica veredicto ni se autoriza cutover.',
 'La dependencia fija M1.7 en el verificador M9.6 era circular/de dominio equivocado y permitia que HOLD_BLOCK verificado equivaliera a PASS.',
 'Alineacion fail-closed de contrato y validador. No altera reglas del producto, decisiones previas, recibos, activacion del consumidor ni readiness de M9.8.',
 'VIGENTE'
WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M96-FIELD-AUTHORITY-ALIGNMENT-20261010');
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{m9_6_semantic_gate_alignment_v3}',
 jsonb_build_object('status','TECHNICAL_GATE_ONLY','plan_drift_authority','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
 'semantic_authority','CONTROL_EQUIVALENCE_JUDGE','current_consumer_policy','INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT',
 'decision_receipt_outcome','NON_BLOCKING_ACCEPTED','verified_receipt_required',true,
 'historical_m410_holds_preserved',true,'consumer_cutover','UNVERIFIED','production_authorized',false,
 'governance_decision','DEC-IG-M96-FIELD-AUTHORITY-ALIGNMENT-20261010'),true)
WHERE id=279 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.6'
AND unit_metadata#>>'{m9_6_scope_alignment_v2,runtime_obligation,status}'='UNVERIFIED';
DO $test$ DECLARE
 v_diff jsonb:=jsonb_build_object('diff_ref','ig://fixture/field','diff_sha256',repeat('a',64),'policy_ref','policy://independent/semantic/v1','level_code','D2');
 v_receipt jsonb:=jsonb_build_object('verification_state','VERIFIED','gate_code','IG_SHADOW_FIELD_ADJUDICATION',
 'receipt_kind','IG_SHADOW_FIELD_ADJUDICATION','subject_ref','ig://fixture/field','subject_sha256',repeat('a',64),
 'source_head_sha',repeat('f',40),'authority_ref','policy://independent/semantic/v1',
 'receipt_payload',jsonb_build_object('typed_evidence',jsonb_build_object('adjudication',
 jsonb_build_object('outcome','NON_BLOCKING_ACCEPTED','level_code','D2'))));
 v_probe jsonb;
BEGIN
 IF NOT programacion.fn_ig_m96_verified_field_decision_match_v1(v_receipt,v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'POSITIVE_EXACT_AUTHORITY_FAILURE'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb_set(v_receipt,'{authority_ref}','"DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001"'::jsonb),v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_M17'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb_set(v_receipt,'{receipt_payload,typed_evidence,adjudication,outcome}','"HOLD_BLOCK"'::jsonb),v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_HOLD_BLOCK'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb_set(v_receipt,'{receipt_payload,typed_evidence,adjudication,level_code}','"D5"'::jsonb),v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_LEVEL_DRIFT'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb_set(v_receipt,'{verification_state}','"ANCHORED"'::jsonb),v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_UNVERIFIED'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(jsonb_set(v_receipt,'{subject_sha256}',to_jsonb(repeat('b',64))),v_diff,repeat('f',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_DIGEST'; END IF;
 IF programacion.fn_ig_m96_verified_field_decision_match_v1(v_receipt,v_diff,repeat('e',40))
 THEN RAISE EXCEPTION 'FALSE_PASS_SOURCE_HEAD'; END IF;
 v_probe:=programacion.fn_ig_m96_adjudication_live_gate_v1('0a091836-f8db-4063-965d-a02fa2fbd6d5'::uuid);
 IF v_probe->>'reason'<>'PRODUCER_ONLY_BUNDLE_DIGEST_OR_UNVERIFIED'
 THEN RAISE EXCEPTION 'REAL_UNVERIFIED_NOT_BLOCKED:%',v_probe; END IF;
 v_probe:=programacion.fn_ig_m96_adjudication_live_gate_v1('00000000-0000-4000-8000-000000000099'::uuid);
 IF v_probe->>'reason'<>'PRODUCER_RECEIPT_MISSING'
 THEN RAISE EXCEPTION 'MISSING_PRODUCER_NOT_BLOCKED:%',v_probe; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units WHERE id=279 AND unit_metadata#>>'{m9_6_semantic_gate_alignment_v3,status}'='TECHNICAL_GATE_ONLY')
 THEN RAISE EXCEPTION 'CONTRACT_NOT_ALIGNED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M96-FIELD-AUTHORITY-ALIGNMENT-20261010'
 AND estado='VIGENTE' AND decision LIKE '%M1.7%')
 THEN RAISE EXCEPTION 'GOVERNANCE_NOT_ALIGNED'; END IF;
END $test$;
