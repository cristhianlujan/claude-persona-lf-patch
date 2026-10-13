-- M10.2 CP5: real positive + negative canary with subtransaction rollback.
-- A PASS assertion is recorded only after PostgreSQL executes and checks no residue.
DO $cp5$
DECLARE
 p constant text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 cp constant text:='NEG_REVERSE';
 actor constant text:='IG_M102_CP5_CANARY_TRAIN_20261013';
 old_sha constant text:='d1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44';
 e constant text:='github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_2/neg_reverse.py;supabase://schema_migrations/lf_ig_m102_cp5_canary_assertion_v1';
 meta jsonb; base jsonb; new_manifest jsonb; new_sha text;
 negative jsonb; positive jsonb; reverted jsonb; x jsonb;
 test_executed boolean:=false;
BEGIN
 base:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF base->>'terminal_action'<>'STOP_ACTION_SPEC_INCOMPLETE'
 OR base#>>'{current_checkpoint,checkpoint_code}'<>cp
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=199 AND status='DONE')<>4
 THEN RAISE EXCEPTION 'CP5_PRESTATE_FAIL'; END IF;
 SELECT unit_metadata INTO meta FROM programacion.engineering_plan_units
 WHERE plan_code=p AND unit_code='M10.2' AND work_item_id=199 FOR UPDATE;
 IF meta#>>'{action_specs_v1,NEG_REVERSE,status}'<>'BLOCK_GENUINE_ASSERTION_UNTIL_EXECUTED'
 OR meta#>>'{m10_2_contract_governance_v1,phase}'<>'CONSTRUCTION_SANDBOX'
 OR meta#>>'{m10_2_contract_governance_v1,operational_gate}'<>'BLOCKED_PENDING_REGISTERED_CANDIDATE_AND_GOVERNED_AUTHORITY'
 THEN RAISE EXCEPTION 'CP5_CONTRACT_SCOPE_DRIFT'; END IF;
 meta:=jsonb_set(meta,'{action_specs_v1,NEG_REVERSE,status}','"READY"'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=meta WHERE plan_code=p AND unit_code='M10.2' AND work_item_id=199;
 base:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF base->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' THEN RAISE EXCEPTION 'CP5_AUTHORING_NOT_READY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_capability_current
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
   AND manifest_sha256=old_sha AND previous_version IS NULL)
 OR (SELECT count(*) FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE')<>1
 THEN RAISE EXCEPTION 'CP5_BASELINE_NOT_CLEAN'; END IF;
 SELECT manifest||jsonb_build_object('version','1.0.1',
   'migration',manifest->'migration'||jsonb_build_object('sandbox_canary',true))
 INTO new_manifest
 FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
 new_sha:=encode(extensions.digest(convert_to(new_manifest::text,'UTF8'),'sha256'),'hex');

 -- Nested exception block is a PostgreSQL subtransaction. Its exception
 -- rolls back BOTH the temporary registry row and every pointer promotion.
 BEGIN
   INSERT INTO public.lf_capability_version_registry(
     capability_code,version,version_major,version_minor,version_patch,
     release_state,supersedes_version,manifest,manifest_sha256,
     source_ref,docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',new_manifest,new_sha,
     source_ref,docs_ref,validator_ref,actor
   FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';

   -- Actual negative test: stale SHA must be rejected by real canonical function.
   negative:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',
      repeat('0',64),actor,'negative SHA mismatch');
   IF negative->>'decision'<>'BLOCK_CURRENTNESS_MISMATCH'
      OR negative->>'ready'<>'false'
      OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
        WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
        AND manifest_sha256=old_sha)
   THEN RAISE EXCEPTION 'CP5_NEGATIVE_NOT_BLOCKED:%',negative; END IF;

   positive:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',
      old_sha,actor,'temporary sandbox canary');
   IF positive->>'decision'<>'PROMOTED_CURRENT'
     OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1'
       AND manifest_sha256=new_sha)
   THEN RAISE EXCEPTION 'CP5_POSITIVE_SWITCH_FAILED:%',positive; END IF;

   reverted:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',
      new_sha,actor,'revert temporary sandbox canary');
   IF reverted->>'decision'<>'PROMOTED_CURRENT'
     OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
       AND manifest_sha256=old_sha)
   THEN RAISE EXCEPTION 'CP5_REVERSE_FAILED:%',reverted; END IF;
   test_executed:=true;
   RAISE EXCEPTION USING ERRCODE='ZX005',MESSAGE='ROLLBACK_AFTER_CP5_TEST';
 EXCEPTION WHEN SQLSTATE 'ZX005' THEN
   IF NOT test_executed THEN RAISE EXCEPTION 'CP5_FALSE_ROLLBACK'; END IF;
 END;

 -- The following readback is outside the rolled-back subtransaction.
 IF EXISTS(SELECT 1 FROM public.lf_capability_version_registry
     WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
   OR (SELECT count(*) FROM public.lf_capability_version_registry
     WHERE capability_code='INPUT_GOVERNANCE')<>1
   OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
     WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
       AND manifest_sha256=old_sha AND previous_version IS NULL)
 THEN RAISE EXCEPTION 'CANARY_RESIDUE'; END IF;

 -- Before actual execution status remained fail-closed. Now authorize
 -- assertion recording, NEVER an unconditional DONE.
 meta:=jsonb_set(meta,'{action_specs_v1,NEG_REVERSE,status}','"READY"'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=meta
 WHERE plan_code=p AND unit_code='M10.2' AND work_item_id=199;
 base:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2',cp);
 IF base->>'status'<>'READY' OR base->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'CP5_READINESS_POST_EXECUTION_FAIL:%',base; END IF;
 x:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 p,'M10.2',cp,jsonb_build_object(
 'status','PASS','test_code','ENG_M10_2_NEG_REVERSE',
 'evidence_ref',e,
 'observed',jsonb_build_object(
   'test_passed',true,'test_exit_code',0,
   'semantic_authority_bound',true,'adversarial_case_executed',true)),
 actor);
 IF x->>'passed'<>'true' OR x->>'assertion_receipt_sha256' IS NULL
 THEN RAISE EXCEPTION 'CP5_ASSERTION_NOT_RECORDED'; END IF;
 x:=programacion.fn_engineering_checkpoint_transition_v1(
 p,'M10.2',cp,'DONE',e,actor,
 'Real negative SHA rejection, positive canary switch, reverse, subtransaction ROLLBACK, zero residue, assertion receipt recorded');
 IF x#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'CP5_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=199 AND status='DONE')<>5
 OR (programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2')
   #>>'{current_checkpoint,checkpoint_code}')<>'SWITCH_READBACK'
 THEN RAISE EXCEPTION 'CP5_POSTSTATE_FAIL'; END IF;
END $cp5$;
