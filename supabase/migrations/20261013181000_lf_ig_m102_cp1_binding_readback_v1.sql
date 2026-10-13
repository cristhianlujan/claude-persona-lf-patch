-- M10.2 checkpoint BINDING_ASIS. Readback only; no operational activation.
DO $cp1$
DECLARE
 v_plan text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_sha text := 'd1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44';
 v_ready jsonb; v_state jsonb; v_result jsonb;
 v_evidence text := 'supabase://public.lf_capability_current/INPUT_GOVERNANCE@1.0.0;supabase://public.lf_capability_version_registry/INPUT_GOVERNANCE@1.0.0;supabase://programacion.engineering_work_checkpoints/M10.0#AUTHORITY_READBACK';
BEGIN
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,'M10.2');
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>'BINDING_ASIS'
 THEN RAISE EXCEPTION 'CP1_NOT_CURRENT'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,'M10.2','BINDING_ASIS');
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'CP1_NOT_READY'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_capability_current c
   JOIN public.lf_capability_version_registry r USING(capability_code,version)
   WHERE c.capability_code='INPUT_GOVERNANCE' AND c.version='1.0.0'
     AND c.manifest_sha256=v_sha AND r.manifest_sha256=v_sha
     AND c.previous_version IS NULL AND r.release_state='RELEASED')
   OR (SELECT count(*) FROM public.lf_capability_version_registry
       WHERE capability_code='INPUT_GOVERNANCE')<>1
   OR (SELECT count(*) FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
       WHERE u.plan_code=v_plan AND u.unit_code='M10.0'
         AND c.checkpoint_code IN ('HUMAN_DECISION_RECORD','AUTHORITY_READBACK')
         AND c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL)<>2
 THEN RAISE EXCEPTION 'CP1_POSITIVE_READBACK_FAILED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_capability_current
           WHERE capability_code='INPUT_GOVERNANCE'
             AND manifest_sha256=repeat('0',64))
 THEN RAISE EXCEPTION 'CP1_NEGATIVE_SHA_NOT_REJECTED'; END IF;
 v_result:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,'M10.2','BINDING_ASIS','ACTION_STARTED',NULL,'{}'::jsonb,
   v_evidence,'IG_M102_CP1_TRAIN',true);
 IF v_result->>'status'<>'REPAIRED'
 THEN RAISE EXCEPTION 'CP1_HEARTBEAT_START_FAILED'; END IF;
 v_result:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,'M10.2','BINDING_ASIS','ACTION_DONE',NULL,'{}'::jsonb,
   v_evidence,'IG_M102_CP1_TRAIN',true);
 IF v_result->>'status'<>'REPAIRED'
 THEN RAISE EXCEPTION 'CP1_HEARTBEAT_END_FAILED'; END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,'M10.2','BINDING_ASIS','DONE',v_evidence,'IG_M102_CP1_TRAIN',
   'CURRENT=1.0.0 RELEASED; single registry entry; negative SHA absent; M10.0 source verified');
 IF v_result#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'CP1_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=199 AND status='DONE')<>1
 THEN RAISE EXCEPTION 'CP1_POSTSTATE_FAILED'; END IF;
END $cp1$;
