-- IG M9.9: remove leaked IG-specific cohort logic from the transversal
-- engineering blocker reconciler. Historical blocker is RESOLVED; the local
-- COHORT_BINDING checkpoint keeps its governed READBACK_ONCE contract.
-- Future cohort faults must be substantiated by consumer evidence, not
-- automatically reconciled by the shared core. No pointer/canary activation.
DO $repair$
DECLARE
  v_old text;
  v_new text;
  v_start int;
  v_end int;
BEGIN
  v_old:=pg_get_functiondef(
    'programacion.fn_engineering_blocker_reconcile_v1(text,text,boolean)'::regprocedure
  );
  IF md5(v_old)<>'d328eebbb8dd3b8a6c7c61241a00db0f' THEN
    RAISE EXCEPTION 'M99_TRANSVERSAL_CORE_BASELINE_DRIFT';
  END IF;
  v_start:=position('      elsif v_kind=''CURRENT_CAPABILITY_COHORT_BINDING'' then' in v_old);
  v_end:=position('      elsif v_kind=''LATEST_SUITE_RUN_PASS'' then' in v_old);
  IF v_start=0 OR v_end<=v_start THEN
    RAISE EXCEPTION 'M99_TRANSVERSAL_CORE_ANCHOR_DRIFT';
  END IF;
  v_new:=substr(v_old,1,v_start-1)||substr(v_old,v_end);
  IF position('input_governance_cohort' in v_new)>0
     OR position('CURRENT_CAPABILITY_COHORT_BINDING' in v_new)>0 THEN
    RAISE EXCEPTION 'M99_TRANSVERSAL_CORE_RETAINS_IG_COUPLING';
  END IF;
  EXECUTE v_new;

  -- Remove the now-obsolete product-specific automatic resolution rule.
  -- The already DONE cohort checkpoint retains its evidence; no history rewrite.
  UPDATE programacion.engineering_plan_units
  SET unit_metadata=unit_metadata #-
     '{blocker_reconciliation_v1,IG_M99_CUTOVER_CONTRACT_AUTHORITY_DRIFT}'
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M9.9'
    AND unit_metadata#>>'{blocker_reconciliation_v1,IG_M99_CUTOVER_CONTRACT_AUTHORITY_DRIFT,kind}'
      ='CURRENT_CAPABILITY_COHORT_BINDING'
    AND unit_metadata#>>'{action_specs_v1,COHORT_BINDING,status}'='READY'
    AND EXISTS (
      SELECT 1 FROM programacion.engineering_work_blockers b
      WHERE b.blocker_code='IG_M99_CUTOVER_CONTRACT_AUTHORITY_DRIFT'
        AND b.work_item_id=programacion.engineering_plan_units.work_item_id
        AND b.status='RESOLVED'
    );
  IF NOT FOUND THEN RAISE EXCEPTION 'M99_LOCAL_RULE_OR_BLOCKER_BASELINE_DRIFT'; END IF;
  IF md5(pg_get_functiondef(
    'programacion.fn_engineering_blocker_reconcile_v1(text,text,boolean)'::regprocedure
  ))<>'7e5448a881ce0a88f3786f349ac3f169' THEN
    RAISE EXCEPTION 'M99_TRANSVERSAL_CORE_POSTSTATE_DRIFT';
  END IF;
END $repair$;
