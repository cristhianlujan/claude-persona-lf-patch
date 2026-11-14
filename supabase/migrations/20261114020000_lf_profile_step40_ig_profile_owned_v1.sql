-- CANDIDATE ONLY, DO NOT APPLY TO LIVE DATABASE.
-- Router only selects profile+passes signed context; IG applicability belongs to step 40.
-- Existing 0/10/20/30/40/45/47/50/60/70/80 step schema is unchanged.
BEGIN;

DO $router_profile_ig_patch$
DECLARE
  v_def text;
  v_old text;
  v_new text;
  v_count integer;
BEGIN
  v_def:=pg_get_functiondef('public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure);
  IF md5(v_def)<>'f0ddcd722b945535dff348a563a6e6cd' THEN
    RAISE EXCEPTION 'STEP50_ROUTER_PREIMAGE_DRIFT';
  END IF;
  -- Eliminate Router's decision (not merely its output fields).
  v_old:=$old$  v_profile_task_intent:=upper(coalesce(p_stage1->>'accion',''));
  v_profile_ig_requirement:=case
    when v_channel='PRODUCTO'
      and v_profile_task_intent='READ_PRODUCT_DEFINITION'
      then 'NOT_REQUIRED_CANONICAL_READ'
    else 'REQUIRED_BY_TASK'
  end;

$old$;
  v_count:=(length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'STEP50_ROUTER_POLICY_ANCHOR_DRIFT:%',v_count; END IF;
  v_def:=replace(v_def,v_old,'');
  v_old:=$old$        'profile_task_intent',v_profile_task_intent,
        'input_governance_requirement',v_profile_ig_requirement,
$old$;
  v_count:=(length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'STEP50_ROUTER_BINDING_ANCHOR_DRIFT:%',v_count; END IF;
  v_def:=replace(v_def,v_old,'');
  EXECUTE v_def;
END;
$router_profile_ig_patch$;

-- Profile's existing input_validate step, not Router, owns this determination.
-- Direct INPUT_GOVERNANCE_EXECUTION_CONTRACT relation is the profile's skill binding.
-- Fail-safe: if bound, invoke the skill; never take a Router skip declaration on trust.
CREATE OR REPLACE FUNCTION public.lf_profile_input_governance_requirement_v1(p_handoff jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $profile_step40$
DECLARE
 v_request jsonb:=p_handoff->'semantic_request';
 v_profile text:=p_handoff->>'profile_code';
 v_valid jsonb;
 v_bound boolean;
BEGIN
 IF jsonb_typeof(v_request)<>'object' OR nullif(v_profile,'') IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_MISSING');
 END IF;
 v_valid:=public.lf_router_semantic_action_binding_validate_v1(v_request,v_profile,'PERFIL');
 IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_INVALID');
 END IF;
 SELECT EXISTS(
   SELECT 1 FROM public.lf_activo_relaciones r
   WHERE r.codigo_activo=v_profile
     AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
     AND r.relacion_tipo='GOBERNADO_POR'
 ) INTO v_bound;
 RETURN jsonb_build_object(
   'status',CASE WHEN v_bound THEN 'REQUIRED' ELSE 'NOT_REQUIRED' END,
   'blocking_code',NULL,
   'input_governance_requirement',CASE WHEN v_bound THEN 'REQUIRED_BY_PROFILE_SKILL' ELSE 'NOT_REQUIRED_PROFILE_SKILL_UNBOUND' END,
   'profile_task_intent','PROFILE_OWNS_STEP40',
   'reason',CASE WHEN v_bound THEN 'PROFILE_BOUND_IG_SKILL_USED_AT_STEP40' ELSE 'PROFILE_HAS_NO_IG_SKILL_BINDING' END
 );
END;
$profile_step40$;

DO $profile_downstream_patch$
DECLARE
 v_def text;
 v_old text;
 v_new text;
 v_count integer;
BEGIN
 v_def:=pg_get_functiondef('public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure);
 IF md5(v_def)<>'0241100cd73563329e4683457a7df1c0' THEN
   RAISE EXCEPTION 'STEP50_PROFILE_CONTEXT_SOURCE_DRIFT';
 END IF;
 v_old:=$old$  v_task_intent:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,profile_task_intent}',
    ''
  ));
  v_ig_requirement:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,input_governance_requirement}',
    ''
  ));$old$;
 v_new:=$new$  v_task_intent:=coalesce(public.lf_profile_input_governance_requirement_v1(p_handoff)->>'profile_task_intent','');
  v_ig_requirement:=coalesce(public.lf_profile_input_governance_requirement_v1(p_handoff)->>'input_governance_requirement','');$new$;
 v_count:=(length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
 IF v_count<>1 THEN RAISE EXCEPTION 'STEP50_CONTEXT_PROFILE_POLICY_ANCHOR_DRIFT:%',v_count; END IF;
 v_def:=replace(v_def,v_old,v_new);
 -- The existing screen-selection branch must still run for bound skill.
 v_def:=replace(v_def,
   $old$IF v_ig_requirement='REQUIRED_BY_TASK'$old$,
   $new$IF v_ig_requirement='REQUIRED_BY_PROFILE_SKILL'$new$);
 EXECUTE v_def;

 v_def:=pg_get_functiondef('public.lf_profile_execution_canonical_read_judge_v1(text)'::regprocedure);
 IF md5(v_def)<>'eb07c420fbbf6776e6a777d17ffe00da' THEN
   RAISE EXCEPTION 'STEP50_CANONICAL_JUDGE_SOURCE_DRIFT';
 END IF;
 v_old:=$old$       OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,profile_task_intent}'
            <>'READ_PRODUCT_DEFINITION'
       OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,input_governance_requirement}'
            <>'NOT_REQUIRED_CANONICAL_READ'$old$;
 v_new:=$new$       OR NOT EXISTS (
          SELECT 1 FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=e.execution_id AND s.step_id='input_validate'
            AND s.status='STEP_PASS_WITH_EVIDENCE'
       )$new$;
 v_count:=(length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
 IF v_count<>1 THEN RAISE EXCEPTION 'STEP50_CANONICAL_JUDGE_ROUTER_IG_ANCHOR_DRIFT:%',v_count; END IF;
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def;
END;
$profile_downstream_patch$;

-- No grants or extra gates; unchanged canonical writer. Train-only candidate.
COMMIT;
