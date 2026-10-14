-- M10.5 CP5/CP6, REAL governed SQL negative, assertion and terminal readback.
-- Only two canonical checkpoint transitions. Transport: LF Migration Train.
-- First success is rolled back, then replayed for permanent commit.
DO $m105$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 u constant text := 'M10.5';
 actor constant text := 'IG_M105_CP5_CP6_CANONICAL_20261014';
 w constant bigint := 477;
 s programacion.v_ig_m105_cp2_sample_readback_v1%rowtype;
 old_run programacion.input_readiness_runs%rowtype;
 new_run programacion.input_readiness_runs%rowtype;
 old_current boolean;
 new_current boolean;
 old_source boolean;
 new_source boolean;
 negative_executed boolean := false;
 exit_code integer := 1;
 assertion_contract jsonb;
 observed jsonb;
 receipt jsonb;
 transition jsonb;
 boot jsonb;
 evidence text;
 err text;
 trial integer;
 final_verdict text;
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units
       WHERE plan_code=p AND unit_code=u AND work_item_id=w AND disposition='ASSIGNED')<>1
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=w AND status='DONE')<>4
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=w AND status='PENDING'
       AND checkpoint_code IN ('NEG_STALE_RUN','E2E_READBACK'))<>2
 THEN RAISE EXCEPTION 'M105_CP5_EXPECTED_75_PERCENT_NOT_CURRENT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
   WHERE operation_code='ACTUALIZACION_DB_LF' AND asset_type='MIGRATION'
     AND action_code='UPDATE' AND status='ACTIVE' AND write_allowed)
 OR (SELECT status FROM public.lf_operation_registry
   WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF') IS DISTINCT FROM 'CANDIDATO_READ_ONLY'
 OR (SELECT write_allowed FROM public.lf_router_action_registry
   WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF') IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'M105_CP5_GOVERNED_ROUTE_CHANGED'; END IF;
 IF (SELECT programacion.fn_engineering_effective_open_blocker_count_v1(w))<>0
 OR EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(w) d WHERE d.is_unmet)
 THEN RAISE EXCEPTION 'M105_CP5_UNMET_DEPENDENCY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
    WHERE c.work_item_id=w AND c.checkpoint_code='NEW_RUNS_VNEXT' AND c.status='DONE'
      AND c.assertion_receipt->>'passed'='true'
      AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256'
      AND c.assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(c.assertion_receipt))
 THEN RAISE EXCEPTION 'M105_CP2_CANONICAL_RECEIPT_STALE'; END IF;

 SELECT * INTO STRICT s FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 SELECT * INTO STRICT old_run FROM programacion.input_readiness_runs WHERE id=825;
 SELECT * INTO STRICT new_run FROM programacion.input_readiness_runs WHERE id=s.sample_run_id;
 IF s.sample_screen_id<>1 OR s.sample_run_id<>931 OR s.sample_verdict<>'PASS_CP2_MUESTRA'
  OR s.source_current IS DISTINCT FROM true OR s.stale_negative_verified IS DISTINCT FROM true
  OR s.authorizes_production IS DISTINCT FROM false OR s.valid_family_count<>5
  OR old_run.status<>'COMPLETED' OR new_run.status<>'COMPLETED'
  OR old_run.pantalla_id<>1 OR new_run.pantalla_id<>1
  OR old_run.id>=new_run.id OR old_run.source_snapshot_sha256 IS NULL
  OR new_run.source_snapshot_sha256 IS NULL
  OR old_run.source_snapshot_sha256=new_run.source_snapshot_sha256
 THEN RAISE EXCEPTION 'M105_CP5_SOURCE_PROOF_DRIFT'; END IF;
 IF to_regprocedure('programacion.fn_input_readiness_run_is_current(bigint)') IS NULL
 OR to_regprocedure('programacion.fn_input_run_is_source_current(bigint)') IS NULL
 THEN RAISE EXCEPTION 'M105_CP5_CANONICAL_ORACLE_MISSING'; END IF;
 old_current:=programacion.fn_input_readiness_run_is_current(old_run.id);
 new_current:=programacion.fn_input_readiness_run_is_current(new_run.id);
 old_source:=programacion.fn_input_run_is_source_current(old_run.id);
 new_source:=programacion.fn_input_run_is_source_current(new_run.id);
 IF old_current IS DISTINCT FROM false OR old_source IS DISTINCT FROM false
 OR new_current IS DISTINCT FROM true OR new_source IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M105_CP5_LIVE_ORACLE_WRONG_OUTCOME'; END IF;

 -- Actually exercise the admission predicate with an old DB run, not a fixture.
 BEGIN
   IF NOT programacion.fn_input_readiness_run_is_current(old_run.id) THEN
     RAISE EXCEPTION 'IG_M105_NEG_STALE_REJECTED' USING ERRCODE='PZ089';
   END IF;
   RAISE EXCEPTION 'M105_CP5_OLD_RUN_WRONGLY_ACCEPTED';
 EXCEPTION WHEN SQLSTATE 'PZ089' THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err IS DISTINCT FROM 'IG_M105_NEG_STALE_REJECTED'
   THEN RAISE EXCEPTION 'M105_CP5_NEGATIVE_WRONG_REASON:%',err; END IF;
   negative_executed:=true; exit_code:=0;
 END;
 IF NOT negative_executed OR exit_code<>0
 OR (SELECT status FROM programacion.input_readiness_runs WHERE id=old_run.id)<>'COMPLETED'
 THEN RAISE EXCEPTION 'M105_CP5_NEGATIVE_TEST_DID_NOT_RUN_OR_LEFT_RESIDUE'; END IF;
 assertion_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
   p,u,'NEG_STALE_RUN',programacion.fn_engineering_checkpoint_action_spec_v3(p,u,'NEG_STALE_RUN'));
 IF assertion_contract->>'status' IS DISTINCT FROM 'READY'
 OR assertion_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M105_CP5_MATERIAL_CONTRACT_NOT_READY'; END IF;
 observed:=jsonb_build_object(
   'test_passed',negative_executed AND NOT old_current AND new_current,
   'test_exit_code',exit_code,
   'semantic_authority_bound',to_regprocedure('programacion.fn_input_readiness_run_is_current(bigint)') IS NOT NULL
      AND NOT old_source AND new_source,
   'adversarial_case_executed',negative_executed,
   'old_run_id',old_run.id,'current_run_id',new_run.id,
   'production_authorized',s.authorizes_production);
 IF (observed @> (assertion_contract->'pass_when')) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M105_CP5_MATERIAL_PROOF_NOT_MATCHING'; END IF;
 evidence:='supabase://programacion.fn_input_readiness_run_is_current#old='||old_run.id
   ||':REJECTED&new='||new_run.id||':CURRENT&negative_case=PZ089&old_source_sha='
   ||old_run.source_snapshot_sha256||'&new_source_sha='||new_run.source_snapshot_sha256;

 -- Genuine fail-closed assertion negative with no receipt.
 BEGIN
   PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(p,u,'NEG_STALE_RUN',
      jsonb_build_object('status','PASS','evidence_ref',evidence,
       'observed',jsonb_set(observed,'{adversarial_case_executed}','false'::jsonb,true)),actor);
   RAISE EXCEPTION 'M105_CP5_FORGED_OBSERVED_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
   THEN RAISE EXCEPTION 'M105_CP5_FORGED_OBSERVED_WRONG_REJECTION:%',err; END IF;
 END;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=w AND checkpoint_code='NEG_STALE_RUN' AND assertion_receipt_sha256 IS NOT NULL)
 THEN RAISE EXCEPTION 'M105_CP5_FORGED_OBSERVED_RESIDUE'; END IF;

 FOR trial IN 1..2 LOOP
  BEGIN
   boot:=programacion.fn_engineering_unit_bootstrap_v3(p,u);
   IF boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
   OR boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEG_STALE_RUN'
   THEN RAISE EXCEPTION 'M105_CP5_NOT_CURRENT'; END IF;
   receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(p,u,'NEG_STALE_RUN',
      jsonb_build_object('status','PASS','evidence_ref',evidence,'observed',observed),actor);
   IF receipt->>'passed' IS DISTINCT FROM 'true'
   OR coalesce(receipt->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
   THEN RAISE EXCEPTION 'M105_CP5_ASSERTION_RECEIPT_BAD'; END IF;
   transition:=programacion.fn_engineering_checkpoint_transition_v1(
      p,u,'NEG_STALE_RUN','DONE',evidence,actor,
      'Live canonical negative: run825 rejected; run931 current; no production authorization');
   IF transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'M105_CP5_DONE_NOT_APPLIED'; END IF;
   IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=w AND c.checkpoint_code='NEG_STALE_RUN' AND c.status='DONE'
        AND c.assertion_contract_sha256=receipt->>'contract_sha256'
        AND c.assertion_receipt_sha256=receipt->>'assertion_receipt_sha256'
        AND c.assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(c.assertion_receipt))
   THEN RAISE EXCEPTION 'M105_CP5_RECEIPT_LEDGER_READBACK_BAD'; END IF;
   SELECT CASE WHEN v.sample_verdict='PASS_CP2_MUESTRA'
    AND v.authorizes_production=false AND v.source_current AND v.valid_family_count=5
    AND (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=w AND checkpoint_code IN
         ('NEW_RUNS_VNEXT','SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN')
         AND status='DONE')=4
    THEN 'PASS' ELSE 'FAIL' END INTO STRICT final_verdict
   FROM programacion.v_ig_m105_cp2_sample_readback_v1 v;
   IF final_verdict<>'PASS'
   THEN RAISE EXCEPTION 'M105_CP6_E2E_READBACK_NOT_PASS'; END IF;
   boot:=programacion.fn_engineering_unit_bootstrap_v3(p,u);
   IF boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'E2E_READBACK'
   THEN RAISE EXCEPTION 'M105_CP6_NOT_CURRENT'; END IF;
   transition:=programacion.fn_engineering_checkpoint_transition_v1(p,u,'E2E_READBACK','DONE',
     'supabase://programacion.engineering_work_checkpoints/477#all6done;sample=931;production=false',
     actor,'Canonical sample E2E 4 prior done; CP5 negative tested; no production promotion');
   IF transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'M105_CP6_DONE_NOT_APPLIED'; END IF;
   boot:=programacion.fn_engineering_unit_bootstrap_v3(p,u);
   IF (boot#>>'{state,progress_pct}')::numeric IS DISTINCT FROM 100
   OR (boot#>>'{state,done_checkpoint_count}')::integer<>6
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=w AND status='DONE')<>6
   OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'DONE'
   THEN RAISE EXCEPTION 'M105_CP6_TERMINAL_STATE_NOT_100'; END IF;
   IF trial=1 THEN
     RAISE EXCEPTION 'M105_CP5_CP6_ROLLBACK_SENTINEL' USING ERRCODE='PZ090';
   END IF;
  EXCEPTION WHEN SQLSTATE 'PZ090' THEN
    IF trial<>1 THEN RAISE EXCEPTION 'M105_CP5_CP6_UNEXPECTED_REPLAY_SENTINEL'; END IF;
  END;
  IF trial=1 AND (
     (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=w AND status='DONE')<>4
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=w AND status='PENDING')<>2
     OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'IN_PROGRESS'
     OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=w AND checkpoint_code='NEG_STALE_RUN'
          AND assertion_receipt_sha256 IS NOT NULL))
  THEN RAISE EXCEPTION 'M105_CP5_CP6_ROLLBACK_LEFT_RESIDUE'; END IF;
 END LOOP;
END $m105$;
