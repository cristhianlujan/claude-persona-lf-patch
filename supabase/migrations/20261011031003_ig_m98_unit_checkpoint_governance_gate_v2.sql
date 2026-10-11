-- Governed M9.8 technical contract and checkpoint. Existing run, release, history and PASE stay unchanged.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_candidate_field_gate_v2(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE r record; pol jsonb; c jsonb; d jsonb; s jsonb; ok boolean; did uuid;
BEGIN
 IF p_id IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','reason','PER_FIELD_RECEIPT_MISSING'); END IF;
 SELECT receipt_id,verification_state,verification_payload,receipt_payload,source_head_sha INTO r
 FROM private.lf_evidence_ledger_v1 WHERE receipt_id=p_id
 AND receipt_kind='IG_SHADOW_COMPARISON' AND gate_code='IG_SHADOW_CANDIDATE_COMPARE';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_RECEIPT_MISSING'); END IF;
 IF r.verification_state IS DISTINCT FROM 'VERIFIED'
 OR r.verification_payload->>'comparison_scope' IS DISTINCT FROM 'PER_FIELD_CURRENT_CANDIDATE'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_UNVERIFIED_PER_FIELD'); END IF;
 c:=r.receipt_payload->'typed_evidence';
 IF c->>'producer_receipt_ref' IS DISTINCT FROM r.receipt_id::text
 OR c->>'source_head_sha' IS DISTINCT FROM r.source_head_sha
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_BINDING_MISMATCH'); END IF;
 s:=programacion.fn_ig_m96_adjudication_structure_v1(c);
 IF s->>'status'<>'STRUCTURAL_READY_NOT_ADMITTED' THEN RETURN s; END IF;
 SELECT especificacion INTO pol FROM programacion.contratos WHERE contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT'
 ORDER BY version_id DESC,id DESC LIMIT 1;
 -- Read-only candidate qualification; not a requirement to activate the consumer.
 IF pol->>'status' IS DISTINCT FROM 'DECLARED_NOT_ACTIVATED'
 OR pol#>>'{technical_admission,status}' IS DISTINCT FROM 'VERIFIED_CANDIDATE'
 OR jsonb_typeof(pol->'declarations') IS DISTINCT FROM 'array'
 OR jsonb_array_length(coalesce(pol->'declarations','[]'::jsonb))=0
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CANDIDATE_FIELD_MAPPING_NOT_VERIFIED',
 'consumer_activation_required',false); END IF;
 FOR d IN SELECT value FROM jsonb_array_elements(c->'field_diffs') LOOP
  SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(pol->'declarations') x
  WHERE x.value->>'consumer_code'=d->>'consumer_code'
  AND x.value->>'subject_scope'=d->>'subject_scope'
  AND x.value->>'field_path'=d->>'field_path'
  AND x.value->>'level_code'=d->>'level_code'
  AND x.value->>'policy_ref'=d->>'policy_ref'
  AND x.value->>'mapping_ref'=d->>'mapping_ref') INTO ok;
  IF NOT ok THEN RETURN jsonb_build_object('status','BLOCKED','reason','FIELD_MAPPING_MISSING','diff_ref',d->>'diff_ref'); END IF;
  IF coalesce(d->>'decision_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','INVALID_DECISION_RECEIPT'); END IF;
  did:=(d->>'decision_receipt_id')::uuid;
  SELECT EXISTS(SELECT 1 FROM private.lf_evidence_ledger_v1 v WHERE v.receipt_id=did
  AND programacion.fn_ig_m96_verified_field_decision_match_v1(to_jsonb(v),d,r.source_head_sha)) INTO ok;
  IF NOT ok THEN RETURN jsonb_build_object('status','BLOCKED','reason','UNVERIFIED_FIELD_DECISION'); END IF;
 END LOOP;
 RETURN jsonb_build_object('status','TECHNICALLY_VERIFIED_NOT_RELEASED','verified_producer_receipt',p_id,'release_authorized',false);
