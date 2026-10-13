-- M10.4 CP3 NEG_NEW_MIGRATION — real adversarial PR rejected by trusted CI.
-- GitHub negative PR #2464 is CLOSED, UNMERGED; no train label or DB apply.
-- Genuine executed test: SentinelX job script_job_83731e2d2129415382edb7a7d99684ed.
-- Positive reference: #2462 merged, independent admission SUCCESS.
BEGIN;
DO $m104_cp3$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M10.4';
 v_cp constant text := 'NEG_NEW_MIGRATION';
 v_test_blob constant text := 'f0bdc03c23dbbf61215b7b0465bdd152a186ee6d';
 v_current jsonb;
 v_ready jsonb;
 v_state jsonb;
 v_receipt jsonb;
 v_out jsonb;
 v_evidence text;
BEGIN
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'M104_CP3_NOT_CURRENT'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM programacion.engineering_work_checkpoints c
   WHERE c.work_item_id=476 AND c.checkpoint_code='FREEZE_RULE'
     AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
     AND nullif(c.assertion_receipt_sha256,'') IS NOT NULL
 ) THEN RAISE EXCEPTION 'M104_CP3_CP2_ASSERTION_MISSING'; END IF;

 -- Negative attempt is forbidden to change authoritative DB migration ledger.
 IF EXISTS(
   SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE name='lf_ig_m104_negative_ci_probe_reject'
 ) THEN RAISE EXCEPTION 'M104_CP3_NEGATIVE_MIGRATION_APPLIED'; END IF;

 SELECT unit_metadata->'m104_freeze_rule_v1'
 INTO v_current
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476;
 IF v_current->>'status'<>'INSTALLED_ENGINEERING_CI'
    OR v_current->>'adversarial_live_pr_test'<>'PENDING_CP3_NEG_NEW_MIGRATION'
    OR v_current->>'source_pr'<>'2460'
 THEN RAISE EXCEPTION 'M104_CP3_GUARD_AUTHORITY_MISSING'; END IF;

 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'M104_CP3_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='github://cristhianlujan/claude-persona-lf-patch/pull/2462'
   ||';github://cristhianlujan/claude-persona-lf-patch/pull/2464'
   ||';github://cristhianlujan/claude-persona-lf-patch/actions/runs/38458403560'
   ||';gitblob:'||v_test_blob
   ||';sentinelx://host_3d5ff6fb467d4e9e/script_job_83731e2d2129415382edb7a7d99684ed'
   ||';supabase://supabase_migrations.schema_migrations/NEGATIVE_NOT_APPLIED';

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,'IG_M104_CP3_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP3_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
   v_plan,v_unit,v_cp,
   jsonb_build_object(
     'status','PASS',
     'test_code','ENG_M10_4_NEG_NEW_MIGRATION',
     'evidence_ref',v_evidence,
     'observed',jsonb_build_object(
       'test_passed',true,
       'test_exit_code',0,
       'semantic_authority_bound',true,
       'adversarial_case_executed',true,
       'positive_pr',2462,
       'positive_ci','SUCCESS',
       'negative_pr',2464,
       'negative_ci','FAILURE_EXPECTED',
       'negative_log_run',38458403560,
       'negative_pr_merged',false,
       'negative_source_applied',false,
       'source_git_blob',v_test_blob
     )
   ),
   'IG_M104_CP3_TRAIN'
 );
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'M104_CP3_TEST_RECEIPT_FAILED'; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,'IG_M104_CP3_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP3_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,v_unit,v_cp,'DONE',v_evidence,'IG_M104_CP3_TRAIN',
   'GitHub PR2464 genuine freeze CI FAIL (expected); closed unmerged, 0 migration ledger; authorized positive #2462 PASS');
 IF v_out#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M104_CP3_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=476 AND status='DONE')<>3
 THEN RAISE EXCEPTION 'M104_CP3_POSTSTATE_FAILED'; END IF;

 -- Rule evidence recorded separately; no modification to immutable CP1 baseline.
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(
      unit_metadata,'{m104_freeze_rule_v1,adversarial_live_pr_test}',
      to_jsonb('CI_FAIL_EXPECTED_PR2464_CLOSED_UNMERGED_LEDGER_ZERO'::text),true)
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476;
END $m104_cp3$;
COMMIT;
