-- IG M10.3 CP5: final readback and canonical unit completion.
-- CP4 is checkpoint-scoped 1/1 reusing real CP3 material evidence;
-- no claim that all INPUT_GOVERNANCE_REGRESSION catalog cases passed.
-- Legacy remains deployed, not removed, not newly routed.
DO $m103_cp5$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 u constant text := 'M10.3';
 cp constant text := 'ROLLBACK_READBACK';
 actor constant text := 'IG_M103_CP5_FINAL_READBACK_20261013';
 w bigint; v_cur public.lf_capability_current%rowtype;
 v_state text; v_count bigint; v_candidates bigint; v_edges bigint;
 v_case_count bigint; v_run_id uuid; v_source_sha text;
 v_meta jsonb; v_assert_sha text; ev text; b jsonb; t jsonb;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,u);
 IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
   OR b#>>'{current_checkpoint,checkpoint_code}'<>cp
   OR b#>>'{execution_readiness,status}'<>'READY'
   OR b#>>'{state,done_checkpoint_count}'<>'4'
   OR b#>>'{state,progress_pct}'<>'85.00'
   OR b#>>'{state,open_blockers}'<>'0'
   OR b#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'M103_CP5_BOOTSTRAP_NOT_READY'; END IF;
 SELECT work_item_id,unit_metadata INTO STRICT w,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code=p AND unit_code=u;
 IF v_meta#>>'{m103_contract_governance_v1,phase}'<>'CONSTRUCTION_SANDBOX'
 OR v_meta#>>'{m103_contract_governance_v1,release_promotion_allowed}'<>'false'
 OR v_meta#>>'{m103_contract_governance_v1,legacy_drop_allowed}'<>'false'
 OR v_meta#>>'{m103_contract_governance_v1,operational_cutover_executed}'<>'false'
 OR v_meta#>>'{m103_contract_governance_v1,operational_zero_legacy_traffic_gate}'
    <> 'SEPARATE_NOT_EVALUATED'
 THEN RAISE EXCEPTION 'M103_CP5_GOVERNANCE_GATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND status='DONE')<>4
 OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND checkpoint_code<>cp AND status<>'DONE')
 THEN RAISE EXCEPTION 'M103_CP5_UPSTREAM_CHECKPOINT_NOT_DONE'; END IF;

 SELECT * INTO STRICT v_cur
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 SELECT count(*),count(*) FILTER(WHERE release_state='CANDIDATE')
 INTO v_count,v_candidates FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_cur.version<>'1.0.0' OR v_cur.previous_version IS NOT NULL
 OR v_count<>1 OR v_candidates<>0
 OR NOT EXISTS(
   SELECT 1 FROM public.lf_capability_version_registry r
   WHERE r.capability_code=v_cur.capability_code
     AND r.version=v_cur.version
     AND r.release_state='RELEASED'
     AND r.manifest_sha256=v_cur.manifest_sha256)
 THEN RAISE EXCEPTION 'M103_CP5_PTR_REGISTRY_OR_RESIDUE_MISMATCH'; END IF;

 SELECT count(*) INTO v_edges FROM public.lf_activos
 WHERE codigo_activo IN (
  'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
  'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
  'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1')
 AND tipo_activo='CAPABILITY'
 AND archived_at IS NULL
 AND estado_operativo='READ_ONLY';
 IF v_edges<>3 THEN RAISE EXCEPTION 'M103_CP5_LEGACY_ASSETS_NOT_PRESERVED'; END IF;

 SELECT assertion_receipt_sha256 INTO v_assert_sha
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=w AND checkpoint_code='ROLLBACK_DRILL'
 AND status='DONE' AND assertion_receipt->>'passed'='true';
 IF v_assert_sha IS NULL THEN RAISE EXCEPTION 'M103_CP5_DRILL_ASSERTION_NOT_PRESENT'; END IF;

 SELECT s.suite_run_id,s.metadata->>'source_assertion_sha256'
 INTO v_run_id,v_source_sha
 FROM public.lf_test_suite_runs s
 WHERE s.suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND s.metadata->>'unit_code'=u
  AND s.metadata->>'checkpoint_code'='ROLLBACK_SUITE'
  AND s.status='PASSED' AND s.tests_total=1
  AND s.tests_passed=1 AND s.tests_failed=0
  AND s.tests_blocked=0
  AND s.metadata->>'result_origin'='REUSED_VERIFIED_REAL_EXECUTION'
  AND s.metadata->>'full_catalog_evaluated'='false'
 ORDER BY created_at DESC LIMIT 1;
 IF v_run_id IS NULL OR v_source_sha IS DISTINCT FROM v_assert_sha
 THEN RAISE EXCEPTION 'M103_CP5_SOURCE_BOUND_SCOPED_SUITE_MISSING'; END IF;
 SELECT count(*) INTO v_case_count FROM public.lf_test_runs
 WHERE suite_run_id=v_run_id AND test_code='ENG_M10_3_ROLLBACK_DRILL'
 AND status='PASS' AND metadata->>'full_catalog_evaluated'='false';
 IF v_case_count<>1 THEN RAISE EXCEPTION 'M103_CP5_SCOPED_SUITE_CASE_INCONSISTENT'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge WHERE
   codigo='IG-M103-OPERATIONAL-CUTOVER-SANDBOX-CONFLATION-001'
   AND root_cause_family='R4_NO_CUESTIONA')
 THEN RAISE EXCEPTION 'M103_CP5_EKB_PREVENTION_NOT_REGISTERED'; END IF;

 ev:='supabase://public.lf_capability_current/INPUT_GOVERNANCE@'||v_cur.version||
     ';supabase://public.lf_capability_version_registry/INPUT_GOVERNANCE@'||v_cur.manifest_sha256||
     ';supabase://public.lf_test_suite_runs/'||v_run_id::text||
     ';supabase://programacion.engineering_work_checkpoints/M10.3#ROLLBACK_DRILL@'||v_assert_sha;
 t:=programacion.fn_engineering_checkpoint_transition_v1(
 p,u,cp,'DONE',ev,actor,
 'Real CP3 negative/positive/revert with subtransaction ROLLBACK (assertion SHA verified); original CURRENT 1.0.0 and manifest match sole RELEASED registry, 0 candidate; 3 legacy assets retained; scoped regression 1/1 reused valid execution (NOT full catalog); EKB verified; no operational promotion.');
 IF t#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M103_CP5_TRANSITION_FAILED:%',t; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=w AND status='DONE')<>5
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'DONE'
 THEN RAISE EXCEPTION 'M103_CP5_CANONICAL_WORK_NOT_DONE'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,u);
 IF b#>>'{state,progress_pct}'<>'100.00'
 OR b#>>'{state,done_checkpoint_count}'<>'5'
 THEN RAISE EXCEPTION 'M103_CP5_FINAL_PROGRESS_MISMATCH:%',b#>'{state}'; END IF;
END $m103_cp5$;