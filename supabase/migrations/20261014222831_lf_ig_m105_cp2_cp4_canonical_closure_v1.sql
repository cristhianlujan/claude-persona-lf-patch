-- IG M10.5: one bounded, canonical closeout of CP2/CP3/CP4.
-- Transport: ACTUALIZACION_DB_LF / UPDATE MIGRATION via LF Migration Merge Train.
-- Explicitly *not* activating CIERRE_CHECKPOINT_INGENIERIA_LF candidate.
-- Reuses existing assertion recorder + DONE guard + canonical transition.
-- Same logical steps are first executed in a true exception-subtransaction
-- and rolled back; permanent pass happens only after readback proves rollback.
-- No new evaluation, no production readiness promotion, no unrelated unit.
DO $m105close$
DECLARE
 v_plan constant text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text:='M10.5';
 v_work constant bigint:=477;
 v_actor constant text:='IG_M105_CANONICAL_CP2_CP4_CLOSE_20261014';
 v_sample programacion.v_ig_m105_cp2_sample_readback_v1%rowtype;
 v_run programacion.input_readiness_runs%rowtype;
 v_status jsonb;
 v_contract jsonb;
 v_contract_sha text;
 v_observed jsonb;
 v_result jsonb;
 v_receipt jsonb;
 v_ref text;
 v_m7 text;
 v_m8 text;
 v_negative_error text;
 v_bad_result jsonb;
 v_stale bigint;
 v_family_count integer;
 v_family_distinct integer;
 v_family_valid integer;
 v_trial integer;
 v_post jsonb;
 v_read_count integer;
