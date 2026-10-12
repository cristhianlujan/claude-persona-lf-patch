-- IG M9.9: one integrated sandbox-only six-case transaction.
-- Reuses governed pointer promoter + live DB candidate readback + M9.9 gates.
-- This is NOT a certified canary: timeout is a historical observation,
-- false-PASS producer is an adversarial fixture, and independent review/
-- durable provenance must be supplied by their separate governed operations.
BEGIN;
CREATE TEMP TABLE ig_m99_integrated_probe_v1 (
 case_code text, observed_cause text, decision text,
 actual_abort boolean, restored_exactly boolean, version_residue int,
 proof_ceiling text
) ON COMMIT DROP;
DO $probe$
DECLARE
 b record; a record; v_case text; m jsonb; candidate_sha text;
 promotion jsonb; decision jsonb; oracle_status text;
 v_fault boolean; v_div text; v_exec_error boolean; v_missing boolean;
 v_elapsed bigint; v_timeout bigint; v_trigger boolean;
 v_count int; v_receipts bigint; missing_gate jsonb;
BEGIN
 SELECT version,manifest_sha256,previous_version INTO STRICT b
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 IF b.version IS DISTINCT FROM '1.0.0' OR b.previous_version IS NOT NULL
 THEN RAISE EXCEPTION 'M99_BASELINE_NOT_FROZEN'; END IF;
 SELECT count(*) INTO v_count FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_count<>1 THEN RAISE EXCEPTION 'M99_BASELINE_REGISTRY_DRIFT'; END IF;
 SELECT count(*) INTO v_receipts FROM programacion.provenance_receipts;
 SELECT (unit_metadata#>>'{canary_rollback_policy_v1,timeout_limit_ms}')::bigint
 INTO v_timeout FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF v_timeout IS NULL OR v_timeout<=0 THEN RAISE EXCEPTION 'M99_TIMEOUT_POLICY_INVALID'; END IF;
 FOR v_case IN SELECT unnest(ARRAY[
   'CLEAN','FALSE_PASS','DIVERGENCE','TIMEOUT','EXECUTION_ERROR','MISSING_RECEIPT'])
 LOOP
  v_fault:=false; v_div:='D0'; v_exec_error:=false;
  v_missing:=false; v_elapsed:=1000; v_trigger:=false;
  decision:=null;
  BEGIN
   SELECT manifest||jsonb_build_object('version','1.0.1','migration',
    manifest->'migration'||jsonb_build_object('sandbox_canary',true))
   INTO STRICT m FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   IF v_case='FALSE_PASS' THEN
     m:=jsonb_set(m,'{migration,semantic_fault}','"FORBIDDEN_FALSE_PASS"'::jsonb,true);
   ELSIF v_case='DIVERGENCE' THEN
     m:=jsonb_set(m,'{migration,divergence_marker}','"D3"'::jsonb,true);
   END IF;
   candidate_sha:=encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',m,candidate_sha,
   source_ref,docs_ref,validator_ref,'IG_M99_INTEGRATED_SANDBOX_PROBE'
   FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   promotion:=public.fn_lf_capability_promote_v1(
    'INPUT_GOVERNANCE','1.0.1',b.manifest_sha256,
    'IG_M99_INTEGRATED_SANDBOX_PROBE','rollback-only');
   IF promotion->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT'
   THEN RAISE EXCEPTION 'M99_CANDIDATE_NOT_PROMOTED'; END IF;
   SELECT CASE WHEN vr.manifest#>>'{migration,semantic_fault}' IS NULL
      THEN 'PASS' ELSE 'FAIL' END,
      coalesce(vr.manifest#>>'{migration,divergence_marker}','D0')
   INTO oracle_status,v_div
   FROM public.lf_capability_current cur
   JOIN public.lf_capability_version_registry vr
    ON cur.capability_code=vr.capability_code AND cur.version=vr.version
   WHERE cur.capability_code='INPUT_GOVERNANCE'
     AND cur.manifest_sha256=candidate_sha;
   IF oracle_status IS NULL THEN RAISE EXCEPTION 'M99_ORACLE_READBACK_MISSING'; END IF;
   v_fault:=(oracle_status='FAIL' AND v_case='FALSE_PASS');
   IF v_case='EXECUTION_ERROR' THEN
    BEGIN
     PERFORM 1/0;
    EXCEPTION WHEN division_by_zero THEN v_exec_error:=true;
    END;
    IF v_exec_error IS NOT TRUE THEN RAISE EXCEPTION 'M99_REAL_ERROR_NOT_OBSERVED'; END IF;
   END IF;
   IF v_case='TIMEOUT' THEN
    SELECT max(extract(epoch from (validator_completed_at-created_at))*1000)::bigint
    INTO v_elapsed FROM programacion.input_readiness_runs
    WHERE validator_completed_at IS NOT NULL
      AND validator_completed_at>created_at
      AND validator_completed_at-created_at>make_interval(secs=>v_timeout/1000.0);
    IF v_elapsed IS NULL OR v_elapsed<=v_timeout
    THEN RAISE EXCEPTION 'M99_HISTORICAL_TIMEOUT_PROOF_MISSING'; END IF;
   END IF;
   IF v_case='MISSING_RECEIPT' THEN
    missing_gate:=programacion.fn_ig_m99_canary_receipt_gate_v1(
       9223372036854770000,b.manifest_sha256,'AUTH');
    v_missing:= (missing_gate->>'action'='ROLLBACK_REQUIRED'
      AND (missing_gate->'reason_codes' ? 'RECEIPT_MISSING_STALE_OR_UNATTESTED'));
    IF NOT v_missing THEN RAISE EXCEPTION 'M99_MISSING_RECEIPT_GATE_NOT_OBSERVED'; END IF;
   END IF;
   decision:=programacion.fn_ig_m99_canary_rollback_decision_v1(
     jsonb_build_object('false_pass_detected',v_fault,'divergence_level',v_div,
     'elapsed_ms',v_elapsed,'execution_error',v_exec_error,
     'receipt_present',NOT v_missing,'receipt_verified',NOT v_missing),
     v_timeout::integer);
   IF v_case='CLEAN' THEN
     IF decision->>'action'<>'CONTINUE_OBSERVATION'
     THEN RAISE EXCEPTION 'M99_CLEAN_FALSE_NEGATIVE'; END IF;
   ELSE
     IF decision->>'action'<>'ROLLBACK_REQUIRED'
     OR NOT(decision->'reason_codes' ? CASE v_case
       WHEN 'MISSING_RECEIPT' THEN 'RECEIPT_MISSING_OR_UNVERIFIED'
       ELSE v_case END)
     THEN RAISE EXCEPTION 'M99_NEGATIVE_DECISION_MISMATCH:%',v_case; END IF;
     v_trigger:=true;
   END IF;
   -- Actual candidate pointer is reverted by this exception subtransaction.
   -- Clean case also reverts to preserve sandbox-only scope.
   RAISE EXCEPTION USING ERRCODE='ZX099',MESSAGE='M99_AUTOMATIC_SAVEPOINT_ABORT';
  EXCEPTION WHEN SQLSTATE 'ZX099' THEN
   IF decision IS NULL THEN RAISE EXCEPTION 'M99_ABORT_WITHOUT_DECISION'; END IF;
  END;
  SELECT version,manifest_sha256,previous_version INTO STRICT a
  FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
  SELECT count(*) INTO v_count FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1';
  IF a.version IS DISTINCT FROM b.version OR
     a.manifest_sha256 IS DISTINCT FROM b.manifest_sha256 OR
     a.previous_version IS DISTINCT FROM b.previous_version OR
     v_count<>0 OR
     (SELECT count(*) FROM programacion.provenance_receipts)<>v_receipts
  THEN RAISE EXCEPTION 'M99_POSTSTATE_NOT_EXACT:%',v_case; END IF;
  INSERT INTO pg_temp.ig_m99_integrated_probe_v1 VALUES
  (v_case,CASE v_case
   WHEN 'TIMEOUT' THEN 'HISTORICAL_ELAPSED_GT_POLICY_NOT_LIVE_CANARY'
   WHEN 'FALSE_PASS' THEN 'DB_OBSERVED_FAULT_AUTHORED_PRODUCER_PASS'
   WHEN 'DIVERGENCE' THEN 'DB_OBSERVED_MANIFEST_DELTA'
   WHEN 'EXECUTION_ERROR' THEN 'ACTUAL_SQL_DIVISION_BY_ZERO_CAUGHT'
   WHEN 'MISSING_RECEIPT' THEN 'CANONICAL_MISSING_RECEIPT_GATE'
   ELSE 'DB_OBSERVED_CLEAN' END,
  decision->>'action',v_trigger,true,v_count,
  'TRANSACTIONAL_SANDBOX_ONLY_NO_SIGNED_LIVE_CANARY');
 END LOOP;
 IF (SELECT count(*) FROM pg_temp.ig_m99_integrated_probe_v1)<>6
 OR (SELECT count(*) FROM pg_temp.ig_m99_integrated_probe_v1
  WHERE case_code<>'CLEAN' AND actual_abort)=0
 THEN RAISE EXCEPTION 'M99_SIX_CASE_MATRIX_INCOMPLETE'; END IF;
END $probe$;
SELECT * FROM pg_temp.ig_m99_integrated_probe_v1 ORDER BY case_code;
ROLLBACK;
