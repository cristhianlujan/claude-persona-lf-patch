-- IG M10.2 CP2: verify existing M9.2 mechanism; no operational activation.
DO $cp2$
DECLARE
  p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  e constant text := 'github://cristhianlujan/claude-persona-lf-patch/pull/2141;supabase://programacion.engineering_work_checkpoints/M9.2#SWITCH_REVERT_SANDBOX+BINDING_READBACK';
  b jsonb;
  n jsonb;
  h text;
BEGIN
  b := programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
  IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
     OR b#>>'{current_checkpoint,checkpoint_code}'<>'REUSE_CAPABILITY_CUTOVER'
  THEN RAISE EXCEPTION 'M102_CP2_NOT_CURRENT'; END IF;
  b := programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2','REUSE_CAPABILITY_CUTOVER');
  IF b->>'status'<>'READY' OR b->>'execution_ready'<>'true'
  THEN RAISE EXCEPTION 'M102_CP2_NOT_READY'; END IF;
  IF to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') IS NULL
     OR (SELECT count(*) FROM programacion.engineering_plan_units u
          JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
         WHERE u.plan_code=p AND u.unit_code='M9.2'
           AND c.checkpoint_code IN ('SWITCH_REVERT_SANDBOX','BINDING_READBACK')
           AND c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL)<>2
     OR (SELECT count(*) FROM public.lf_capability_version_registry
         WHERE capability_code='INPUT_GOVERNANCE')<>1
  THEN RAISE EXCEPTION 'M102_CP2_POSITIVE_REUSE_NOT_VERIFIED'; END IF;
  SELECT c.manifest_sha256 INTO h FROM public.lf_capability_current c
   WHERE c.capability_code='INPUT_GOVERNANCE' AND c.version='1.0.0';
  IF h IS DISTINCT FROM 'd1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44'
  THEN RAISE EXCEPTION 'M102_CP2_CURRENT_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_capability_version_registry
            WHERE capability_code='INPUT_GOVERNANCE' AND version='9.9.99')
  THEN RAISE EXCEPTION 'M102_CP2_NEGATIVE_FIXTURE_COLLISION'; END IF;
  n := public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','9.9.99',h,
                                          'IG_M102_CP2_NEGATIVE','test missing version');
  IF n->>'decision'<>'BLOCK_VERSION_NOT_FOUND' OR n->>'ready'<>'false'
  THEN RAISE EXCEPTION 'M102_CP2_NEGATIVE_NOT_REJECTED'; END IF;
  b := programacion.fn_engineering_checkpoint_transition_v1(
        p,'M10.2','REUSE_CAPABILITY_CUTOVER','DONE',e,'IG_M102_CP2_TRAIN',
        'M9.2 2/2 DONE and canonical function reused; negative missing version rejected');
  IF b#>>'{transition,status}'<>'APPLIED'
  THEN RAISE EXCEPTION 'M102_CP2_TRANSITION_FAILED'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=199 AND status='DONE')<>2
   OR (programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2')
       #>>'{current_checkpoint,checkpoint_code}')<>'SWITCH_ONLY_MIGRATION'
   OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
       AND manifest_sha256=h)
  THEN RAISE EXCEPTION 'M102_CP2_POSTSTATE_FAILED'; END IF;
END $cp2$;
