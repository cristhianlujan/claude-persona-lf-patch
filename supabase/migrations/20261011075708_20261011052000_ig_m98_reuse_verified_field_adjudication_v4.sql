-- Source first M9.8 v4. No ledger fixture or false PASS.

CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_historical_hold_receipt_match_v4(
 p_decision jsonb,p_original_adr text,p_producer_receipt_id uuid,p_producer_head text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog' AS $matcher$
 SELECT coalesce(
 p_producer_receipt_id IS NOT NULL
 AND p_original_adr LIKE 'DEC-IG-M4.10-ADJ-%'
 AND p_producer_head ~ '^[0-9a-f]{40}$'
 AND p_decision->>'verification_state'='VERIFIED'
 AND p_decision->>'receipt_kind'='IG_SHADOW_FIELD_ADJUDICATION'
 AND p_decision->>'gate_code'='IG_SHADOW_FIELD_ADJUDICATION'
 AND p_decision->>'source_head_sha'=p_producer_head
 AND p_decision#>>'{verification_payload,provider_readback_verified}'='true'
 AND p_decision#>>'{verification_payload,digest_recomputed}'='true'
 AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,original_adr}'=p_original_adr
 AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,producer_receipt_id}'=p_producer_receipt_id::text
 AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,outcome}'='NON_BLOCKING_ACCEPTED'
 AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,level_code}' IN ('D1','D2','D3','D5')
 AND p_decision->>'subject_ref'=p_decision#>>'{receipt_payload,typed_evidence,adjudication,diff_ref}'
 AND p_decision->>'subject_sha256'=p_decision#>>'{receipt_payload,typed_evidence,adjudication,diff_sha256}'
 AND p_decision->>'authority_ref'=p_decision#>>'{receipt_payload,typed_evidence,adjudication,policy_ref}'
 AND nullif(p_decision->>'authority_ref','') IS NOT NULL
 ,false);
