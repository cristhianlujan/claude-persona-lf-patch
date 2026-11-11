-- LF #3779 | Repair existing RULE_UPDATE_APPLY child readback.
-- Do not create tables or weaken candidate checks; admin remains state-preserving.
BEGIN;
DO $source_guard$
BEGIN
 IF md5(pg_get_functiondef('public.lf_skill_rule_child_readback_v1(text,text,text)'::regprocedure)) <>
    '85b22ffafeeb740d1c3ba403ac21190e' THEN
   RAISE EXCEPTION 'BLOCK_RULE_CHILD_READBACK_BASELINE_DRIFT';
 END IF;
END $source_guard$;

CREATE OR REPLACE FUNCTION public.lf_skill_rule_child_readback_v1(p_parent text, p_run text, p_child text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;
 v_code text; v_sha text; v_count integer; v_clean integer; v_names integer;
 v_hist jsonb; v_expected text; v_kind text; v_current jsonb; v_result jsonb;
 v_origin jsonb; v_fields jsonb;
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
 SELECT to_jsonb(r) INTO v_current FROM lf_ops.reglas r WHERE r.codigo=v_code;
 IF v_current IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_RULE_MISSING'); END IF;
 SELECT st.evidence_payload->'rule_update_history_v1' INTO v_hist
 FROM public.lf_operation_execution_steps st
 WHERE st.execution_id=p_child AND st.step_id='readback'
   AND st.status='PASS_CLEAN';
 v_kind:=coalesce(v_hist->>'change_kind','LEGACY_DOCUMENTARY');
 v_origin:=v_hist->'source_row';
 v_result:=v_hist->'result_row';
 v_fields:=v_hist->'changed_fields';
 IF v_kind='ADMINISTRATIVE_ONLY' THEN
   v_expected:=v_origin->>'estado';
   IF v_expected NOT IN ('CANDIDATO','VIGENTE')
   OR v_hist->>'schema_version'<>'LF_RULE_UPDATE_HISTORY_V1'
   OR v_hist->>'rule_code' IS DISTINCT FROM v_code
   OR v_result IS DISTINCT FROM v_current
   OR v_result->>'estado' IS DISTINCT FROM v_expected
   OR e.manifest->>'rule_state' IS DISTINCT FROM v_expected
   OR jsonb_typeof(v_fields) IS DISTINCT FROM 'object'
   OR (SELECT count(*) FROM jsonb_object_keys(v_fields)) NOT BETWEEN 1 AND 2
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_fields) k(field)
       WHERE k.field NOT IN ('owner_name','created_by'))
   OR (v_result-'created_at'-'updated_at'-'owner_name'-'created_by')
      IS DISTINCT FROM
      (v_origin-'created_at'-'updated_at'-'owner_name'-'created_by')
   THEN
     RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_ADMIN_HISTORY_OR_STATE_MISMATCH');
   END IF;
 ELSE
   v_expected:='CANDIDATO';
   IF v_kind NOT IN ('LEGACY_DOCUMENTARY','DOCUMENTARY_ONLY','FUNCTIONAL_CANDIDATE')
   OR v_current->>'estado' IS DISTINCT FROM 'CANDIDATO'
   OR v_current->>'pendiente_decision' IS DISTINCT FROM 'true'
   OR e.manifest->>'rule_state' IS DISTINCT FROM 'CANDIDATO'
   OR (v_hist IS NOT NULL AND (
     v_hist->>'schema_version'<>'LF_RULE_UPDATE_HISTORY_V1'
     OR v_hist->>'rule_code' IS DISTINCT FROM v_code
     OR v_result IS DISTINCT FROM v_current))
   THEN
     RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_STATE_DRIFT');
   END IF;
 END IF;
 v_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_code);
 IF v_sha IS DISTINCT FROM e.manifest->>'result_snapshot_sha256' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT'); END IF;
 IF v_hist IS NOT NULL AND (
     v_hist->>'result_snapshot_sha256' IS DISTINCT FROM v_sha
     OR v_hist->>'source_snapshot_sha256' IS DISTINCT FROM
       encode(extensions.digest(convert_to(
         (v_origin-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
     OR v_sha IS DISTINCT FROM
       encode(extensions.digest(convert_to(
         (v_result-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
     OR v_hist->>'parent_execution_id' IS DISTINCT FROM p_parent
     OR v_hist->>'child_execution_id' IS DISTINCT FROM p_child
 ) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_HISTORY_SHA_OR_BINDING_INVALID');
 END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
   'parent_execution_id',p_parent,'child_execution_id',p_child,
   'skill_run_id',p_run,'operation_code','ACTUALIZACION_REGLA_LF',
   'rule_code',v_code,'rule_state',v_expected,'result_snapshot_sha256',v_sha,
   'canonical_readback',true,'required_steps_clean',7,
   'promotion_authorized',false,'profile_execution_complete',false,
   'next_action','CONTINUE_SAME_PARENT_PROFILE');
END
$function$;

DO $verify$
BEGIN
 IF position('RULE_CHILD_ADMIN_HISTORY_OR_STATE_MISMATCH' in
   pg_get_functiondef('public.lf_skill_rule_child_readback_v1(text,text,text)'::regprocedure))=0 THEN
 RAISE EXCEPTION 'BLOCK_RULE_READBACK_GUARD_NOT_INSTALLED'; END IF;
END $verify$;
COMMIT;
