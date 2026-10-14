-- IG M10.3 CP3: real pointer rollback drill in PostgreSQL exception
-- subtransaction, with negative stale SHA + positive switch + reversibility,
-- followed by machine assertion and canonical checkpoint transition.
-- No operational release, no lasting registry row, no legacy delete.
DO $m103_cp3$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 cp constant text := 'ROLLBACK_DRILL';
 actor constant text := 'IG_M103_CP3_ROLLBACK_TRAIN_20261013';
 ev constant text := 'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_3/rollback_drill.py;supabase://schema_migrations/lf_ig_m103_cp3_rollback_drill_v1';
 old_sha text; new_sha text; new_manifest jsonb;
 b jsonb; a jsonb; result jsonb; negative jsonb; positive jsonb; reverted jsonb;
 test_executed boolean := false;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
  OR b#>>'{current_checkpoint,checkpoint_code}'<>cp
  OR b#>>'{execution_readiness,status}'<>'READY'
  OR b#>>'{state,done_checkpoint_count}'<>'2'
  OR b#>>'{state,progress_pct}'<>'40.00'
  OR b#>>'{state,open_blockers}'<>'0'
  OR b#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'M103_CP3_BOOTSTRAP_NOT_CURRENT'; END IF;
 IF (SELECT unit_metadata#>>'{m103_contract_governance_v1,phase}'
      FROM programacion.engineering_plan_units
      WHERE plan_code=p AND unit_code='M10.3') IS DISTINCT FROM 'CONSTRUCTION_SANDBOX'
 OR (SELECT unit_metadata#>>'{m103_contract_governance_v1,operational_cutover_authorized}'
      FROM programacion.engineering_plan_units
      WHERE plan_code=p AND unit_code='M10.3') IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M103_CP3_SCOPE_NOT_SANDBOX'; END IF;

 SELECT manifest_sha256 INTO STRICT old_sha
 FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
 AND previous_version IS NULL;
 IF (SELECT count(*) FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE')<>1
 OR NOT EXISTS(
      SELECT 1 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE'
      AND version='1.0.0' AND manifest_sha256=old_sha
      AND release_state='RELEASED')
 THEN RAISE EXCEPTION 'M103_CP3_SOURCE_BASELINE_DRIFT'; END IF;

 SELECT manifest || jsonb_build_object(
    'version','1.0.1',
    'migration',manifest->'migration' || jsonb_build_object('sandbox_m103_cp3_drill',true))
 INTO STRICT new_manifest
 FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
 new_sha:=encode(extensions.digest(convert_to(new_manifest::text,'UTF8'),'sha256'),'hex');
 IF new_sha IS NULL OR new_sha=old_sha
 THEN RAISE EXCEPTION 'M103_CP3_UNSAFE_TEST_MANIFEST'; END IF;

 -- The exception rolls back the entire temporary registry and CURRENT
 -- mutation, including the positive promotion and reverse promotion.
 BEGIN
   INSERT INTO public.lf_capability_version_registry(
     capability_code,version,version_major,version_minor,version_patch,
     release_state,supersedes_version,manifest,manifest_sha256,
     source_ref,docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',new_manifest,new_sha,
     source_ref,docs_ref,validator_ref,actor
   FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';

   negative:=public.fn_lf_capability_promote_v1(
     'INPUT_GOVERNANCE','1.0.1',repeat('0',64),actor,'M10.3 CP3 negative stale SHA');
   IF negative->>'decision'<>'BLOCK_CURRENTNESS_MISMATCH'
      OR negative->>'ready'<>'false'
      OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
           WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
           AND manifest_sha256=old_sha)
   THEN RAISE EXCEPTION 'M103_CP3_ADVERSARIAL_NEGATIVE_NOT_REJECTED:%',negative; END IF;

   positive:=public.fn_lf_capability_promote_v1(
     'INPUT_GOVERNANCE','1.0.1',old_sha,actor,'M10.3 CP3 sandbox pointer-only positive');
   IF positive->>'decision'<>'PROMOTED_CURRENT'
    OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE'
         AND version='1.0.1' AND manifest_sha256=new_sha)
   THEN RAISE EXCEPTION 'M103_CP3_POSITIVE_NOT_PROMOTED:%',positive; END IF;

   reverted:=public.fn_lf_capability_promote_v1(
     'INPUT_GOVERNANCE','1.0.0',new_sha,actor,'M10.3 CP3 sandbox pointer revert');
   IF reverted->>'decision'<>'PROMOTED_CURRENT'
     OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE'
       AND version='1.0.0' AND manifest_sha256=old_sha)
   THEN RAISE EXCEPTION 'M103_CP3_REVERT_NOT_EXECUTED:%',reverted; END IF;

   test_executed:=true;
   RAISE EXCEPTION USING ERRCODE='ZX013',MESSAGE='ROLLBACK_AFTER_M103_CP3';
 EXCEPTION WHEN SQLSTATE 'ZX013' THEN
   IF NOT test_executed THEN RAISE EXCEPTION 'M103_CP3_FALSE_TEST_ROLLBACK'; END IF;
 END;

 -- Readback OUTSIDE the subtransaction; no residual candidate/version.
 IF EXISTS(SELECT 1 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
 OR (SELECT count(*) FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE')<>1
 OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
      AND manifest_sha256=old_sha AND previous_version IS NULL)
 THEN RAISE EXCEPTION 'CP3_CANARY_RESIDUE'; END IF;

 b:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.3',cp);
 IF b->>'status'<>'READY' OR b->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'M103_CP3_READINESS_FAILED:%',b; END IF;
 a:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 p,'M10.3',cp,jsonb_build_object(
   'status','PASS','test_code','ENG_M10_3_ROLLBACK_DRILL',
   'evidence_ref',ev,
   'observed',jsonb_build_object(
      'test_passed',true,'test_exit_code',0,
      'semantic_authority_bound',true,'adversarial_case_executed',true)),
 actor);
 IF a->>'passed'<>'true' OR a->>'assertion_receipt_sha256' IS NULL
 THEN RAISE EXCEPTION 'M103_CP3_MACHINE_ASSERTION_MISSING:%',a; END IF;

 result:=programacion.fn_engineering_checkpoint_transition_v1(
 p,'M10.3',cp,'DONE',ev,actor,
 'Real canonical SHA-negative rejection, real ephemeral positive candidate pointer, real revert and PostgreSQL subtransaction ROLLBACK, zero persistent candidate, machine assertion receipt.');
 IF result#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M103_CP3_TRANSITION_FAILED:%',result; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b#>>'{state,done_checkpoint_count}'<>'3'
 OR b#>>'{state,progress_pct}'<>'65.00'
 OR b#>>'{current_checkpoint,checkpoint_code}'<>'ROLLBACK_SUITE'
 THEN RAISE EXCEPTION 'M103_CP3_POSTSTATE_MISMATCH:%',b#>'{state}'; END IF;
END $m103_cp3$;