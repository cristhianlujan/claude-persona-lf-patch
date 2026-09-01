-- Structural regression assertions for the P0 migration.
-- Intended to run after migration application in Bootstrap/ephemeral DB.
DO $test$
DECLARE
  v_manifest text;
  v_fast text;
  v_execute text;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_input_context_manifest(bigint)'::regprocedure) INTO v_manifest;
  SELECT pg_get_functiondef('programacion.fn_input_context_manifest_known_current_v1(bigint,boolean)'::regprocedure) INTO v_fast;
  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) INTO v_execute;

  IF position('programacion.fn_input_readiness_run_is_current(p_run_id)' in v_manifest)=0 THEN
    RAISE EXCEPTION 'STRONG_MANIFEST_CURRENTNESS_GUARD_MISSING';
  END IF;
  IF position('programacion.fn_input_stage_gate_summary(p_run_id)' in v_manifest)=0 THEN
    RAISE EXCEPTION 'STRONG_MANIFEST_STAGE_GUARD_MISSING';
  END IF;
  IF position('programacion.fn_input_readiness_run_is_current(p_run_id)' in v_fast)>0 THEN
    RAISE EXCEPTION 'FAST_MANIFEST_CURRENTNESS_RECOMPUTE_PRESENT';
  END IF;
  IF position('fn_input_stage_gate_summary_known_current_v1' in v_fast)=0 THEN
    RAISE EXCEPTION 'FAST_MANIFEST_KNOWN_CURRENT_STAGE_MISSING';
  END IF;
  IF position('fn_input_readiness_run_is_current_cached_v1(r.id)' in v_execute)=0 THEN
    RAISE EXCEPTION 'EXECUTE_AUTHORITATIVE_CURRENTNESS_MISSING';
  END IF;
  IF position('v_fresh:=programacion.fn_input_freshness_delta(v_run);' in v_execute)=0 THEN
    RAISE EXCEPTION 'EXECUTE_FRESHNESS_GATE_MISSING';
  END IF;
  IF position('fn_input_context_manifest_known_current_v1' in v_execute)=0 THEN
    RAISE EXCEPTION 'EXECUTE_FAST_MANIFEST_MISSING';
  END IF;
  IF position('programacion.fn_input_context_manifest(v_run)' in v_execute)>0 THEN
    RAISE EXCEPTION 'EXECUTE_DUPLICATE_STRONG_MANIFEST_REMAINS';
  END IF;
END;
$test$;
