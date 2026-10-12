-- IG M9.9 / FALSE_PASS: real governed capability pointer rollback-only probe.
-- All writes are nested within exception-triggered subtransaction, outer ROLLBACK.
-- Historical real M4.9 oracle + authored producer PASS does not prove live canary.
BEGIN;
CREATE TEMP TABLE ig_m99_false_pass_pointer_result (
 case_code text, action text, abort_triggered boolean, baseline_restored boolean,
 before_version text, after_version text, candidate_version_count integer,
 signed_live_canary_proven boolean, automatic_live_canary_proven boolean
) ON COMMIT DROP;
DO $m99$
DECLARE
 v_baseline record;v_current record;v_manifest jsonb;v_candidate_sha text;
 v_prom jsonb;v_decision jsonb;v_abort boolean:=false;v_candidates int;v_receipts bigint;
BEGIN
 SELECT version,manifest_sha256,previous_version INTO STRICT v_baseline
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 IF v_baseline.version IS DISTINCT FROM '1.0.0'
 OR v_baseline.previous_version IS NOT NULL THEN
  RAISE EXCEPTION 'BASELINE_NOT_EXPECTED'; END IF;
 SELECT count(*) INTO v_candidates FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_candidates<>1 THEN RAISE EXCEPTION 'PREEXISTING_REGISTRY_VERSION_DRIFT'; END IF;
 SELECT count(*) INTO v_receipts FROM programacion.provenance_receipts;
 IF NOT EXISTS (
  SELECT 1 FROM public.lf_test_runs tr
  JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
  JOIN public.lf_test_suite_cases c ON c.test_code=tr.test_code
  WHERE tr.suite_run_id='980a2228-24ad-4d14-a63c-e8fbb251b783'::uuid
   AND tr.test_code='M4_9_T07_STALE_EVIDENCE'
   AND tr.status='PASS' AND ar.assertion_code=tr.test_code||'_ASSERT'
   AND ar.actual_value->>'detected'='true'
   AND ar.actual_value->>'false_pass'='false'
   AND c.expected_output->>'decision'='DETECTED_FAIL_CLOSED'
 ) THEN RAISE EXCEPTION 'HISTORICAL_ORACLE_NOT_CURRENTLY_PROVEN'; END IF;
 BEGIN
  SELECT manifest||jsonb_build_object('version','1.0.1','migration',
       manifest->'migration'||jsonb_build_object('sandbox_canary',true))
  INTO STRICT v_manifest FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
  v_candidate_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_capability_version_registry(
   capability_code,version,version_major,version_minor,version_patch,
   release_state,supersedes_version,manifest,manifest_sha256,source_ref,
   docs_ref,validator_ref,created_by_execution_id)
  SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',v_manifest,
   v_candidate_sha,source_ref,docs_ref,validator_ref,'IG_M99_FALSE_PASS_ROLLBACK_PROBE'
  FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
  v_prom:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',
   v_baseline.manifest_sha256,'IG_M99_FALSE_PASS_ROLLBACK_PROBE','rollback-only test');
  IF v_prom->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT' THEN
   RAISE EXCEPTION 'PROMOTER_NOT_OPERABLE:%',v_prom; END IF;
  -- Only the producer PASS is authored; M4.9 known mutation is historical proof.
  v_decision:=programacion.fn_ig_m99_canary_rollback_decision_v1(
   jsonb_build_object('false_pass_detected',true,'divergence_level','D0',
   'elapsed_ms',100000,'execution_error',false,
   'receipt_present',true,'receipt_verified',true),150000);
  IF v_decision->>'action' IS DISTINCT FROM 'ROLLBACK_REQUIRED'
   OR NOT (v_decision->'reason_codes' ? 'FALSE_PASS') THEN
   RAISE EXCEPTION 'FALSE_PASS_TRIGGER_MISSING'; END IF;
  v_abort:=true;
  RAISE EXCEPTION USING ERRCODE='ZX099',MESSAGE='ROLLBACK_REQUIRED_ABORT';
 EXCEPTION WHEN SQLSTATE 'ZX099' THEN
  IF v_abort IS NOT TRUE THEN RAISE EXCEPTION 'NOT_CAUSALLY_TRIGGERED'; END IF;
 END;
 SELECT version,manifest_sha256,previous_version INTO STRICT v_current
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 SELECT count(*) INTO v_candidates FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1';
 IF v_current.version IS DISTINCT FROM v_baseline.version
 OR v_current.manifest_sha256 IS DISTINCT FROM v_baseline.manifest_sha256
 OR v_current.previous_version IS DISTINCT FROM v_baseline.previous_version
 OR v_candidates<>0 OR (SELECT count(*) FROM programacion.provenance_receipts)<>v_receipts
 THEN RAISE EXCEPTION 'POINTER_OR_PROVENANCE_RESIDUE'; END IF;
 INSERT INTO pg_temp.ig_m99_false_pass_pointer_result VALUES (
 'FALSE_PASS','ROLLBACK_REQUIRED',v_abort,true,v_baseline.version,
 v_current.version,v_candidates,false,false);
END $m99$;
SELECT * FROM pg_temp.ig_m99_false_pass_pointer_result;
ROLLBACK;
