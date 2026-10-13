-- M10.2 CP6: final sandbox readback after actual CP5 assertion.
-- CURRENT and registry unchanged; real operational cutover remains gated.
DO $cp6$
DECLARE p constant text:='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 h constant text:='d1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44';
 e constant text:='supabase://programacion.engineering_work_checkpoints/M10.2#NEG_REVERSE;supabase://public.lf_capability_current/INPUT_GOVERNANCE@1.0.0;github://cristhianlujan/claude-persona-lf-patch/pull/2445';
 meta jsonb; b jsonb; cp5 jsonb; receipt_sha text; result jsonb;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
 OR b#>>'{current_checkpoint,checkpoint_code}'<>'SWITCH_READBACK'
 OR b#>>'{state,open_blockers}'<>'0'
 OR b#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'CP6_BOOTSTRAP_NOT_CURRENT_OR_BLOCKED'; END IF;
 SELECT unit_metadata INTO meta FROM programacion.engineering_plan_units
 WHERE plan_code=p AND unit_code='M10.2' AND work_item_id=199 FOR UPDATE;
 IF meta#>>'{m10_2_contract_governance_v1,phase}'<>'CONSTRUCTION_SANDBOX'
 OR meta#>>'{m10_2_contract_governance_v1,activation_performed}'<>'false'
 OR meta#>>'{m10_2_contract_governance_v1,operational_gate}'
   <>'BLOCKED_PENDING_REGISTERED_CANDIDATE_AND_GOVERNED_AUTHORITY'
 THEN RAISE EXCEPTION 'CP6_OPERATIONAL_GATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=199 AND status='DONE')<>5
 THEN RAISE EXCEPTION 'CP6_PRECEDING_CHECKPOINTS_INCOMPLETE'; END IF;
 SELECT assertion_receipt,assertion_receipt_sha256 INTO cp5,receipt_sha
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=199 AND checkpoint_code='NEG_REVERSE' AND status='DONE';
 IF cp5 IS NULL OR cp5->>'passed'<>'true'
 OR cp5->>'checkpoint_code'<>'NEG_REVERSE'
 OR cp5->>'unit_code'<>'M10.2'
 OR cp5->>'evidence_ref' IS NULL
 OR receipt_sha IS NULL
 THEN RAISE EXCEPTION 'CP6_REAL_CANARY_ASSERTION_MISSING'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r USING(capability_code,version)
 WHERE c.capability_code='INPUT_GOVERNANCE'
 AND c.version='1.0.0' AND c.manifest_sha256=h
 AND r.manifest_sha256=h AND c.previous_version IS NULL AND r.release_state='RELEASED')
 OR (SELECT count(*) FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE')<>1
 OR EXISTS(SELECT 1 FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
 OR EXISTS(SELECT 1 FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE' AND manifest_sha256=repeat('0',64))
 THEN RAISE EXCEPTION 'CP6_CURRENT_OR_RESIDUE_READBACK_FAILED'; END IF;
 result:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2','SWITCH_READBACK');
 IF result->>'status'<>'READY' OR result->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'CP6_READINESS_FAIL'; END IF;
 result:=programacion.fn_engineering_checkpoint_transition_v1(
 p,'M10.2','SWITCH_READBACK','DONE',e,'IG_M102_CP6_TRAIN',
 'CP5 genuine passed assertion present; baseline 1.0.0 unchanged, 1 registered version, no residue, no operational promotion');
 IF result#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'CP6_TRANSITION_FAIL'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=199 AND status='DONE')<>6
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=199)<>'DONE'
 OR b#>>'{state,progress_pct}'::text IS NULL
 THEN RAISE EXCEPTION 'CP6_FINAL_UNIT_NOT_DONE'; END IF;
END $cp6$;