BEGIN
 -- READ authority at apply time; never trust a user-reported PASS.
 IF (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work
       AND disposition='ASSIGNED')<>1
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_SCOPE_OR_UNIT_CHANGED'; END IF;
 IF NOT EXISTS(
    SELECT 1 FROM public.lf_router_action_registry
    WHERE operation_code='ACTUALIZACION_DB_LF' AND asset_type='MIGRATION'
      AND action_code='UPDATE' AND status='ACTIVE' AND write_allowed=true)
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_DB_TRAIN_ROUTE_NOT_ACTIVE'; END IF;
 -- Do not enable the still-candidate dedicated operation.
 IF NOT EXISTS (
  SELECT 1 FROM public.lf_operation_registry
  WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
   AND status='CANDIDATO_READ_ONLY' AND lifecycle_state_code='OP_CANDIDATE')
 OR NOT EXISTS (
  SELECT 1 FROM public.lf_router_action_registry
  WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
    AND status='CANDIDATO_READ_ONLY' AND write_allowed=false)
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_CANDIDATE_BOUNDARY_CHANGED'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=v_work AND checkpoint_code='POST_CUTOVER_ASIS'
   AND status='DONE')
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work AND checkpoint_code IN
      ('NEW_RUNS_VNEXT','SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN','E2E_READBACK')
      AND status='PENDING' AND assertion_receipt_sha256 IS NULL)<>5
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_EXPECTED_STATES_CHANGED'; END IF;
 IF (SELECT programacion.fn_engineering_effective_open_blocker_count_v1(v_work))<>0
 OR EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(v_work) d
           WHERE d.is_unmet)
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_BLOCKER_OR_DEPENDENCY'; END IF;

 SELECT * INTO STRICT v_sample FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 IF v_sample.sample_screen_id IS DISTINCT FROM 1
 OR v_sample.sample_run_id IS DISTINCT FROM 931
 OR v_sample.run_status IS DISTINCT FROM 'COMPLETED'
 OR v_sample.sampled_screen_count IS DISTINCT FROM 1
 OR v_sample.sample_family_count IS DISTINCT FROM 5
 OR v_sample.valid_family_count IS DISTINCT FROM 5
 OR v_sample.sample_verdict IS DISTINCT FROM 'PASS_CP2_MUESTRA'
 OR v_sample.source_current IS DISTINCT FROM true
 OR v_sample.stale_negative_verified IS DISTINCT FROM true
 OR v_sample.authorizes_production IS DISTINCT FROM false
 OR jsonb_array_length(v_sample.sample_families)<>5
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_CANONICAL_SAMPLE_NOT_PASS'; END IF;
 SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs
 WHERE id=v_sample.sample_run_id;
 IF v_run.pantalla_id<>v_sample.sample_screen_id
 OR v_run.status<>'COMPLETED'
 OR programacion.fn_input_run_is_source_current(v_run.id) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_CURRENT_RUN_NOT_VERIFIED'; END IF;
 SELECT count(*),count(DISTINCT family_code),
        count(*) FILTER(WHERE validator_outcome IN ('PASS','FAIL','BLOCKED')
           AND validator_identity IS NOT NULL
           AND validator_sha256 ~ '^[0-9a-f]{64}$'
           AND validator_assessed_at IS NOT NULL
           AND jsonb_typeof(validator_findings)='array')
 INTO v_family_count,v_family_distinct,v_family_valid
 FROM programacion.input_family_assessments
 WHERE run_id=v_run.id AND family_code IN
    ('ACCESSIBILITY','API_DATA_CONTRACT','FRESHNESS_INVALIDATION','SECURITY','STATES');
 IF v_family_count<>5 OR v_family_distinct<>5 OR v_family_valid<>5
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_FIVE_INDEPENDENT_RECEIPTS_MISSING'; END IF;
 SELECT id INTO v_stale
 FROM programacion.input_readiness_runs r
 WHERE r.pantalla_id=1 AND r.status='COMPLETED'
   AND r.id<v_sample.sample_run_id AND NOT programacion.fn_input_run_is_source_current(r.id)
 ORDER BY id DESC LIMIT 1;
 IF v_stale IS NULL OR programacion.fn_input_run_is_source_current(v_stale)
 THEN RAISE EXCEPTION 'M105_CP_CLOSE_STALE_CONTROL_NOT_PROVEN'; END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 v_plan,v_unit,'NEW_RUNS_VNEXT',
 programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,'NEW_RUNS_VNEXT'));
 IF v_contract->>'status' IS DISTINCT FROM 'READY'
 OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M105_CP2_ASSERTION_CONTRACT_NOT_READY'; END IF;
 v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
 v_observed:=jsonb_build_object(
 'sample_verdict',v_sample.sample_verdict,
 'source_current',v_sample.source_current,
 'valid_family_count',v_family_valid,
 'sample_family_count',v_sample.sample_family_count,
 'sampled_screen_count',v_sample.sampled_screen_count,
 'stale_negative_verified',v_sample.stale_negative_verified,
 'authorizes_production',v_sample.authorizes_production,
 'sample_run_id',v_run.id,
 'stale_run_id',v_stale);
 IF (v_observed @> (v_contract->'pass_when')) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M105_CP2_ASSERTION_OBSERVED_NOT_MATCHING_CONTRACT'; END IF;
 v_ref:='supabase://programacion.v_ig_m105_cp2_sample_readback_v1#screen=1&run='
  ||v_run.id||'&stale_run='||v_stale;

 -- Fail-closed negative: a deliberately forged 4/5 must be rejected by the
 -- existing canonical recorder and leave absolutely no receipt.
 BEGIN
   v_bad_result:=jsonb_build_object('status','PASS','evidence_ref',v_ref,
       'observed',jsonb_set(v_observed,'{valid_family_count}','4'::jsonb,true));
   PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
       v_plan,v_unit,'NEW_RUNS_VNEXT',v_bad_result,v_actor);
   RAISE EXCEPTION 'M105_CP2_FORGED_FOUR_OF_FIVE_WAS_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS v_negative_error=MESSAGE_TEXT;
   IF v_negative_error NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
   THEN RAISE EXCEPTION 'M105_CP2_NEGATIVE_UNEXPECTED:%',v_negative_error; END IF;
 END;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=v_work AND checkpoint_code='NEW_RUNS_VNEXT'
    AND (assertion_receipt IS NOT NULL OR assertion_receipt_sha256 IS NOT NULL))
 THEN RAISE EXCEPTION 'M105_CP2_NEGATIVE_LEFT_RESIDUE'; END IF;

 -- A true reversible, positive end-to-end rehearsal FIRST. PostgreSQL undoes
 -- the assertion, transitions and engineering update ledger, atomically.
 FOR v_trial IN 1..2 LOOP
  BEGIN
   v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
   IF v_post->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEW_RUNS_VNEXT'
   THEN RAISE EXCEPTION 'M105_CP2_NOT_CURRENT'; END IF;
   v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
     v_plan,v_unit,'NEW_RUNS_VNEXT',
     jsonb_build_object('status','PASS','evidence_ref',v_ref,'observed',v_observed),
     v_actor);
   IF v_receipt->>'passed' IS DISTINCT FROM 'true'
   OR v_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
   OR coalesce(v_receipt->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
   THEN RAISE EXCEPTION 'M105_CP2_CANONICAL_RECEIPT_INVALID'; END IF;
   v_result:=programacion.fn_engineering_checkpoint_transition_v1(
     v_plan,v_unit,'NEW_RUNS_VNEXT','DONE',v_ref,v_actor,
     'ONB_001 run 931, five distinct independent family validators; old stale run rejected; no production grant');
   IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'M105_CP2_TRANSITION_NOT_APPLIED'; END IF;
   IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work AND checkpoint_code='NEW_RUNS_VNEXT' AND status='DONE'
    AND assertion_contract_sha256=v_contract_sha
    AND assertion_receipt_sha256=v_receipt->>'assertion_receipt_sha256'
    AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt))
   THEN RAISE EXCEPTION 'M105_CP2_DONE_RECEIPT_READBACK_BAD'; END IF;

   -- CP3 is non-material: read-only semantic M7 sample exactly as declared.
   SELECT CASE WHEN sample_verdict='PASS_CP2_MUESTRA' AND valid_family_count=5
     AND jsonb_array_length(sample_families)=5 THEN 'PASS' ELSE 'FAIL' END
    INTO STRICT v_m7 FROM programacion.v_ig_m105_cp2_sample_readback_v1;
   IF v_m7 IS DISTINCT FROM 'PASS' OR v_sample.semantic_observation_count<1
   THEN RAISE EXCEPTION 'M105_CP3_M7_SEMANTICS_NOT_PASS'; END IF;
   v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
   IF v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'SUITE_M7_GREEN'
   THEN RAISE EXCEPTION 'M105_CP3_NOT_CURRENT'; END IF;
   v_result:=programacion.fn_engineering_checkpoint_transition_v1(
     v_plan,v_unit,'SUITE_M7_GREEN','DONE',v_ref||'&m7=PASS',v_actor,
     'Five validator family outcomes and semantic findings independently classified; production holds are not technical errors');
   IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'M105_CP3_TRANSITION_NOT_APPLIED'; END IF;

   -- CP4 is non-material: real measured M8 timing under 150000 ms.
   SELECT CASE WHEN sample_verdict='PASS_CP2_MUESTRA'
     AND validator_elapsed_ms IS NOT NULL AND validator_elapsed_ms<=150000
     AND EXISTS(SELECT 1 FROM programacion.fn_ig_performance_timing_metrics_v1() t
          WHERE t.scope='SUMMARY' AND t.status='PUBLISHED' AND t.sample_count>0)
     THEN 'PASS' ELSE 'FAIL' END INTO STRICT v_m8
   FROM programacion.v_ig_m105_cp2_sample_readback_v1;
   IF v_m8 IS DISTINCT FROM 'PASS'
   THEN RAISE EXCEPTION 'M105_CP4_M8_LATENCY_NOT_PASS'; END IF;
   v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
   IF v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'PERF_M8_GREEN'
   THEN RAISE EXCEPTION 'M105_CP4_NOT_CURRENT'; END IF;
   v_result:=programacion.fn_engineering_checkpoint_transition_v1(
     v_plan,v_unit,'PERF_M8_GREEN','DONE',
     v_ref||'&validator_elapsed_ms='||v_sample.validator_elapsed_ms,
     v_actor,'Measured ONB_001 validator elapsed ms <=150000; M8 SUMMARY published');
   IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'M105_CP4_TRANSITION_NOT_APPLIED'; END IF;
   IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND status='DONE')<>4
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND status='PENDING')<>2
   THEN RAISE EXCEPTION 'M105_CP2_CP4_FINAL_STATES_BAD'; END IF;
   v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
   IF v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEG_STALE_RUN'
   OR (v_post#>>'{state,progress_pct}')::numeric<>75
   THEN RAISE EXCEPTION 'M105_CP2_CP4_NEXT_BOOTSTRAP_WRONG'; END IF;
   IF v_trial=1 THEN
     RAISE EXCEPTION 'M105_CP2_CP4_POSITIVE_ROLLBACK_SENTINEL' USING ERRCODE='PZ088';
   END IF;
  EXCEPTION WHEN SQLSTATE 'PZ088' THEN
   IF v_trial<>1 THEN RAISE EXCEPTION 'M105_CP_CLOSE_UNEXPECTED_ROLLBACK_SENTINEL'; END IF;
  END;
  IF v_trial=1 AND (
   (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work AND status='DONE')<>1
   OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work AND checkpoint_code='NEW_RUNS_VNEXT'
      AND (assertion_receipt_sha256 IS NOT NULL OR status<>'PENDING'))
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work AND status='PENDING')<>5)
  THEN RAISE EXCEPTION 'M105_CP2_CP4_POSITIVE_ROLLBACK_LEFT_RESIDUE'; END IF;
 END LOOP;
 -- DONE is proven ONLY for CP2 CP3 CP4; CP5 and CP6 remain PENDING.
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work AND checkpoint_code IN ('NEG_STALE_RUN','E2E_READBACK')
    AND status<>'PENDING')
 THEN RAISE EXCEPTION 'M105_CP5_CP6_UNAUTHORIZED_DELTA'; END IF;
END $m105close$;
