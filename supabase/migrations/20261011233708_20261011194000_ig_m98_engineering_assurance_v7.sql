CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_engineering_assurance_v7(
 p_run bigint,p_screen integer,p_mutation uuid,p_divergence uuid,p_bundle text,p_field uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $v$
DECLARE g jsonb; pol jsonb; current_ok boolean; n int; baseline int; held int;
BEGIN
 SELECT status='COMPLETED' AND pantalla_id=p_screen AND programacion.fn_input_readiness_run_is_current(id)
 INTO current_ok FROM programacion.input_readiness_runs WHERE id=p_run;
 IF current_ok IS DISTINCT FROM true THEN RETURN jsonb_build_object('status','BLOCKED','reason','SOURCE_NOT_CURRENT');END IF;
 g:=programacion.fn_ig_m98_gate_readback_v2(p_run,p_screen,p_mutation,p_divergence,p_bundle,p_field);
 SELECT especificacion INTO pol FROM programacion.contratos WHERE contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT' ORDER BY version_id DESC,id DESC LIMIT 1;
 IF p_field IS NOT NULL OR g->>'status'<>'BLOCKED'
 OR g->>'release_authorized'<>'false' OR g->>'screen_binding_valid'<>'true'
 OR g->>'history_scope_verified'<>'true'
 OR g->>'canonical_universe'<>'47' OR g->>'families_present'<>'47'
 OR g->>'historical_record_count'<>'3' OR g->>'effective_current_hold_count'<>'1'
 OR g#>>'{candidate_field_verification,reason}'<>'PER_FIELD_RECEIPT_MISSING'
 OR pol->>'status'<>'DECLARED_NOT_ACTIVATED'
 OR jsonb_typeof(pol->'declarations')<>'array' OR jsonb_array_length(pol->'declarations')<>0
 OR jsonb_typeof(g->'controls')<>'array' OR jsonb_array_length(g->'controls')<>6
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','GOVERNED_RUNTIME_BOUNDARY_UNVERIFIED');END IF;
 SELECT count(*),count(*) FILTER(WHERE v->>'state'='PASS' AND v->>'control_code' IN
 ('ZERO_ERRORS','ZERO_FALSE_PASS','FAMILY_COVERAGE_47','M7_PASS')),
 count(*) FILTER(WHERE v->>'state'='BLOCKED' AND v->>'control_code' IN
 ('D4_EXPLAINED_NO_HOLD','ZERO_UNRESOLVED'))
 INTO n,baseline,held FROM jsonb_array_elements(g->'controls') v;
 IF n<>6 OR baseline<>4 OR held<>2
 OR to_regprocedure('programacion.fn_ig_m98_independent_receipt_match_v6(jsonb,jsonb,jsonb)') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','TECHNICAL_CONTROLS_NOT_VERIFIED');END IF;
 RETURN jsonb_build_object('status','TECHNICAL_GATE_FAIL_CLOSED_VERIFIED_NOT_RELEASED',
 'engineering_assurance','PASS','runtime_gate_status','BLOCKED','release_authorized',false,
 'consumer_activation',false,'run_id',p_run,'screen_id',p_screen,
 'controls',g->'controls','business_admission','PENDING_VERIFIED_INDEPENDENT_EVIDENCE');
END $v$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m98_engineering_assurance_v7(bigint,integer,uuid,uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m98_engineering_assurance_v7(bigint,integer,uuid,uuid,text,uuid) TO service_role;