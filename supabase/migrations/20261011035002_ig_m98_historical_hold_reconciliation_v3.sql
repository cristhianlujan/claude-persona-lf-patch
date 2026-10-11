-- Follow-up to the unapplied 20261011035001 source: historical evidence and effective holds are different authorities.
-- Two mutually exclusive counts are NOT compared when evaluating historical suite explanations.
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
 WHERE v.receipt_kind='IG_SHADOW_HOLD_RESOLUTION'
 AND v.gate_code='IG_SHADOW_HOLD_ADJUDICATION'
 AND v.verification_state='VERIFIED'
 AND p_field IS NOT NULL
 AND v.verification_payload->>'original_adr'=dl.adr
 AND v.receipt_payload#>>'{typed_evidence,original_adr}'=dl.adr
 AND v.verification_payload->>'producer_receipt_id'=p_field::text
 AND v.receipt_payload#>>'{typed_evidence,producer_receipt_id}'=p_field::text
 AND v.verification_payload->>'outcome'='NON_BLOCKING_ACCEPTED'
 AND v.receipt_payload#>>'{typed_evidence,outcome}'='NON_BLOCKING_ACCEPTED'
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

COMMENT ON FUNCTION programacion.fn_ig_m98_gate_readback_v2(bigint,integer,uuid,uuid,text,uuid)
IS 'Read-only M9.8 technical gate. Historical evidence cohort count and outstanding HOLD decisions are independent; active holds can clear only with bound VERIFIED per-field resolution receipts. No product release.';
INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M98-HISTORICAL-HOLD-SEPARATION-V3-20261010',
'M9.8: recuento historico distinto del HOLD efectivo',
'La explicacion historica verifica el total de registros historicos, no la cantidad de HOLD aun efectivos. La vigencia del bloqueo se calcula independientemente: cada HOLD conserva efecto salvo recibo verificado con original_adr, producer_receipt_id y resultado NON_BLOCKING_ACCEPTED coincidentes. Un digest y un comentario no resuelven HOLD. Se mantiene D4, cobertura de pantalla exacta, contrato tecnico sin activar consumidor y seis controles.',
'Corrige condicion circular en el readback tecnico v2, que aun comparaba historicos contra HOLD activos.',
'Version candidata de verificacion tecnica; no muta las decisiones historicas ni permite pase a produccion.',
'VIGENTE'
WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-HISTORICAL-HOLD-SEPARATION-V3-20261010');
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{m9_8_gate_contract_v2,history_hold_reconciliation}',
jsonb_build_object('status','HISTORICAL_AND_EFFECTIVE_SEPARATE',
'historical_proof','SIGNED_SUITE_HISTORY_COUPLED_TO_IMMUTABLE_ADRS',
'effective_hold_resolution','VERIFIED_PRODUCER_BOUND_FIELD_RECEIPT',
'history_is_not_current_hold_count',true,
'authority','DEC-IG-M98-HISTORICAL-HOLD-SEPARATION-V3-20261010',
'release_authorized',false),true)
WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';
DO $tests$
DECLARE d jsonb; e jsonb;BEGIN
 d:=programacion.fn_ig_m98_gate_readback_v2(845,58,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,
 '7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
 IF d->>'status'<>'BLOCKED' OR d->>'screen_binding_valid'<>'false'
 OR d->>'historical_suite_explained'<>'true'
 OR (d->>'historical_record_count')::int IS DISTINCT FROM (d->>'historical_divergence_count')::int
 OR (d->>'historical_hold_decisions')::int<1
 THEN RAISE EXCEPTION 'HISTORICAL_SEPARATION_INVALID'; END IF;
 e:=programacion.fn_ig_m98_gate_readback_v2(829,58,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,
 '7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
 IF e->>'status'<>'BLOCKED' OR e->>'current_family_evidence'<>'false'
 THEN RAISE EXCEPTION 'STALE_SOURCE_FALSE_PASS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-HISTORICAL-HOLD-SEPARATION-V3-20261010')
 THEN RAISE EXCEPTION 'GOVERNANCE_NOT_BOUND'; END IF;
END $tests$;