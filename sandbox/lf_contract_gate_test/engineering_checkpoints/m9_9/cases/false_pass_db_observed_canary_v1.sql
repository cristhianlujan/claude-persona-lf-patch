-- M9.9 / FALSE_PASS executable sandbox canary: DB-observed oracle, governed pointer, causal rollback.
-- BOTH cases use a real temporary version of INPUT_GOVERNANCE inside a subtransaction.
-- Producer PASS is an adversarial fixture, independently observed malformed manifest is DB-real.
-- This verifies executor mechanics only; a synthetic mutation is NOT a signed live canary.
BEGIN;
CREATE TEMP TABLE ig_m99_oracle_executor_cases_v1
(case_code text,producer_decision text,independent_decision text,
 rollback_decision text,rollback_triggered boolean,baseline_restored boolean,
 residue_versions integer,verified_canary_receipt boolean) ON COMMIT DROP;
DO $probe$
DECLARE b record; c record; m jsonb; sha text; outcome jsonb; verdict jsonb;
 n_before bigint; v_count integer; bad boolean; producer text; independent text;
 v_trigger boolean; v_case text; v_error text;
BEGIN
 SELECT version,manifest_sha256,previous_version INTO STRICT b
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 IF b.version IS DISTINCT FROM '1.0.0' OR b.previous_version IS NOT NULL
 THEN RAISE EXCEPTION 'M99_BASELINE_DRIFT'; END IF;
 SELECT count(*) INTO v_count FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_count<>1 THEN RAISE EXCEPTION 'M99_VERSION_REGISTRY_UNEXPECTED'; END IF;
 SELECT count(*) INTO n_before FROM programacion.provenance_receipts;
 FOR v_case IN SELECT unnest(ARRAY['CLEAN','FALSE_PASS']) LOOP
  bad:=v_case='FALSE_PASS';
  v_trigger:=false; producer:='PASS'; independent:=null; verdict:=null;
  BEGIN
   SELECT manifest || jsonb_build_object(
    'version','1.0.1','migration',
    manifest->'migration'||jsonb_build_object('sandbox_canary',true)
   ) INTO STRICT m FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   IF bad THEN
     m:=jsonb_set(m,'{migration,sandbox_canary_fault}','"FORBIDDEN_CANARY_FAULT"'::jsonb,true);
   END IF;
   sha:=encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.lf_capability_version_registry(
     capability_code,version,version_major,version_minor,version_patch,
     release_state,supersedes_version,manifest,manifest_sha256,source_ref,
     docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',
     m,sha,source_ref,docs_ref,validator_ref,'IG_M99_SANDBOX_ONLY'
   FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   outcome:=public.fn_lf_capability_promote_v1(
    'INPUT_GOVERNANCE','1.0.1',b.manifest_sha256,'IG_M99_SANDBOX_ONLY','transactional canary');
   IF outcome->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT' THEN
    RAISE EXCEPTION 'M99_CANDIDATE_PROMOTION_FAILED'; END IF;
   -- Independent observable fact from the authoritative DB registry, not a caller boolean.
   SELECT CASE WHEN v.manifest#>>'{migration,sandbox_canary_fault}' IS NULL
               THEN 'PASS' ELSE 'FAIL' END
   INTO independent
   FROM public.lf_capability_version_registry v JOIN public.lf_capability_current cur
     ON v.capability_code=cur.capability_code AND v.version=cur.version
   WHERE cur.capability_code='INPUT_GOVERNANCE' AND cur.manifest_sha256=sha;
   IF independent IS NULL THEN RAISE EXCEPTION 'M99_INDEPENDENT_OBSERVATION_MISSING'; END IF;
   verdict:=programacion.fn_ig_m99_canary_rollback_decision_v1(
     jsonb_build_object(
       'false_pass_detected',producer='PASS' AND independent='FAIL',
       'divergence_level','D0','elapsed_ms',100000,
       'execution_error',false,'receipt_present',true,'receipt_verified',true),150000);
   IF bad AND (verdict->>'action' IS DISTINCT FROM 'ROLLBACK_REQUIRED'
        OR NOT(verdict->'reason_codes' ? 'FALSE_PASS')) THEN
      RAISE EXCEPTION 'M99_FALSE_PASS_TRIGGER_NOT_DETECTED'; END IF;
   IF NOT bad AND verdict->>'action' IS DISTINCT FROM 'CONTINUE_OBSERVATION'
   THEN RAISE EXCEPTION 'M99_CLEAN_CASE_FALSE_ROLLBACK'; END IF;
   v_trigger:=bad;
   -- Even clean case is removed: this is an isolated, rollback-only test.
   RAISE EXCEPTION USING ERRCODE='ZX099',MESSAGE='M99_RETURN_TO_FROZEN_BASELINE';
  EXCEPTION WHEN SQLSTATE 'ZX099' THEN
   IF independent IS NULL OR verdict IS NULL THEN
      RAISE EXCEPTION 'M99_NO_QUALIFIED_TRANSACTIONAL_OBSERVATION'; END IF;
  END;
  SELECT version,manifest_sha256,previous_version INTO STRICT c
  FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
  SELECT count(*) INTO v_count FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1';
  IF c.version IS DISTINCT FROM b.version
   OR c.manifest_sha256 IS DISTINCT FROM b.manifest_sha256
   OR c.previous_version IS DISTINCT FROM b.previous_version
   OR v_count<>0 OR (SELECT count(*) FROM programacion.provenance_receipts)<>n_before
  THEN RAISE EXCEPTION 'M99_CANARY_RESTORE_OR_RECEIPT_RESIDUE'; END IF;
  INSERT INTO pg_temp.ig_m99_oracle_executor_cases_v1
  VALUES(v_case,producer,independent,verdict->>'action',v_trigger,true,v_count,false);
 END LOOP;
END $probe$;
SELECT * FROM pg_temp.ig_m99_oracle_executor_cases_v1 ORDER BY case_code;
ROLLBACK;
