-- Source-first V5 coordinated history-currentness repair; no consumer activation.
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
 unit_metadata,'{m9_8_gate_contract_v2,historical_subjects_v5}',
 jsonb_build_array(
 jsonb_build_object('adr','DEC-IG-M4.10-ADJ-AUDIT-20261007','screen_id',58,'family_code','AUDIT'),
 jsonb_build_object('adr','DEC-IG-M4.10-ADJ-RATE-LIMIT-20261007','screen_id',58,'family_code','RATE_LIMIT'),
 jsonb_build_object('adr','DEC-IG-M4.10-ADJ-VISUAL-EVIDENCE-20261007','screen_id',58,'family_code','VISUAL_EVIDENCE')
 ),true) WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';
INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
 SELECT 'DEC-IG-M98-LIVE-HISTORY-SPLIT-V5-20261011','M9.8: current unresolved HOLDs versus historical decisions',
 'Maintain all historical M4.10 HOLD ADRs immutable. Effective current HOLD count is derived from an exact typed ADR-screen-family map and current canonical M9.6 per-field observation. Missing mapping/current scope blocks. Current VISUAL_EVIDENCE remains unresolved without independent verified per-field decision. D4 always blocks and no consumer activation.',
 'Prior gate counted three historical HOLD ADRs even when AUDIT and RATE_LIMIT no longer diverged in current source.',
 'Coordinated governance and M9.8 validator readback; M9.5-9.7 DONE is capability, not producer evidence.',
 'VIGENTE' WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-LIVE-HISTORY-SPLIT-V5-20261011');
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,
 '{m9_runtime_handoff_v5}',jsonb_build_object(
 'capability_implementation','DONE',
 'live_evidence_verification','SEPARATE_GATE_REQUIRED',
 'consumer_activation',false),true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code IN ('M9.5','M9.6','M9.7');
CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_gate_readback_v2(
 p_run bigint,p_screen integer,p_mutation uuid,p_divergence uuid,p_bundle text,p_field uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE b jsonb;t jsonb;hist_bundle jsonb;hm jsonb;obs jsonb;mapping_ok boolean:=false;mapping_count integer:=0;unique_count integer:=0;v_run record;hist_n integer;hist_total integer;hold_n integer;family_n integer;row_n integer;
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

 SELECT u.unit_metadata#>'{m9_8_gate_contract_v2,historical_subjects_v5}' INTO hm
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.8';
 obs:=programacion.fn_ig_m96_shadow_field_probe_v1(p_screen,(SELECT r.version_id FROM programacion.input_readiness_runs r WHERE r.id=p_run));
 IF jsonb_typeof(hm)='array' AND jsonb_typeof(obs->'field_diffs')='array'
 AND obs->>'schema_version'='IG_M96_SHADOW_FIELD_OBSERVATION_V1'
 AND jsonb_array_length(hm)=hist_total AND hist_total>0 THEN
 SELECT count(*),count(DISTINCT h.value->>'adr') INTO mapping_count,unique_count
 FROM jsonb_array_elements(hm) h JOIN transversal.decision_log dl ON dl.adr=h.value->>'adr'
 WHERE dl.estado='VIGENTE' AND dl.decision LIKE 'HOLD_BLOCK.%'
 AND dl.decision LIKE '%screen='||(h.value->>'screen_id')||' family='||(h.value->>'family_code')||' %'
 AND h.value->>'screen_id'=p_screen::text;
 mapping_ok:=(mapping_count=hist_total AND unique_count=hist_total);
 END IF;
 IF mapping_ok THEN
 SELECT count(*) INTO hold_n FROM jsonb_array_elements(hm) h
 JOIN transversal.decision_log dl ON dl.adr=h.value->>'adr' AND dl.estado='VIGENTE'
 WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(obs->'field_diffs') d WHERE d.value->>'family_code'=h.value->>'family_code')
 AND NOT EXISTS(SELECT 1 FROM private.lf_evidence_ledger_v1 v
 JOIN private.lf_evidence_ledger_v1 producer ON producer.receipt_id=p_field
 WHERE producer.verification_state='VERIFIED' AND producer.receipt_kind='IG_SHADOW_COMPARISON'
 AND producer.gate_code='IG_SHADOW_CANDIDATE_COMPARE'
 AND producer.verification_payload->>'comparison_scope'='PER_FIELD_CURRENT_CANDIDATE'
 AND programacion.fn_ig_m98_historical_hold_receipt_match_v4(to_jsonb(v),dl.adr,p_field,producer.source_head_sha));
 ELSE hold_n:=hist_total; END IF;
  hist_ok:=hist_bundle->>'status'='VERIFIED' AND hist_n IS NOT NULL AND hist_n>=0 AND hist_n=hist_total AND mapping_ok;
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
 'historical_suite_explained',hist_ok,'history_scope_verified',mapping_ok,'effective_current_hold_count',hold_n,'current_field_diff_count',coalesce((obs->>'field_diff_count')::int,-1),'historical_count_not_required_current_divergences',true,
 'family_run_screen_id',v_run.pantalla_id,'requested_screen_id',p_screen,
 'screen_binding_valid',v_run.pantalla_id=p_screen,'current_family_evidence',coalesce(scope_ok,false),
 'families_present',family_n,'assessments_present',row_n,'canonical_universe',47,
 'family_applicability_needs_request_scope',true,'candidate_field_verification',t,
 'technical_check_requires_consumer_activation',false,'release_authorized',false);
END $f$;