$matcher$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_historical_hold_receipt_match_v4(jsonb,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_historical_hold_receipt_match_v4(jsonb,text,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_gate_readback_v2(
 p_run bigint,p_screen integer,p_mutation uuid,p_divergence uuid,p_bundle text,p_field uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE b jsonb;t jsonb;hist_bundle jsonb;v_run record;hist_n integer;hist_total integer;hold_n integer;family_n integer;row_n integer;
 hist_ok boolean;scope_ok boolean;gate_states text[];v_codes text[]:=ARRAY['ZERO_ERRORS','D4_EXPLAINED_NO_HOLD','ZERO_UNRESOLVED','ZERO_FALSE_PASS','FAMILY_COVERAGE_47','M7_PASS'];
 result_controls jsonb:='[]'::jsonb;i integer;
BEGIN
 b:=programacion.fn_ig_m98_control_receipt_set_v1(p_run,p_mutation,p_divergence,p_bundle,p_field);
 t:=programacion.fn_ig_m98_candidate_field_gate_v2(p_field);
 hist_bundle:=CASE WHEN p_divergence IS NULL THEN '{}'::jsonb ELSE programacion.fn_engineering_run_test_receipt_bundle_v1(p_divergence) END;
 SELECT sum((s.value->>'oracle_divergence_count')::integer) INTO hist_n
 FROM public.lf_test_runs tr JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(ar.actual_value->'screens','[]'::jsonb)) s
 WHERE tr.suite_run_id=p_divergence AND tr.test_code='ENGINEERING_T_EQUIV_SHADOW_CORPUS'
 AND tr.status='PASS' AND ar.status='PASS' AND ar.assertion_code='ENGINEERING_T_EQUIV_SHADOW_CORPUS_ASSERT'
 AND (s.value->>'oracle_divergence_count') ~ '^[0-9]+$';
 SELECT count(*) INTO hist_total FROM transversal.decision_log dl
 WHERE dl.adr LIKE 'DEC-IG-M4.10-ADJ-%' AND dl.decision LIKE 'HOLD_BLOCK.%';
 SELECT count(*) INTO hold_n FROM transversal.decision_log dl
 WHERE dl.adr LIKE 'DEC-IG-M4.10-ADJ-%' AND dl.estado='VIGENTE' AND dl.decision LIKE 'HOLD_BLOCK.%'
 AND NOT EXISTS(
 SELECT 1 FROM private.lf_evidence_ledger_v1 v
 JOIN private.lf_evidence_ledger_v1 producer ON producer.receipt_id=p_field
 WHERE producer.verification_state='VERIFIED'
 AND producer.receipt_kind='IG_SHADOW_COMPARISON'
 AND producer.gate_code='IG_SHADOW_CANDIDATE_COMPARE'
 AND producer.verification_payload->>'comparison_scope'='PER_FIELD_CURRENT_CANDIDATE'
 AND programacion.fn_ig_m98_historical_hold_receipt_match_v4(
 to_jsonb(v),dl.adr,p_field,producer.source_head_sha)
 );
 hist_ok:=hist_bundle->>'status'='VERIFIED' AND hist_n IS NOT NULL AND hist_n>=0 AND hist_n=hist_total;
 SELECT r.pantalla_id,r.status,r.invalidated_at,r.family_count INTO v_run FROM programacion.input_readiness_runs r WHERE r.id=p_run;
 SELECT count(DISTINCT a.family_code),count(*) INTO family_n,row_n FROM programacion.input_family_assessments a WHERE a.run_id=p_run;
 scope_ok:=p_screen IS NOT NULL AND v_run.pantalla_id=p_screen AND v_run.status='COMPLETED'
 AND v_run.invalidated_at IS NULL AND programacion.fn_input_readiness_run_is_current(p_run) IS TRUE
 AND v_run.family_count=47 AND family_n=47 AND row_n=47;
 gate_states:=ARRAY[
 CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(b->'controls') x WHERE x->>'control_code'='ZERO_ERRORS' AND x->>'state'='PASS') THEN 'PASS' ELSE 'BLOCKED' END,
 CASE WHEN hist_ok AND hold_n=0 AND t->>'status'='TECHNICALLY_VERIFIED_NOT_RELEASED' THEN 'PASS' ELSE 'BLOCKED' END,
 CASE WHEN t->>'status'='TECHNICALLY_VERIFIED_NOT_RELEASED' THEN 'PASS' ELSE 'BLOCKED' END,
 CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(b->'controls') x WHERE x->>'control_code'='ZERO_FALSE_PASS' AND x->>'state'='PASS') THEN 'PASS' ELSE 'BLOCKED' END,
 CASE WHEN coalesce(scope_ok,false) THEN 'PASS' ELSE 'BLOCKED' END,
 CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(b->'controls') x WHERE x->>'control_code'='M7_PASS' AND x->>'state'='PASS') THEN 'PASS' ELSE 'BLOCKED' END
 ];
 FOR i IN 1..6 LOOP result_controls:=result_controls||jsonb_build_array(jsonb_build_object('control_code',v_codes[i],'state',gate_states[i])); END LOOP;
 RETURN jsonb_build_object('schema_version','IG_M98_GATE_READBACK_V2',
 'status',CASE WHEN array_position(gate_states,'BLOCKED') IS NULL THEN 'TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED' ELSE 'BLOCKED' END,
 'controls',result_controls,'historical_divergence_count',hist_n,'historical_record_count',hist_total,'historical_hold_decisions',hold_n,
 'historical_suite_explained',hist_ok,'historical_count_not_required_current_divergences',true,
 'family_run_screen_id',v_run.pantalla_id,'requested_screen_id',p_screen,
 'screen_binding_valid',v_run.pantalla_id=p_screen,'current_family_evidence',coalesce(scope_ok,false),
 'families_present',family_n,'assessments_present',row_n,'canonical_universe',47,
 'family_applicability_needs_request_scope',true,'candidate_field_verification',t,
 'technical_check_requires_consumer_activation',false,'release_authorized',false);
END $f$;



INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M98-REUSE-FIELD-ADJUDICATION-20261011',
'M9.8: reconciliacion via adjudicacion verificada por campo',
'Se conserva el historial HOLD y se valida su supersesion solo contra un recibo real IG_SHADOW_FIELD_ADJUDICATION enlazado al productor per-field vigente, ADR exacto, source_head, policy_ref, diff_ref y resultado NON_BLOCKING_ACCEPTED. D4 no admite excepcion. Se retira dependencia del tipo ficticio IG_SHADOW_HOLD_RESOLUTION sin emisor. Prueba positiva aislada no representa recibo registrado ni autoriza release.',
'El gate tecnico v3 dependia de tipo de recibo sin ruta de emision.',
'Correccion fail-closed del contrato M9.8, no cambia decisiones historicas ni activa consumidor.',
'VIGENTE'
WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-REUSE-FIELD-ADJUDICATION-20261011');
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,
'{m9_8_gate_contract_v2,history_hold_reconciliation,receipt_authority}',
jsonb_build_object('status','REUSE_VERIFIED_M96_FIELD_ADJUDICATION',
'schema_version','IG_M98_HOLD_RECEIPT_AUTHORITY_V4',
'kind','IG_SHADOW_FIELD_ADJUDICATION','gate','IG_SHADOW_FIELD_ADJUDICATION',
'producer_kind','IG_SHADOW_COMPARISON','no_imagined_receipt_kind',true,
'original_adr_required',true,'source_head_binding_required',true,
'no_release_authorization',true,'governance','DEC-IG-M98-REUSE-FIELD-ADJUDICATION-20261011'),true)
WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';


DO $proof$ DECLARE fixture jsonb;producer_id uuid:='11111111-2222-4333-8444-555555555555';
source_head text:=repeat('a',40);original_adr text:='DEC-IG-M4.10-ADJ-VISUAL-EVIDENCE-20261007';live jsonb;
BEGIN
fixture:=jsonb_build_object('verification_state','VERIFIED',
'receipt_kind','IG_SHADOW_FIELD_ADJUDICATION','gate_code','IG_SHADOW_FIELD_ADJUDICATION',
'source_head_sha',source_head,
'verification_payload',jsonb_build_object('provider_readback_verified',true,'digest_recomputed',true),
'subject_ref','screen:58/family:VISUAL_EVIDENCE/coverage_status',
'subject_sha256',repeat('b',64),'authority_ref','POL-IG-FIELD-01',
'receipt_payload',jsonb_build_object('typed_evidence',jsonb_build_object('adjudication',
jsonb_build_object('original_adr',original_adr,'producer_receipt_id',producer_id::text,
'outcome','NON_BLOCKING_ACCEPTED','level_code','D2',
'diff_ref','screen:58/family:VISUAL_EVIDENCE/coverage_status',
'diff_sha256',repeat('b',64),'policy_ref','POL-IG-FIELD-01'))));
IF NOT programacion.fn_ig_m98_historical_hold_receipt_match_v4(fixture,original_adr,producer_id,source_head)
THEN RAISE EXCEPTION 'POSITIVE_PURE_MATCHER_FAILED'; END IF;
IF programacion.fn_ig_m98_historical_hold_receipt_match_v4(fixture,original_adr,'00000000-0000-4000-8000-000000000001'::uuid,source_head)
THEN RAISE EXCEPTION 'WRONG_PRODUCER_PASSED'; END IF;
IF programacion.fn_ig_m98_historical_hold_receipt_match_v4(fixture,'DEC-IG-M4.10-ADJ-AUDIT-20261007',producer_id,source_head)
THEN RAISE EXCEPTION 'WRONG_ADR_PASSED'; END IF;
IF programacion.fn_ig_m98_historical_hold_receipt_match_v4(jsonb_set(fixture,'{receipt_payload,typed_evidence,adjudication,level_code}','"D4"'::jsonb),original_adr,producer_id,source_head)
THEN RAISE EXCEPTION 'D4_PASSED'; END IF;
IF programacion.fn_ig_m98_historical_hold_receipt_match_v4(jsonb_set(fixture,'{verification_state}','"ANCHORED"'::jsonb),original_adr,producer_id,source_head)
THEN RAISE EXCEPTION 'UNVERIFIED_PASSED'; END IF;
live:=programacion.fn_ig_m98_gate_readback_v2(829,58,
'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,
'7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
IF live->>'status'<>'BLOCKED' OR live#>>'{controls,1,state}'<>'BLOCKED'
OR (live->>'historical_hold_decisions')::int<>3 THEN RAISE EXCEPTION 'FALSE_LIVE_PASS';END IF;
IF NOT EXISTS(SELECT 1 FROM transversal.decision_log dl
WHERE dl.adr='DEC-IG-M98-REUSE-FIELD-ADJUDICATION-20261011')
THEN RAISE EXCEPTION 'GOVERNANCE_ABSENT';END IF;
END $proof$;