-- P0 performance hardening: reuse authoritative currentness inside one governed execution request.
--
-- Safety invariant (ARC-015): this does NOT remove evaluator/classifier semantic currentness.
-- programacion.fn_input_governance_execute still resolves a current run through
-- fn_input_readiness_run_is_current_cached_v1 and then checks fn_input_freshness_delta
-- before any known-current fastpath is used.
--
-- The new manifest helper is internal-only: PUBLIC/anon/authenticated/service_role
-- cannot invoke it directly. The SECURITY DEFINER owner of fn_input_governance_execute
-- can call it after currentness was proven earlier in the same statement snapshot.

DO $migration$
DECLARE
  v_manifest_def text;
  v_manifest_sha text;
  v_fast_def text;
  v_execute_def text;
  v_execute_sha text;
  v_verify text;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_input_context_manifest(bigint)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_context_manifest(bigint)'::regprocedure),'sha256'),'hex')
    INTO v_manifest_def,v_manifest_sha;

  IF v_manifest_sha <> '3163c77328166aa29fc81ecaafc58abcdb21a290371997bad2767e13187234fa' THEN
    RAISE EXCEPTION 'INPUT_CONTEXT_MANIFEST_BASELINE_SHA_MISMATCH:%',v_manifest_sha;
  END IF;

  IF position('fn_input_context_manifest(p_run_id bigint)' in v_manifest_def)=0 THEN
    RAISE EXCEPTION 'INPUT_CONTEXT_MANIFEST_SIGNATURE_ANCHOR_MISSING';
  END IF;
  IF (length(v_manifest_def)-length(replace(v_manifest_def,'programacion.fn_input_readiness_run_is_current(p_run_id)','')))/length('programacion.fn_input_readiness_run_is_current(p_run_id)') <> 1 THEN
    RAISE EXCEPTION 'INPUT_CONTEXT_MANIFEST_CURRENTNESS_CALL_COUNT_MISMATCH';
  END IF;
  IF (length(v_manifest_def)-length(replace(v_manifest_def,'programacion.fn_input_stage_gate_summary(p_run_id)','')))/length('programacion.fn_input_stage_gate_summary(p_run_id)') <> 1 THEN
    RAISE EXCEPTION 'INPUT_CONTEXT_MANIFEST_STAGE_CALL_COUNT_MISMATCH';
  END IF;

  v_fast_def := replace(
    v_manifest_def,
    'fn_input_context_manifest(p_run_id bigint)',
    'fn_input_context_manifest_known_current_v1(p_run_id bigint, p_run_current boolean)'
  );
  v_fast_def := replace(
    v_fast_def,
    'programacion.fn_input_readiness_run_is_current(p_run_id)',
    'p_run_current'
  );
  v_fast_def := replace(
    v_fast_def,
    'programacion.fn_input_stage_gate_summary(p_run_id)',
    'programacion.fn_input_stage_gate_summary_known_current_v1(p_run_id,true)'
  );
  EXECUTE v_fast_def;

  EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_context_manifest_known_current_v1(bigint,boolean) FROM PUBLIC';
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_context_manifest_known_current_v1(bigint,boolean) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_context_manifest_known_current_v1(bigint,boolean) FROM authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_context_manifest_known_current_v1(bigint,boolean) FROM service_role';
  END IF;

  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'sha256'),'hex')
    INTO v_execute_def,v_execute_sha;

  IF v_execute_sha <> '94b700b766d88e67f9754f66f85634a3fafd00727ae81e9ec6836fd1ebc542f2' THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_BASELINE_SHA_MISMATCH:%',v_execute_sha;
  END IF;
  IF (length(v_execute_def)-length(replace(v_execute_def,'programacion.fn_input_context_manifest(v_run)','')))/length('programacion.fn_input_context_manifest(v_run)') <> 1 THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_MANIFEST_CALL_COUNT_MISMATCH';
  END IF;
  IF (length(v_execute_def)-length(replace(v_execute_def,'programacion.fn_input_readiness_run_is_current_cached_v1(r.id)','')))/length('programacion.fn_input_readiness_run_is_current_cached_v1(r.id)') <> 1 THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_AUTHORITATIVE_CURRENTNESS_MISSING';
  END IF;
  IF position('v_fresh:=programacion.fn_input_freshness_delta(v_run);' in v_execute_def)=0 THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_FRESHNESS_GATE_MISSING';
  END IF;

  v_execute_def := replace(
    v_execute_def,
    'programacion.fn_input_context_manifest(v_run)',
    'programacion.fn_input_context_manifest_known_current_v1(v_run,true)'
  );
  EXECUTE v_execute_def;

  IF encode(digest(pg_get_functiondef('programacion.fn_input_context_manifest(bigint)'::regprocedure),'sha256'),'hex')
       <> '3163c77328166aa29fc81ecaafc58abcdb21a290371997bad2767e13187234fa' THEN
    RAISE EXCEPTION 'INPUT_CONTEXT_MANIFEST_STRONG_ENTRYPOINT_CHANGED';
  END IF;

  SELECT pg_get_functiondef('programacion.fn_input_context_manifest_known_current_v1(bigint,boolean)'::regprocedure)
    INTO v_verify;
  IF position('programacion.fn_input_readiness_run_is_current(p_run_id)' in v_verify)>0 THEN
    RAISE EXCEPTION 'KNOWN_CURRENT_MANIFEST_RECOMPUTES_CURRENTNESS';
  END IF;
  IF position('programacion.fn_input_stage_gate_summary(p_run_id)' in v_verify)>0 THEN
    RAISE EXCEPTION 'KNOWN_CURRENT_MANIFEST_RECOMPUTES_STAGE_CURRENTNESS';
  END IF;
  IF position('programacion.fn_input_stage_gate_summary_known_current_v1(p_run_id, true)' in v_verify)=0
     AND position('programacion.fn_input_stage_gate_summary_known_current_v1(p_run_id,true)' in v_verify)=0 THEN
    RAISE EXCEPTION 'KNOWN_CURRENT_MANIFEST_STAGE_FASTPATH_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) a
    WHERE p.oid='programacion.fn_input_context_manifest_known_current_v1(bigint,boolean)'::regprocedure
      AND a.grantee=0
      AND a.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'KNOWN_CURRENT_MANIFEST_PUBLIC_EXECUTE_NOT_REVOKED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
     AND has_function_privilege('service_role','programacion.fn_input_context_manifest_known_current_v1(bigint,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'KNOWN_CURRENT_MANIFEST_SERVICE_ROLE_EXECUTE_NOT_REVOKED';
  END IF;

  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    INTO v_verify;
  IF (length(v_verify)-length(replace(v_verify,'programacion.fn_input_context_manifest_known_current_v1(v_run, true)','')))/length('programacion.fn_input_context_manifest_known_current_v1(v_run, true)') <> 1
     AND (length(v_verify)-length(replace(v_verify,'programacion.fn_input_context_manifest_known_current_v1(v_run,true)','')))/length('programacion.fn_input_context_manifest_known_current_v1(v_run,true)') <> 1 THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_KNOWN_CURRENT_MANIFEST_PATCH_MISSING';
  END IF;
  IF position('programacion.fn_input_context_manifest(v_run)' in v_verify)>0 THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_STRONG_MANIFEST_DUPLICATE_REMAINS';
  END IF;
END;
$migration$;

COMMENT ON FUNCTION programacion.fn_input_context_manifest_known_current_v1(bigint,boolean) IS
  'Internal request-scoped manifest fastpath. Caller must have proven currentness earlier in the same governed statement snapshot. Not externally executable; ARC-015 strong currentness remains at fn_input_governance_execute entry.';
