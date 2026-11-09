-- LF G2: SKILL_UPDATE_APPLY handler/opener in the EXISTING profile skill invoker.
-- Source of truth: ACT-0001, lf_skill_catalog_v1, lf_skill_invoke_v1,
-- lf_router_governed_caller_route_v1, ACTUALIZACION_SKILL_LF (14 native steps).
-- This migration does not activate the skill or caller, write GitHub, update
-- asset bindings, alter Router/ACL for existing objects or create a profile RUN.
-- It only installs fail-closed functions. Subsequent admission requires G1/G3/G5.
DO $bootstrap_contract$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1
     WHERE skill_code='SKILL_UPDATE_APPLY'
       AND required_operation='ACTUALIZACION_SKILL_LF'
       AND handler_fn='lf_skill_h_skill_update_propose_v1'
       AND opener_fn='lf_skill_o_skill_update_v1'
       AND effect='WRITE_GOVERNED' AND status='DRAFT')
 OR NOT EXISTS(SELECT 1 FROM public.lf_router_governed_callers
     WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
       AND operation_code='ACTUALIZACION_SKILL_LF' AND status='DISABLED')
 THEN
  RAISE EXCEPTION 'SKILL_UPDATE_ADAPTER_REQUIRES_INACTIVE_BOOTSTRAP';
 END IF;
