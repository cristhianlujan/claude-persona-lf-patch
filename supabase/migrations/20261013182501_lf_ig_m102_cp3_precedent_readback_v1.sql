-- M10.2 CP3 verifies an existing M9.2 sandbox switch, not a new cutover.
DO $cp3$
DECLARE p text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 h text:='d1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44';
 e text:='github://cristhianlujan/claude-persona-lf-patch/pull/2141;supabase://programacion.engineering_work_checkpoints/M9.2#SWITCH_REVERT_SANDBOX+BINDING_READBACK';
 b jsonb;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF b#>>'{current_checkpoint,checkpoint_code}'<>'SWITCH_ONLY_MIGRATION'
 THEN RAISE EXCEPTION 'CP3_NOT_CURRENT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON u.work_item_id=c.work_item_id
     WHERE u.plan_code=p AND u.unit_code='M9.2' AND c.checkpoint_code IN ('SWITCH_REVERT_SANDBOX','BINDING_READBACK') AND c.status='DONE' AND c.evidence_ref IS NOT NULL)<>2
 OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256=h AND previous_version IS NULL)
 OR (SELECT count(*) FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE')<>1
 THEN RAISE EXCEPTION 'CP3_PRECEDENT_OR_BASELINE_FAIL'; END IF;
 UPDATE programacion.engineering_work_checkpoints SET title='Readback del switch/revert sandbox M9.2, sin nuevo cutover'
 WHERE work_item_id=199 AND checkpoint_code='SWITCH_ONLY_MIGRATION' AND status='PENDING';
 b:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2','SWITCH_ONLY_MIGRATION');
 IF b->>'status'<>'READY' THEN RAISE EXCEPTION 'CP3_NOT_READY'; END IF;
 b:=programacion.fn_engineering_checkpoint_transition_v1(p,'M10.2','SWITCH_ONLY_MIGRATION','DONE',e,'IG_M102_CP3_TRAIN','M9.2 proof observed; fresh canary remains CP5, operational cutover blocked');
 IF b#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'CP3_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=199 AND status='DONE')<>3
 THEN RAISE EXCEPTION 'CP3_POSTSTATE_FAIL'; END IF;
END $cp3$;