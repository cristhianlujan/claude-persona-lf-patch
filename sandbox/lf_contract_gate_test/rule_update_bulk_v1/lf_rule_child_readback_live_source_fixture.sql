-- Current live source frozen solely for isolated PG17 test. Original MD5 85b22ffafeeb740d1c3ba403ac21190e
CREATE OR REPLACE FUNCTION public.lf_skill_rule_child_readback_v1(p_parent text, p_run text, p_child text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;
 v_code text; v_sha text; v_count integer; v_clean integer; v_names integer;
BEGIN
 IF coalesce(p_parent,'')='' OR coalesce(p_run,'')='' OR coalesce(p_child,'')='' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_READBACK_INPUT_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_invocation_v1 i
   WHERE i.skill_run_id=p_run AND i.skill_code='RULE_UPDATE_APPLY'
     AND i.parent_execution_id=p_parent AND i.child_execution_id=p_child
     AND i.status='COMPLETED') THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_INVOCATION_MISMATCH'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_child
   AND operation_code='ACTUALIZACION_REGLA_LF'
   AND target_type='REGLA'
   AND created_by_execution_id=p_parent;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_OPERATION_BINDING_INVALID'); END IF;
 IF e.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
    OR e.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM p_run THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_HANDOFF_MISMATCH'); END IF;
 IF e.status<>'COMPLETED' THEN
   RETURN jsonb_build_object('status','CHILD_IN_PROGRESS','child_execution_id',p_child,
     'effect_verified',false,'profile_execution_complete',false); END IF;
 IF e.manifest->>'candidate_write_verified' IS DISTINCT FROM 'true'
    OR e.manifest->>'rule_state' IS DISTINCT FROM 'CANDIDATO'
    OR e.manifest->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR coalesce(e.manifest->>'result_snapshot_sha256','') !~ '^[0-9a-f]{64}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_COMPLETION_UNATTESTED'); END IF;
 SELECT count(*),count(*) FILTER (WHERE status='PASS_CLEAN'),
        count(DISTINCT step_id) FILTER(WHERE step_id IN (
          'ekb_preflight','classify','existing_check','destination_validate',
          'candidate_write','readback','trace_close'))
 INTO v_count,v_clean,v_names
 FROM public.lf_operation_execution_steps WHERE execution_id=p_child;
 IF v_count<>7 OR v_clean<>7 OR v_names<>7 THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_REQUIRED_STEPS_NOT_CLEAN',
     'observed_steps',v_count,'clean_steps',v_clean); END IF;
 v_code:=e.target_code;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_code AND estado='CANDIDATO'
   AND pendiente_decision=true) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_STATE_DRIFT'); END IF;
 v_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_code);
 IF v_sha IS DISTINCT FROM e.manifest->>'result_snapshot_sha256' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT'); END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
   'parent_execution_id',p_parent,'child_execution_id',p_child,
   'skill_run_id',p_run,'operation_code','ACTUALIZACION_REGLA_LF',
   'rule_code',v_code,'rule_state','CANDIDATO','result_snapshot_sha256',v_sha,
   'canonical_readback',true,'required_steps_clean',7,
   'promotion_authorized',false,'profile_execution_complete',false,
   'next_action','CONTINUE_SAME_PARENT_PROFILE');
END
$function$;