END $f$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_candidate_field_gate_v2(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_candidate_field_gate_v2(uuid) TO service_role;

CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_gate_readback_v2(
 p_run bigint,p_screen integer,p_mutation uuid,p_divergence uuid,p_bundle text,p_field uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE b jsonb;t jsonb;hist_bundle jsonb;v_run record;hist_n integer;hold_n integer;family_n integer;row_n integer;
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
 SELECT count(*) INTO hold_n FROM transversal.decision_log dl
 WHERE dl.adr LIKE 'DEC-IG-M4.10-ADJ-%' AND dl.estado='VIGENTE' AND dl.decision LIKE 'HOLD_BLOCK.%';
 hist_ok:=hist_bundle->>'status'='VERIFIED' AND hist_n IS NOT NULL AND hist_n>=0 AND hist_n=hold_n;
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
 'controls',result_controls,'historical_divergence_count',hist_n,'historical_hold_decisions',hold_n,
 'historical_suite_explained',hist_ok,'historical_count_not_required_current_divergences',true,
 'family_run_screen_id',v_run.pantalla_id,'requested_screen_id',p_screen,
 'screen_binding_valid',v_run.pantalla_id=p_screen,'current_family_evidence',coalesce(scope_ok,false),
 'families_present',family_n,'assessments_present',row_n,'canonical_universe',47,
 'family_applicability_needs_request_scope',true,'candidate_field_verification',t,
 'technical_check_requires_consumer_activation',false,'release_authorized',false);
END $f$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_gate_readback_v2(bigint,integer,uuid,uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_gate_readback_v2(bigint,integer,uuid,uuid,text,uuid) TO service_role;

CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_checkpoint_bound_readback_v2(p_plan text,p_unit text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE j jsonb;
BEGIN
 SELECT unit_metadata#>'{m9_8_gate_contract_v2,evidence_binding}' INTO j
 FROM programacion.engineering_plan_units u WHERE u.plan_code=p_plan AND u.unit_code=p_unit;
 IF jsonb_typeof(j) IS DISTINCT FROM 'object' OR j->>'status'<>'VERIFIED_BINDING'
 OR coalesce(j->>'run_id','') !~ '^[0-9]+$' OR coalesce(j->>'screen_id','') !~ '^[0-9]+$'
 OR coalesce(j->>'mutation_suite_id','') !~ '^[0-9a-f-]{36}$'
 OR coalesce(j->>'divergence_suite_id','') !~ '^[0-9a-f-]{36}$'
 OR coalesce(j->>'bundle_sha','') !~ '^[0-9a-f]{64}$'
 OR coalesce(j->>'field_receipt_id','') !~ '^[0-9a-f-]{36}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','GOVERNED_EVIDENCE_BINDING_MISSING'); END IF;
 BEGIN
 RETURN programacion.fn_ig_m98_gate_readback_v2(
 (j->>'run_id')::bigint,(j->>'screen_id')::int,(j->>'mutation_suite_id')::uuid,
 (j->>'divergence_suite_id')::uuid,j->>'bundle_sha',(j->>'field_receipt_id')::uuid);
 EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RETURN jsonb_build_object('status','BLOCKED','reason','INVALID_BOUND_EVIDENCE_IDENTITIES');
 END;
END $f$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_checkpoint_bound_readback_v2(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_checkpoint_bound_readback_v2(text,text) TO service_role;

INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M98-TECHNICAL-CHECKPOINT-CONTRACT-V2-20261010',
'M9.8: corregir contrato tecnico, checkpoint y gobernanza',
'Se separa verificacion tecnica de activacion del consumidor. Las divergencias historicas son cohorte probada, no cuota fija de diferencias actuales. Tres HOLD historicos se conservan y siguen bloqueando hasta reconciliacion exacta verificada. El checkpoint exige seis controles anclados a mismo contexto, pantalla y fuente actual, sin inferir aplicabilidad de las 47 familias por defecto; no hay PASS por solo digest.',
'Contradiccion entre exigir tres HOLD y exigir cero; lectura de familia ajena a pantalla objetivo; dependencia circular de activar D0-D5 para validar candidato.',
'Unicamente M9.8 y nuevo readback tecnico, no alteracion de oraculo original, gobernanza historica ni release.',
'VIGENTE' WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-TECHNICAL-CHECKPOINT-CONTRACT-V2-20261010');
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
 unit_metadata,'{m9_8_gate_contract_v2}',jsonb_build_object(
 'status','TECHNICAL_NOT_RELEASED','schema_version','IG_M98_UNIT_GATE_V2',
 'entrypoint','programacion.fn_ig_m98_checkpoint_bound_readback_v2',
 'evidence_binding',NULL,'historical_count','FROM_VERIFIED_COHORT_NOT_FIXED',
 'effective_holds','REQUIRE_VERIFIED_RECONCILIATION','candidate_field_policy','VERIFY_BEFORE_ACTIVATION',
 'family_scope','POSITIVE_DYNAMIC_APPLICABILITY','canonical_universe',47,
 'checkpoint','GATE_VERDICT_READBACK','false_pass_policy','FAIL_CLOSED',
 'technical_positive_state','TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED',
 'release_authorized',false,'governance_ref','DEC-IG-M98-TECHNICAL-CHECKPOINT-CONTRACT-V2-20261010'),true)
 WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';
UPDATE programacion.engineering_work_checkpoints
 SET title='Readback tecnico de los seis controles y recibos vigentes, sin activar al consumidor'
 WHERE work_item_id=469 AND checkpoint_code='GATE_VERDICT_READBACK' AND status='IN_PROGRESS';
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,
 '{source_pack_v1,checkpoint_inputs,GATE_VERDICT_READBACK,inputs,queries}',
 jsonb_build_array(
 'select programacion.fn_ig_m98_checkpoint_bound_readback_v2(''IG_CURATOR_VALIDATOR_REFACTOR_V2'',''M9.8'') as technical_gate',
 'select checkpoint_code,status,evidence_ref from programacion.engineering_work_checkpoints where work_item_id=469 and checkpoint_code=''GATE_VERDICT_READBACK'''),true)
WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';
DO $verify$ DECLARE a jsonb;b jsonb;c jsonb;BEGIN
 a:=programacion.fn_ig_m98_gate_readback_v2(845,58,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,'7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
 IF a->>'status'<>'BLOCKED' OR a->>'screen_binding_valid'<>'false'
 OR a#>>'{controls,4,state}'<>'BLOCKED' OR a->>'historical_suite_explained'<>'true'
 THEN RAISE EXCEPTION 'CROSS_SCREEN_FALSE_PASS'; END IF;
 b:=programacion.fn_ig_m98_gate_readback_v2(829,58,'980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid,'7469c5cb-745b-41aa-80d0-638c32965fa9'::uuid,
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',NULL);
 IF b->>'screen_binding_valid'<>'true' OR b->>'current_family_evidence'<>'false'
 OR b->>'status'<>'BLOCKED' THEN RAISE EXCEPTION 'STALE_SOURCE_FALSE_PASS'; END IF;
 c:=programacion.fn_ig_m98_candidate_field_gate_v2('0a091836-f8db-4063-965d-a02fa2fbd6d5'::uuid);
 IF c->>'reason'<>'PRODUCER_UNVERIFIED_PER_FIELD' THEN RAISE EXCEPTION 'UNVERIFIED_PRODUCER_ADMITTED'; END IF;
 c:=programacion.fn_ig_m98_checkpoint_bound_readback_v2('IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.8');
 IF c->>'reason'<>'GOVERNED_EVIDENCE_BINDING_MISSING' THEN RAISE EXCEPTION 'MISSING_BINDING_ADMITTED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-TECHNICAL-CHECKPOINT-CONTRACT-V2-20261010' AND estado='VIGENTE')
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints WHERE work_item_id=469
 AND checkpoint_code='GATE_VERDICT_READBACK' AND status='IN_PROGRESS')
 THEN RAISE EXCEPTION 'CONTRACT_GOVERNANCE_CHECKPOINT_UNBOUND'; END IF;
END $verify$;