END $bootstrap_contract$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_skill_update_propose_v1(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $lf$
DECLARE
  v_code text := upper(btrim(coalesce(p_input->>'target_code','')));
  v_path text := btrim(coalesce(p_input->>'target_path',''));
BEGIN
  IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
    OR v_code !~ '^[A-Z][A-Z0-9_-]{3,159}$'
    OR v_path !~ '^skills/[a-z0-9_-]+(/[A-Za-z0-9_.-]+)+$'
    OR position('..' IN v_path)>0 OR position('//' IN v_path)>0
  THEN
    RAISE EXCEPTION 'SKILL_UPDATE_HANDLER_INVALID_TARGET';
  END IF;
  -- This handler is PROPOSE_ONLY and cannot declare the asset's owner.
  -- Exact owner binding is resolved server-side by the opener.
  RETURN jsonb_build_object(
    'target_code',v_code, 'target_path',v_path,
    'operacion_requerida','ACTUALIZACION_SKILL_LF',
    'escribe',false, 'owner_verification','DEFER_TO_GOVERNED_OPENER');
END
$lf$;

CREATE OR REPLACE FUNCTION public.lf_skill_o_skill_update_v1(
  p_child text, p_input jsonb, p_parent text,
  p_run text, p_request_sha text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public','extensions'
AS $lf$
DECLARE
  v_par public.lf_operation_execution%ROWTYPE;
  v_inv public.lf_skill_invocation_v1%ROWTYPE;
  v_asset public.lf_activos%ROWTYPE;
  v_step public.lf_operation_steps%ROWTYPE;
  v_binding public.lf_operation_step_judge_bindings%ROWTYPE;
  v_contract public.lf_operation_contracts%ROWTYPE;
  v_existing public.lf_operation_execution_steps%ROWTYPE;
  v_t jsonb;
  v_owner jsonb;
  v_c jsonb;
  v_g jsonb;
  v_r jsonb;
  v_res jsonb;
  v_ep jsonb;
  v_root text;
  v_canonical_root text;
  v_owner_execution text;
  v_hist_count integer;
  v_root_count integer;
  v_required_count integer;
  v_path text := btrim(coalesce(p_input->>'target_path',''));
  v_target text := upper(btrim(coalesce(p_input->>'target_code','')));
  v_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
  v_op constant text := 'ACTUALIZACION_SKILL_LF';
BEGIN
  IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
     OR v_target !~ '^[A-Z][A-Z0-9_-]{3,159}$'
     OR v_path !~ '^skills/[a-z0-9_-]+(/[A-Za-z0-9_.-]+)+$'
     OR position('..' IN v_path)>0 OR position('//' IN v_path)>0
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_TARGET_INVALID'; END IF;
  -- Refuse any call that did not originate at the existing governed profile
  -- invoker. _trusted is replaced by Edge after OIDC and exact GitHub readback.
  v_t := p_input->'_trusted';
  IF jsonb_typeof(v_t) IS DISTINCT FROM 'object'
     OR coalesce(v_t->>'main_sha','') !~ '^[0-9a-f]{40}$'
     OR coalesce(v_t->>'target_blob_sha','') !~ '^[0-9a-f]{40}$'
     OR jsonb_typeof(v_t->'caller') IS DISTINCT FROM 'object'
     OR coalesce(v_t->'caller'->>'method','') <>
          'GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1'
     OR coalesce(v_t->'caller'->>'repository','') <> v_repo
     OR coalesce(v_t->'caller'->>'run_id','') !~ '^[1-9][0-9]{4,19}$'
     OR coalesce(v_t->'caller'->>'workflow_sha','') !~ '^[0-9a-f]{40}$'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_SERVER_TRUST_MISSING'; END IF;

  SELECT * INTO v_par
  FROM public.lf_operation_execution WHERE execution_id=p_parent
    AND operation_code='EJECUCION_PERFIL_LF' AND status='IN_PROGRESS'
    AND target_type='PERFIL' FOR UPDATE;
  IF NOT FOUND OR v_par.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
    OR v_par.manifest->'router_profile_handoff'
       ->'router_authorization_receipt'->>'profile_execution_allowed'
       IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_PARENT_NOT_AUTHORIZED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code=v_par.target_code AND operation_code=v_op
      AND status='ACTIVE')
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_PROFILE_OPERATION_NOT_AUTHORIZED'; END IF;
  IF p_request_sha IS DISTINCT FROM v_par.request_sha256
    OR coalesce(p_run,'') !~ '^RUN-[A-Z0-9]{16,24}$'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_REQUEST_OR_RUN_MISMATCH'; END IF;
  SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
  WHERE skill_run_id=p_run AND skill_code='SKILL_UPDATE_APPLY'
    AND parent_execution_id=p_parent AND child_execution_id=p_child
    AND profile_code=v_par.target_code AND status='COMPLETED'
    AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_INVOCATION_UNBOUND'; END IF;

  SELECT * INTO v_asset FROM public.lf_activos
  WHERE codigo_activo=v_target AND tipo_activo='SKILL'
    AND archived_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_ASSET_NOT_CURRENT'; END IF;
  -- G1 owner: combine a canonical COMPLETED skill update (all active
  -- contract steps clean) with the README at the exact current GitHub main.
  -- No new owner registry; neither Drive history nor sandbox receipts authorize.
  v_owner := v_t->'github_owner';
  v_root := v_owner->>'root_path';
  IF jsonb_typeof(v_owner) IS DISTINCT FROM 'object'
    OR v_owner->>'asset_code' IS DISTINCT FROM v_target
    OR v_owner->>'main_sha' IS DISTINCT FROM v_t->>'main_sha'
    OR coalesce(v_owner->>'readme_blob_sha','') !~ '^[0-9a-f]{40}$'
    OR coalesce(v_root,'') !~ '^skills/[a-z0-9_-]+$'
    OR v_owner->>'readme_path' IS DISTINCT FROM v_root||'/README.md'
    OR v_path NOT LIKE v_root||'/%'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CURRENT_OWNER_PROOF_INVALID'; END IF;

  SELECT count(*) INTO v_required_count
    FROM public.lf_operation_step_contracts
    WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT';
  IF v_required_count<>14
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_STEP_CONTRACT_DRIFT:%',v_required_count; END IF;

  WITH verified_owner AS (
    SELECT e.execution_id,e.target_path
    FROM public.lf_operation_execution e
    JOIN public.lf_operation_execution_steps sr
      ON sr.execution_id=e.execution_id AND sr.step_id='skill_resolve'
    WHERE e.operation_code=v_op AND e.target_type='SKILL'
      AND e.target_code=v_target AND e.status='COMPLETED'
      AND sr.status='STEP_PASS_WITH_EVIDENCE'
      AND sr.evidence_payload->>'codigo_activo'=v_target
      AND sr.evidence_payload->>'repo_path'=e.target_path
      AND sr.evidence_payload->>'exact_skill_resolved'='true'
      AND (SELECT count(*) FROM public.lf_operation_execution_steps x
           WHERE x.execution_id=e.execution_id)=v_required_count
      AND (SELECT count(*) FROM public.lf_operation_execution_steps x
           WHERE x.execution_id=e.execution_id
             AND x.status='STEP_PASS_WITH_EVIDENCE')=v_required_count
      AND NOT EXISTS (
        SELECT 1 FROM public.lf_operation_step_contracts c
        LEFT JOIN public.lf_operation_execution_steps x
          ON x.execution_id=e.execution_id AND x.step_id=c.step_id
             AND x.step_order=c.step_order
        WHERE c.operation_code=v_op AND c.status='ACTIVE_ENFORCEMENT'
          AND x.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
      )
  )
  SELECT count(*),count(DISTINCT target_path),
         min(target_path),min(execution_id)
  INTO v_hist_count,v_root_count,v_canonical_root,v_owner_execution
  FROM verified_owner;
  IF v_hist_count<1 OR v_root_count<>1 OR v_canonical_root IS DISTINCT FROM v_root
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED'; END IF;
  -- Explicitly re-derive ACT-0001 receipt for the REGISTERED OIDC caller;
  -- no Router execution or direct profile dispatch is introduced.
  v_c := public.lf_skill_child_caller_manifest_v1('SKILL_UPDATE_APPLY');
  IF v_c->>'governed_caller_method' IS DISTINCT FROM v_t->'caller'->>'method'
    OR v_c->>'caller_repository' IS DISTINCT FROM v_repo
    OR v_c->>'caller_workflow_ref' IS DISTINCT FROM v_t->'caller'->>'workflow_ref'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CALLER_BINDING_MISMATCH'; END IF;
  v_g:=public.lf_router_governed_caller_route_v1(
    jsonb_build_object(
      'method',v_c->>'governed_caller_method',
      'repository',v_c->>'caller_repository',
      'workflow_ref',v_c->>'caller_workflow_ref',
      'run_id',v_t->'caller'->>'run_id',
      'workflow_sha',v_t->'caller'->>'workflow_sha'),
    v_target,v_path);
  v_r:=v_g->'router_result';
  IF v_g->>'status' IS DISTINCT FROM 'ROUTER_REDERIVED'
    OR v_r->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
    OR v_r->>'operation_code' IS DISTINCT FROM v_op
    OR v_r->>'action_code' IS DISTINCT FROM 'SKILL_UPDATE'
    OR v_g->>'semantic_receipt_sha256' !~ '^[0-9a-f]{64}$'
    OR v_g->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_ROUTER_REDERIVATION_DENIED:%',
    coalesce(v_g->>'blocking_code',v_r->>'status','UNKNOWN'); END IF;

  SELECT * INTO v_contract FROM public.lf_operation_contracts
  WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT';
  IF NOT FOUND OR (SELECT count(*) FROM public.lf_operation_contracts
    WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>1
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CONTRACT_NOT_EXACT'; END IF;
  SELECT * INTO v_step FROM public.lf_operation_steps
  WHERE operation_code=v_op AND step_id='init_execution' AND active=true;
  SELECT * INTO v_binding FROM public.lf_operation_step_judge_bindings
  WHERE operation_code=v_op AND step_id='init_execution'
    AND step_order=v_step.step_order AND status='ACTIVE_ENFORCEMENT';
  IF v_step.step_id IS DISTINCT FROM 'init_execution'
     OR v_binding.clean_result_value IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_INIT_GATE_INVALID'; END IF;

  v_res:=public.fn_lf_operation_reserve_execution_v1(
    p_child,v_op,'SKILL',v_target,
    'skill-child-v1:'||p_run,p_request_sha,p_parent,v_repo,v_path,
    jsonb_build_object(
      'contract_code',v_contract.contract_code,
      'contract_sha',v_contract.contract_sha,
      'profile_handoff',jsonb_build_object(
        'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
      'router','ACT-0001',
      'router_semantic_receipt_sha256',v_g->>'semantic_receipt_sha256',
      'router_governed_caller_code',v_g->>'caller_code',
      'initial_main_revision',v_t->>'main_sha',
      'initial_target_blob_sha',v_t->>'target_blob_sha',
      'owner_provenance',jsonb_build_object(
        'canonical_execution_id',v_owner_execution,
        'canonical_root_path',v_root,
        'source','public.lf_operation_execution+GitHub_MAIN_README',
        'readme_blob_sha',v_owner->>'readme_blob_sha'),
      'github_write_executed',false,'runtime_write_executed',false,
      'production_authorized',false,'automatic_runtime_promotion',false,
      'target_root_path',v_root) || v_c
  );
  IF v_res->>'execution_id' IS DISTINCT FROM p_child
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_RESERVATION_MISMATCH'; END IF;
  IF v_res->>'result'='REPLAY_EXISTING_EXECUTION' THEN
    SELECT * INTO v_existing FROM public.lf_operation_execution_steps
    WHERE execution_id=p_child AND step_id='init_execution'
      AND status=v_binding.clean_result_value;
    IF NOT FOUND THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_REPLAY_NOT_CLEAN'; END IF;
    RETURN v_res||jsonb_build_object('init_step','ALREADY_RECORDED_IDEMPOTENT','next_step','router');
  END IF;
  IF v_res->>'result' IS DISTINCT FROM 'RESERVED_NEW_EXECUTION'
  THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_RESERVATION_NOT_NEW'; END IF;

  v_ep:=jsonb_build_object(
    'execution_id_created',p_child,
    'execution_row_created',true,
    'target_code',v_target,'target_path',v_path,
    'operation_code',v_op,'target_type','SKILL',
    'source_revision',v_t->>'main_sha',
    'asset_owner_binding',v_asset.codigo_activo,
    'verified_owner_execution_id',v_owner_execution,
    'owner_readme_blob_sha',v_owner->>'readme_blob_sha',
    'router_semantic_receipt_sha256',v_g->>'semantic_receipt_sha256',
    'assertions_checked',jsonb_build_array('execution_row_created',
      'asset_current_owner_verified','router_rederived','parent_operation_active'),
    'hard_fails_checked','[]'::jsonb,
    'blocking_codes','[]'::jsonb,
    'step_result',v_binding.clean_result_value,
    'mini_judge_code',v_binding.judge_code,
    'mini_judge_result',v_binding.clean_result_value,
    'recorded_by_rpc','lf_skill_o_skill_update_v1');
  INSERT INTO public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,
      evidence_payload,notes,created_by_execution_id)
  VALUES(p_child,v_step.step_order,'init_execution',v_binding.clean_result_value,
      'supabase://public/lf_operation_execution/'||p_child,
      v_ep,'Governed skill update init: no GitHub or product write',p_parent);
  SELECT * INTO v_existing FROM public.lf_operation_execution_steps
  WHERE execution_id=p_child AND step_id='init_execution'
    AND status=v_binding.clean_result_value;
  IF NOT FOUND THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_INIT_READBACK_FAILED'; END IF;
  RETURN v_res||jsonb_build_object('init_step','RECORDED','next_step','router',
    'no_write_performed',true,'source_revision',v_t->>'main_sha');
END
$lf$;

-- The new functions are not publicly callable: only the existing invoker
-- (owned by postgres, SECURITY DEFINER) and the service-role transport can
-- use these after separately governed activation of the catalog+caller.
REVOKE ALL ON FUNCTION public.lf_skill_h_skill_update_propose_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_skill_h_skill_update_propose_v1(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text) TO service_role;

DO $readback$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1
    WHERE skill_code='SKILL_UPDATE_APPLY' AND status='DRAFT')
  OR NOT EXISTS(SELECT 1 FROM public.lf_router_governed_callers
    WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
    AND status='DISABLED')
  OR to_regprocedure('public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text)') IS NULL
  OR to_regprocedure('public.lf_skill_h_skill_update_propose_v1(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'SKILL_UPDATE_ADAPTER_POSTMIGRATION_READBACK_FAILED'; END IF;
END
$readback$;
