-- IG M10.5 CP2: close only the sampled checkpoint using current canonical
-- provider evidence, digest-bound assertion receipt and engineering transition.
-- Transport: LF Migration Merge Train. No extra screens, runs or capability release.
BEGIN;
DO $m105_sample_cp2$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M10.5';
 v_cp constant text := 'NEW_RUNS_VNEXT';
 v_actor constant text := 'IG_M105_CP2_SAMPLE_TRAIN_20261014';
 v_sample record;
 v_boot jsonb;
 v_ready jsonb;
 v_obs jsonb;
 v_receipt jsonb;
 v_transition jsonb;
 v_evidence text;
 v_prior_run bigint;
BEGIN
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
    OR v_boot#>>'{execution_readiness,status}' IS DISTINCT FROM 'READY'
    OR v_boot#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '1'
 THEN RAISE EXCEPTION 'M105_CP2_NOT_CURRENT_OR_NOT_READY:%',v_boot#>'{current_checkpoint}'; END IF;

 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=477 AND c.checkpoint_code='NEW_RUNS_VNEXT'
    AND c.status='PENDING' AND c.assertion_receipt_sha256 IS NULL)
 THEN RAISE EXCEPTION 'M105_CP2_CHECKPOINT_ALREADY_CHANGED'; END IF;

 SELECT * INTO STRICT v_sample FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 IF v_sample.schema_version IS DISTINCT FROM 'IG_M105_CP2_SAMPLE_READBACK_V1'
    OR v_sample.sample_screen_id IS DISTINCT FROM 1
    OR v_sample.sample_run_id IS NULL
    OR v_sample.sampled_screen_count IS DISTINCT FROM 1
    OR v_sample.sample_family_count IS DISTINCT FROM 5
    OR v_sample.valid_family_count IS DISTINCT FROM 5
    OR v_sample.run_status IS DISTINCT FROM 'COMPLETED'
    OR v_sample.source_current IS DISTINCT FROM true
    OR v_sample.stale_negative_verified IS DISTINCT FROM true
    OR v_sample.sample_verdict IS DISTINCT FROM 'PASS_CP2_MUESTRA'
    OR v_sample.authorizes_production IS DISTINCT FROM false
    OR jsonb_array_length(v_sample.sample_families) IS DISTINCT FROM 5
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_sample.sample_families) e(f)
      WHERE e.f->>'valid_evidence' IS DISTINCT FROM 'true')
 THEN RAISE EXCEPTION 'M105_CP2_REAL_SAMPLE_PROOF_MISSING'; END IF;

 SELECT r.id INTO v_prior_run
 FROM programacion.input_readiness_runs r
 WHERE r.pantalla_id=1 AND r.id < v_sample.sample_run_id
   AND r.status='COMPLETED'
   AND NOT programacion.fn_input_run_is_source_current(r.id)
 ORDER BY r.id DESC LIMIT 1;
 IF v_prior_run IS NULL OR v_prior_run=v_sample.sample_run_id
 THEN RAISE EXCEPTION 'M105_CP2_STALE_NEGATIVE_NOT_GENUINE'; END IF;
 IF NOT programacion.fn_input_run_is_source_current(v_sample.sample_run_id)
 THEN RAISE EXCEPTION 'M105_CP2_POSITIVE_RUN_IS_STALE'; END IF;

 -- The five families are chosen by previously installed contract, not here.
 IF (SELECT count(*) FROM programacion.input_family_assessments a
   WHERE a.run_id=v_sample.sample_run_id
   AND a.family_code IN ('STATES','SECURITY','API_DATA_CONTRACT',
       'FRESHNESS_INVALIDATION','ACCESSIBILITY')
   AND a.validator_outcome IN ('PASS','FAIL','BLOCKED')
   AND a.validator_identity IS NOT NULL
   AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
   AND a.validator_assessed_at IS NOT NULL
   AND jsonb_typeof(a.validator_findings)='array')<>5
 THEN RAISE EXCEPTION 'M105_CP2_SAMPLE_INDEPENDENT_VALIDATOR_ROWS_MISSING'; END IF;

 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
   v_plan,v_unit,v_cp);
 IF v_ready->>'status' IS DISTINCT FROM 'READY'
    OR v_ready->>'execution_ready' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M105_CP2_EXECUTION_READINESS_DENIED:%',v_ready; END IF;

 v_obs:=jsonb_build_object(
  'sampled_screen_count',v_sample.sampled_screen_count,
  'sample_family_count',v_sample.sample_family_count,
  'valid_family_count',v_sample.valid_family_count,
  'source_current',v_sample.source_current,
  'stale_negative_verified',v_sample.stale_negative_verified,
  'sample_verdict',v_sample.sample_verdict,
  'authorizes_production',v_sample.authorizes_production,
  'sample_run_id',v_sample.sample_run_id,
  'previous_stale_run_id',v_prior_run,
  'sample_families',v_sample.sample_families,
  'semantic_observation_count',v_sample.semantic_observation_count);
 v_evidence:='supabase://programacion.v_ig_m105_cp2_sample_readback_v1'
  ||'#screen=1&run='||v_sample.sample_run_id
  ||'&stale_negative='||v_prior_run;
 
 v_transition:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,
   v_evidence,v_actor,true);
 IF v_transition->>'status' IS DISTINCT FROM 'REPAIRED'
 THEN RAISE EXCEPTION 'M105_CP2_HEARTBEAT_START_FAILED:%',v_transition; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
  v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','evidence_ref',v_evidence,'observed',v_obs),
  v_actor);
 IF v_receipt->>'passed' IS DISTINCT FROM 'true'
    OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'M105_CP2_ASSERTION_NOT_RECORDED:%',v_receipt; END IF;

 v_transition:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,
   v_evidence,v_actor,true);
 IF v_transition->>'status' IS DISTINCT FROM 'REPAIRED'
 THEN RAISE EXCEPTION 'M105_CP2_HEARTBEAT_DONE_FAILED:%',v_transition; END IF;

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
  v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'Muestreo operacional de ONB_001 y cinco familias, positivo vigente y negativo stale reales; sin aprobación de producción ni requerimiento de censo.');
 IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M105_CP2_TRANSITION_FAILED:%',v_transition; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '2'
    OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'SUITE_M7_GREEN'
 THEN RAISE EXCEPTION 'M105_CP2_NEXT_CP_NOT_AVAILABLE:%',v_boot#>'{current_checkpoint}'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=477 AND c.checkpoint_code=v_cp AND c.status='DONE'
    AND c.assertion_receipt->>'passed'='true'
    AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256'
    AND c.assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(c.assertion_receipt))
 THEN RAISE EXCEPTION 'M105_CP2_FINAL_MACHINE_RECEIPT_MISSING'; END IF;
END $m105_sample_cp2$;
COMMIT;
