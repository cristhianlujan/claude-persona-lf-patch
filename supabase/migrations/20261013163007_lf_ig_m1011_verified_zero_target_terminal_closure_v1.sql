-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.11 ONLY.
-- Authoritative suite independent provider readback: verified 2026-10-13,
-- suite IG_M1011_ZERO_TARGET_FINAL_V1, one actual external Python run
-- covering seven scenarios / four negatives, 5 source surfaces.
-- No ACL GRANT/REVOKE, function DROP or production change.
-- Checkpoint changes ONLY via fn_engineering_checkpoint_transition_v1.
DO $m1011_close$
DECLARE
 v_plan text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit text:='M10.11';
 v_actor text:='IG_M1011_VERIFIED_ZERO_TARGET_CLOSURE_V1';
 v_suite public.lf_test_suite_runs%rowtype;
 v_receipt jsonb;
 v_ref text;
 v_boot jsonb;
 v_result jsonb;
 v_latest bigint;
 v_ready bigint;
 v_count bigint;
 v_source_or_acl_drift bigint;
 v_error text;
 v_progress numeric;
BEGIN
 SELECT * INTO v_suite FROM public.lf_test_suite_runs
 WHERE suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND OR v_suite.status IS DISTINCT FROM 'PASSED'
    OR v_suite.tests_total<=0 OR v_suite.tests_total IS DISTINCT FROM v_suite.tests_passed
    OR coalesce(v_suite.tests_failed,0)<>0
    OR coalesce(v_suite.tests_blocked,0)<>0
    OR coalesce(v_suite.tests_review_required,0)<>0
    OR v_suite.metadata->>'plan_code' IS DISTINCT FROM v_plan
    OR v_suite.metadata->>'unit_code' IS DISTINCT FROM v_unit
    OR v_suite.metadata->>'independently_verified' IS DISTINCT FROM 'true'
    OR v_suite.metadata->>'acl_unchanged' IS DISTINCT FROM 'true'
    OR v_suite.metadata->>'remove_ready_count' IS DISTINCT FROM '0'
    OR v_suite.completed_at<clock_timestamp()-interval '24 hours' THEN
   RAISE EXCEPTION 'M1011_VERIFIED_SUITE_PRECONDITION_FAILED';
 END IF;
 IF EXISTS (
   SELECT 1 FROM (VALUES('SQL'),('GIT'),('EDGE'),('ROUTER'),('CONTRACTS')) t(name)
   WHERE v_suite.metadata#>>ARRAY['sources',t.name] IS DISTINCT FROM 'PASS'
 ) THEN RAISE EXCEPTION 'M1011_SUITE_HAS_MISSING_SOURCE_PROOF'; END IF;
 IF v_suite.metadata->>'dynamic_absence_proven' IS DISTINCT FROM 'false' THEN
   RAISE EXCEPTION 'M1011_UNSAFE_ABSENCE_CLAIM';
 END IF;
 v_receipt:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite.suite_run_id);
 IF v_receipt->>'status' IS DISTINCT FROM 'VERIFIED'
    OR v_receipt#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true'
    OR v_receipt#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'M1011_CURRENT_SUITE_RECEIPT_UNVERIFIED:%',v_receipt;
 END IF;
 SELECT max(id) INTO v_latest FROM public.lf_eventos
 WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 IF v_latest::text IS DISTINCT FROM
    v_suite.metadata->>'historical_classification_id' THEN
    RAISE EXCEPTION 'M1011_CLASSIFICATION_CURRENTNESS_CHANGED';
 END IF;
 SELECT count(*) INTO v_ready FROM public.lf_eventos e
 CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
 WHERE e.id=v_latest AND item->>'class'='REMOVE_READY';
 IF v_ready IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'M1011_REMOVE_READY_TARGETS_CHANGED';
 END IF;
 WITH curr AS (
  SELECT x.item,p.oid,p.prosrc FROM programacion.engineering_plan_units u
  CROSS JOIN LATERAL jsonb_array_elements(
       u.unit_metadata#>'{m1011_live_sql_recheck_v2,functions}') x(item)
  LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.item->>'observed_signature')
  WHERE u.plan_code=v_plan AND u.unit_code=v_unit
 )
 SELECT count(*), count(*) FILTER (WHERE oid IS NULL
    OR md5(prosrc) IS DISTINCT FROM item->>'function_source_md5'
    OR has_function_privilege('anon',oid,'EXECUTE') IS DISTINCT FROM
          (item#>>'{effective_execute,anon}')::boolean
    OR has_function_privilege('authenticated',oid,'EXECUTE') IS DISTINCT FROM
          (item#>>'{effective_execute,authenticated}')::boolean
    OR has_function_privilege('service_role',oid,'EXECUTE') IS DISTINCT FROM
          (item#>>'{effective_execute,service_role}')::boolean)
 INTO v_count,v_source_or_acl_drift FROM curr;
 IF v_count<=0 OR v_source_or_acl_drift<>0 OR
    v_count IS DISTINCT FROM
       (SELECT count(*) FROM public.lf_eventos e
        CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
        WHERE e.id=v_latest AND item->>'class'='LEGACY_UNREFERENCED') THEN
   RAISE EXCEPTION 'M1011_SQL_SOURCE_ACL_CHANGED_SINCE_REAL_SUITE';
 END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_blockers
   WHERE work_item_id=197 AND status='OPEN') IS DISTINCT FROM 0 THEN
   RAISE EXCEPTION 'M1011_BLOCKERS_REOPENED';
 END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('code',checkpoint_code,'status',status)
     ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197) IS DISTINCT FROM
     '[{"code":"GRANTS_ASIS","status":"DONE"},{"code":"REUSE_RETIREMENT_GOV","status":"DONE"},{"code":"REVOKE_MIGRATION","status":"IN_PROGRESS"},{"code":"NEG_CALLER_DENIED","status":"PENDING"},{"code":"REVOKE_READBACK","status":"PENDING"}]'::jsonb THEN
   RAISE EXCEPTION 'M1011_CHECKPOINT_PRESTATE_DRIFT';
 END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{action_spec,status}' IS DISTINCT FROM 'READY'
    OR v_boot#>>'{execution_readiness,status}' IS DISTINCT FROM 'READY' THEN
   RAISE EXCEPTION 'M1011_BOOTSTRAP_NOT_READY_FOR_CLOSURE';
 END IF;
 v_ref:='supabase://public.lf_test_suite_runs/'||v_suite.suite_run_id::text||
   '#IG_M1011_ZERO_TARGET_FINAL_V1=PASSED;bundle=VERIFIED;no_revoke=true';

 -- Negative case against the ACTUAL scoped transition. Any unbound fake
 -- evidence is rejected, and the attempted mutation rolls back automatically
 -- within this exception block; no residual writes.
 BEGIN
   PERFORM programacion.fn_engineering_checkpoint_transition_v1(
     v_plan,v_unit,'REVOKE_MIGRATION','NOT_APPLICABLE',
     'supabase://test/forged-unbound-suite',v_actor,
     'Adversarial: missing canonical suite ref must fail');
   RAISE EXCEPTION 'M1011_FORGED_SUITE_NEGATIVE_FALSE_PASS';
 EXCEPTION WHEN raise_exception THEN
   GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
   IF v_error NOT LIKE 'M1011_RECEIPT_EVIDENCE_BINDING_REQUIRED%' THEN
     RAISE EXCEPTION 'M1011_FORGED_SUITE_NEGATIVE_UNEXPECTED:%',v_error;
   END IF;
 END;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND checkpoint_code='REVOKE_MIGRATION')
     IS DISTINCT FROM 'IN_PROGRESS' THEN
   RAISE EXCEPTION 'M1011_NEGATIVE_TEST_LEFT_RESIDUE';
 END IF;

 -- Canonical, evidence-bound, one-at-a-time transitions and fresh readbacks.
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,'REVOKE_MIGRATION','NOT_APPLICABLE',
    v_ref,v_actor,'Verified current 0 REMOVE_READY; no physical REVOKE');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
   RAISE EXCEPTION 'M1011_CP3_NOT_APPLIED:%',v_result;
 END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEG_CALLER_DENIED'
    OR v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT' THEN
   RAISE EXCEPTION 'M1011_CP4_NOT_CURRENT_AFTER_CP3';
 END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,'NEG_CALLER_DENIED','NOT_APPLICABLE',
    v_ref,v_actor,'No revoked target; live denial test not applicable, independent suite verified');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
   RAISE EXCEPTION 'M1011_CP4_NOT_APPLIED:%',v_result;
 END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'REVOKE_READBACK'
    OR v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT' THEN
   RAISE EXCEPTION 'M1011_CP5_NOT_CURRENT_AFTER_CP4';
 END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,'REVOKE_READBACK','DONE',
    v_ref,v_actor,'Final readback no ACL delta, 0 approved removal, 5 surfaces, VERIFIED suite');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
   RAISE EXCEPTION 'M1011_CP5_NOT_APPLIED:%',v_result;
 END IF;

 -- Final live ledger + live privilege readback, no fabricated completion.
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=197)
    IS DISTINCT FROM 'DONE' THEN
   RAISE EXCEPTION 'M1011_WORK_ITEM_NOT_DONE';
 END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND status IN ('DONE','NOT_APPLICABLE'))
    IS DISTINCT FROM
    (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197) THEN
   RAISE EXCEPTION 'M1011_REQUIRED_CHECKPOINTS_NOT_TERMINAL';
 END IF;
 SELECT p.progress_pct INTO v_progress FROM programacion.v_engineering_work_progress p
 WHERE p.work_code='PAULO-095';
 IF v_progress IS DISTINCT FROM 100 THEN
   RAISE EXCEPTION 'M1011_LEDGER_PROGRESS_NOT_100:%',v_progress;
 END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_blockers
   WHERE work_item_id=197 AND status='OPEN')<>0 THEN
   RAISE EXCEPTION 'M1011_FINAL_BLOCKER_NOT_ZERO';
 END IF;
END;
$m1011_close$;
