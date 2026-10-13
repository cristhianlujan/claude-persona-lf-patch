-- M10.11 only: safe zero-target branch and independently verified N/A gate.
-- No ACL, function retirement, runtime activation or unrelated unit changes.
DO $pre$
DECLARE e bigint; n int;
BEGIN
 IF (SELECT w.status FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
    IS DISTINCT FROM 'IN_PROGRESS' THEN RAISE EXCEPTION 'M1011_STATE_DRIFT'; END IF;
 IF (SELECT u.unit_metadata#>>'{action_specs_v1,REVOKE_MIGRATION,status}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
     IS DISTINCT FROM 'BLOCK_NO_CURRENT_REMOVE_READY' THEN
    RAISE EXCEPTION 'M1011_SPEC_DRIFT'; END IF;
 SELECT max(id) INTO e FROM public.lf_eventos
 WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 SELECT count(*) INTO n FROM public.lf_eventos ev
 CROSS JOIN LATERAL jsonb_array_elements(ev.payload->'matrix') item
 WHERE ev.id=e AND item->>'class'='REMOVE_READY';
 IF e IS NULL OR n IS DISTINCT FROM 0 THEN
   RAISE EXCEPTION 'M1011_MATERIAL_TARGET_BRANCH_REQUIRED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_blockers
     WHERE work_item_id=197 AND blocker_code='M1011_NO_REMOVE_READY' AND status='OPEN')
     IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'M1011_BLOCKER_DRIFT'; END IF;
 IF (SELECT unit_metadata#>>'{m1011_live_sql_recheck_v2,authority}'
     FROM programacion.engineering_plan_units
     WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11')
     IS DISTINCT FROM 'PG_CATALOG_CURRENT_SQL_ONLY' THEN
   RAISE EXCEPTION 'M1011_SQL_EVIDENCE_MISSING'; END IF;
END;
$pre$;

-- M10.11-specific safety gate: no synthetic N/A and no material DONE
-- while no approved REMOVE_READY targets exist. Other units unaffected.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m1011_conditional_exit_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'programacion','public','pg_catalog'
AS $guard$
DECLARE e bigint; n int; receipt public.lf_test_suite_runs%rowtype;
        bundle jsonb;
BEGIN
 IF NEW.work_item_id IS DISTINCT FROM 197
   OR NEW.checkpoint_code NOT IN ('REVOKE_MIGRATION','NEG_CALLER_DENIED','REVOKE_READBACK')
   OR NEW.status NOT IN ('DONE','NOT_APPLICABLE') THEN RETURN NEW; END IF;
 SELECT max(id) INTO e FROM public.lf_eventos
 WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 SELECT count(*) INTO n FROM public.lf_eventos ev
 CROSS JOIN LATERAL jsonb_array_elements(ev.payload->'matrix') item
 WHERE ev.id=e AND item->>'class'='REMOVE_READY';
 IF e IS NULL OR n IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'M1011_RECHECK_MATERIAL_TARGET_BRANCH'; END IF;
 IF NEW.checkpoint_code IN ('REVOKE_MIGRATION','NEG_CALLER_DENIED')
   AND NEW.status='DONE' THEN
    RAISE EXCEPTION 'M1011_MATERIAL_DONE_WITHOUT_TARGET'; END IF;
 IF NEW.checkpoint_code='REVOKE_READBACK' AND NEW.status='NOT_APPLICABLE' THEN
    RAISE EXCEPTION 'M1011_TERMINAL_READBACK_REQUIRED'; END IF;
 SELECT * INTO receipt FROM public.lf_test_suite_runs t
 WHERE t.suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
   AND t.status='PASSED' AND t.tests_total>0
   AND t.tests_passed=t.tests_total
   AND coalesce(t.tests_failed,0)=0
   AND coalesce(t.tests_blocked,0)=0
   AND coalesce(t.tests_review_required,0)=0
   AND t.metadata->>'plan_code'='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND t.metadata->>'unit_code'='M10.11'
   AND t.metadata->>'historical_classification_id'=e::text
   AND t.metadata->>'remove_ready_count'='0'
   AND t.metadata->>'acl_unchanged'='true'
   AND t.metadata->>'independently_verified'='true'
   AND t.metadata#>>'{sources,SQL}'='PASS'
   AND t.metadata#>>'{sources,GIT}'='PASS'
   AND t.metadata#>>'{sources,EDGE}'='PASS'
   AND t.metadata#>>'{sources,ROUTER}'='PASS'
   AND t.metadata#>>'{sources,CONTRACTS}'='PASS'
   AND t.completed_at>=clock_timestamp()-interval '24 hours'
 ORDER BY t.completed_at DESC LIMIT 1;
 IF NOT FOUND THEN
    RAISE EXCEPTION 'M1011_INDEPENDENT_MULTISOURCE_SUITE_REQUIRED'; END IF;
 bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(receipt.suite_run_id);
 IF bundle->>'status' IS DISTINCT FROM 'VERIFIED' THEN
    RAISE EXCEPTION 'M1011_VERIFIED_RECEIPT_REQUIRED'; END IF;
 IF position(receipt.suite_run_id::text IN coalesce(NEW.evidence_ref,''))=0 THEN
    RAISE EXCEPTION 'M1011_RECEIPT_EVIDENCE_BINDING_REQUIRED'; END IF;
 RETURN NEW;
END;
$guard$;

CREATE TRIGGER trg_ig_m1011_conditional_exit_guard_v1
BEFORE UPDATE OF status ON programacion.engineering_work_checkpoints
FOR EACH ROW
WHEN (NEW.work_item_id=197 AND NEW.status IN ('DONE','NOT_APPLICABLE'))
EXECUTE FUNCTION programacion.fn_ig_m1011_conditional_exit_guard_v1();

-- Two independent no-target readbacks instead of impossible live REVOKE / denial.
UPDATE programacion.engineering_plan_units
SET unit_metadata=
 jsonb_set(
   jsonb_set(
     jsonb_set(
       unit_metadata,
       '{action_specs_v1,REVOKE_MIGRATION}',
       jsonb_build_object(
         'schema_version','ENGINEERING_ACTION_SPEC_V3',
         'status','READY',
         'checkpoint_code','REVOKE_MIGRATION',
         'action_kind','READBACK_ONCE',
         'recipe_mode','READBACK_EXACT',
         'requires_material_execution',false,
         'contract_family','CONDITIONAL_ZERO_TARGET_RETIREMENT',
         'expected','No REVOKE. N/A only after independently VERIFIED current zero-target multi-source suite, otherwise HOLD.',
         'target',jsonb_build_object('declared_assets',jsonb_build_array('ASSET_RETIREMENT_GOVERNANCE'),'declared_objects',jsonb_build_array('public.lf_eventos','public.lf_test_suite_runs','pg_catalog.pg_proc')),
         'terminal_guard','programacion.fn_ig_m1011_conditional_exit_guard_v1',
         'forbidden',jsonb_build_array('REVOKE_WHEN_ZERO','PREMATURE_NA','SYNTHETIC_PASS','PRODUCTION_ACTIVATION')),true),
       '{action_specs_v1,NEG_CALLER_DENIED}',
       jsonb_build_object(
         'schema_version','ENGINEERING_ACTION_SPEC_V3',
         'status','READY','checkpoint_code','NEG_CALLER_DENIED',
         'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
         'requires_material_execution',false,
         'expected','No live revoked target: N/A requires same VERIFIED zero-target receipt as CP3.',
         'target',jsonb_build_object('declared_objects',jsonb_build_array('public.lf_test_suite_runs','information_schema.routine_privileges')),
         'terminal_guard','programacion.fn_ig_m1011_conditional_exit_guard_v1',
         'forbidden',jsonb_build_array('LIVE_DENIAL_WITHOUT_APPROVED_TARGET','PREMATURE_NA')),true),
     '{m1011_retirement_governance_v1,decision_gate_v2}',
     jsonb_build_object('status','CONDITIONAL_ZERO_TARGET_VALIDATION',
       'transversal_change','NOT_APPLICABLE_CURRENT_RETIREE_GOVERNANCE_REUSED',
       'required_suite','IG_M1011_ZERO_TARGET_FINAL_V1',
       'independent_source_checks',jsonb_build_array('SQL','GIT','EDGE','ROUTER','CONTRACTS'),
       'historical_zero_is_not_pass',true,
       'checked_by','programacion.fn_ig_m1011_conditional_exit_guard_v1'),true),
 exit_criterion='Zero approved REMOVE_READY is a valid no-material-action branch. CP3 and CP4: N/A only with fresh VERIFIED independent SQL/Git/Edge/Router/Contracts suite and exact suite-bound evidence. CP5: mandatory DONE live readback. If current approved targets appear, stop and use separate exact material REVOKE contract. Never infer no callers from names or stale M10.10.'
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

DO $verify$
DECLARE spec jsonb; outcome jsonb;
BEGIN
 spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11','REVOKE_MIGRATION');
 IF spec->>'status' IS DISTINCT FROM 'READY'
    OR spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
    OR spec->>'requires_material_execution' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'M1011_COMPILED_SPEC_NOT_READBACK_READY'; END IF;
 IF programacion.fn_engineering_execution_packet_from_spec_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11','REVOKE_MIGRATION',spec,
   '{}'::jsonb)->>'status' IS DISTINCT FROM 'READY' THEN
   RAISE EXCEPTION 'M1011_COMPILED_PACKET_NOT_READY'; END IF;
 outcome:=programacion.fn_engineering_blocker_resolve_v1(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11','M1011_NO_REMOVE_READY',
 'supabase://programacion.engineering_plan_units/M10.11#m1011_retirement_governance_v1.decision_gate_v2',
 'IG_M1011_CONDITIONAL_REPAIR');
 IF outcome->>'status' IS DISTINCT FROM 'RESOLVED' THEN
   RAISE EXCEPTION 'M1011_BLOCKER_RECONCILE_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND status IN ('DONE','NOT_APPLICABLE')) IS DISTINCT FROM 2
 THEN RAISE EXCEPTION 'M1011_PREMATURE_CHECKPOINT_CLOSE'; END IF;
END;
$verify$;
