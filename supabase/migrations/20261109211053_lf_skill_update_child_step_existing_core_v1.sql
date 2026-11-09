-- LF | Skill-child continuation adaptor to EXISTING operation-neutral core.
-- Router ACT-0001 unchanged. No new workflow, no alternate executor.
-- The OIDC Edge transport derives the source/main+blob+caller; neither
-- service_role nor a PASS assertion passes through Router or profile text.
-- This first slice is expressly LIMITED TO STEPS 10..60. GitHub writes,
-- readback, semantic judge and terminal close must not use this adapter.
-- EKB: GOV-022 GOV-024 CI-014; issue #3724 child EXEC-SKILL-49797550002EE84C.
CREATE OR REPLACE FUNCTION public.lf_skill_update_child_step_v1(
  p_parent text, p_child text, p_step text,
  p_evidence_ref text, p_evidence jsonb, p_server_context jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public','extensions'
AS $skill_step$
DECLARE
  v_child public.lf_operation_execution%ROWTYPE;
  v_parent public.lf_operation_execution%ROWTYPE;
  v_step public.lf_operation_steps%ROWTYPE;
  v_binding public.lf_operation_step_judge_bindings%ROWTYPE;
  v_catalog public.lf_skill_catalog_v1%ROWTYPE;
  v_inv public.lf_skill_invocation_v1%ROWTYPE;
  v_caller public.lf_router_governed_callers%ROWTYPE;
  v_manifest jsonb;
  v_current text;
  v_blob text;
  v_owner jsonb;
  v_expected_plan_sha text;
  v_write_plan jsonb;
  v_failure text;
  v_result jsonb;
  v_source jsonb;
BEGIN
  IF coalesce(p_parent,'') !~ '^EXEC-PROFILE-GATE2-[A-Za-z0-9]{8,64}$'
    OR coalesce(p_child,'') !~ '^EXEC-SKILL-[A-Za-z0-9]{12,40}$'
    OR p_step NOT IN ('router','skill_resolve','baseline_read','change_scope',
                      'regression_plan','pre_write_execution_binding_gate')
    OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL
    OR length(p_evidence_ref)>1500
    OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
    OR length(p_evidence::text)>44000
    OR jsonb_typeof(p_server_context) IS DISTINCT FROM 'object'
  THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_REQUEST_INVALID','durable',false);
  END IF;
  IF p_evidence ?| array['server_assertions','server_hard_fails',
     'trust_validation','derived_result','derived_by_judge'] THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_CALLER_JUDGE_FIELDS_FORBIDDEN','durable',false);
  END IF;

  SELECT * INTO v_parent FROM public.lf_operation_execution
    WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
      AND target_type='PERFIL' AND status='IN_PROGRESS';
  SELECT * INTO v_child FROM public.lf_operation_execution
    WHERE execution_id=p_child AND operation_code='ACTUALIZACION_SKILL_LF'
      AND target_type='SKILL' AND target_code='ACT-0045'
      AND status='IN_PROGRESS' AND created_by_execution_id=p_parent
    FOR UPDATE;
  IF v_parent.execution_id IS NULL OR v_child.execution_id IS NULL
     OR v_child.request_sha256 IS DISTINCT FROM v_parent.request_sha256
     OR v_parent.manifest->>'read_only' IS DISTINCT FROM 'true'
     OR v_parent.manifest->>'no_write' IS DISTINCT FROM 'true'
     OR v_parent.manifest->>'no_promotion' IS DISTINCT FROM 'true'
     OR v_parent.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'
        IS DISTINCT FROM 'true'
     OR v_child.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
     OR v_child.manifest->>'router_governed_caller_code' IS DISTINCT FROM 'CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
     OR v_child.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR v_child.target_path NOT LIKE 'skills/profile_creator/%'
  THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_PARENT_CHILD_BINDING_INVALID','durable',false);
  END IF;
  SELECT * INTO v_catalog FROM public.lf_skill_catalog_v1
    WHERE skill_code='SKILL_UPDATE_APPLY' AND status='READY'
      AND required_operation='ACTUALIZACION_SKILL_LF'
      AND effect='WRITE_GOVERNED';
  SELECT * INTO v_caller FROM public.lf_router_governed_callers
    WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
      AND operation_code='ACTUALIZACION_SKILL_LF'
      AND status='ACTIVE';
  SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
    WHERE parent_execution_id=p_parent AND child_execution_id=p_child
      AND skill_code='SKILL_UPDATE_APPLY' AND status='COMPLETED';
  IF v_catalog.skill_code IS NULL OR v_caller.caller_code IS NULL
    OR v_inv.skill_run_id IS NULL OR v_inv.profile_code IS DISTINCT FROM v_parent.target_code
    OR v_child.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM v_inv.skill_run_id
    OR NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
      WHERE profile_code=v_parent.target_code AND operation_code='ACTUALIZACION_SKILL_LF'
        AND status='ACTIVE')
  THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_INVOCATION_AUTHORITY_INVALID','durable',false);
  END IF;

  -- This envelope exists ONLY because the exact GitHub Actions OIDC workload
  -- authenticated at the EXISTING Edge, and that Edge independently fetched
  -- github/heads/main, target blob and current README. The request's _trusted
  -- field is always discarded by the transport.
  v_current:=p_server_context->>'main_sha';
  v_blob:=p_server_context->>'target_blob_sha';
  v_owner:=p_server_context->'github_owner';
  IF coalesce(v_current,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(v_blob,'') !~ '^[0-9a-f]{40}$'
     OR v_blob IS DISTINCT FROM v_child.manifest->>'initial_target_blob_sha'
     OR coalesce(v_owner->>'readme_blob_sha','') IS DISTINCT FROM
           v_child.manifest#>>'{owner_provenance,readme_blob_sha}'
     OR v_owner->>'root_path' IS DISTINCT FROM
           v_child.manifest#>>'{owner_provenance,canonical_root_path}'
     OR v_owner->>'asset_code' IS DISTINCT FROM v_child.target_code
     OR v_owner->>'main_sha' IS DISTINCT FROM v_current
     OR p_server_context#>>'{caller,method}' IS DISTINCT FROM v_caller.caller_method
     OR p_server_context#>>'{caller,repository}' IS DISTINCT FROM v_caller.repository
     OR p_server_context#>>'{caller,workflow_ref}' IS DISTINCT FROM v_caller.workflow_ref
     OR coalesce(p_server_context#>>'{caller,workflow_sha}','') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_server_context#>>'{caller,run_id}','') !~ '^[1-9][0-9]{4,19}$'
  THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_SERVER_CONTEXT_OR_DRIFT_INVALID','durable',false);
  END IF;

  SELECT * INTO v_step FROM public.lf_operation_steps
    WHERE operation_code='ACTUALIZACION_SKILL_LF'
      AND step_id=p_step AND active IS TRUE;
  SELECT * INTO v_binding FROM public.lf_operation_step_judge_bindings
    WHERE operation_code='ACTUALIZACION_SKILL_LF'
      AND step_id=p_step AND step_order=v_step.step_order
      AND status='ACTIVE_ENFORCEMENT';
  IF v_step.step_id IS NULL OR v_binding.step_id IS NULL
    OR NOT EXISTS(SELECT 1 FROM public.lf_operation_step_contracts c
      WHERE c.operation_code='ACTUALIZACION_SKILL_LF' AND c.step_id=p_step
        AND c.step_order=v_step.step_order AND c.status='ACTIVE_ENFORCEMENT')
  THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_ACTIVE_CONTRACT_MISSING','durable',false);
  END IF;
  IF jsonb_typeof(p_evidence->'blocking_codes') IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_evidence->'blocking_codes') <> 0 THEN
    RETURN jsonb_build_object('outcome','BLOCKED',
      'code','SKILL_UPDATE_STEP_BLOCKING_CODES_NOT_CLEAN','durable',false);
  END IF;
  -- The first 6 steps are a bounded specification/pre-write gate.
  -- Check material evidence, not just the presence of a key or caller PASS.
  IF p_step='router' THEN
    IF p_evidence->>'action' IS DISTINCT FROM 'SKILL_UPDATE'
      OR p_evidence->>'router_read' IS DISTINCT FROM
        v_child.manifest->>'router_semantic_receipt_sha256'
    THEN v_failure:='SKILL_UPDATE_ROUTER_RECEIPT_MISMATCH'; END IF;
  ELSIF p_step='skill_resolve' THEN
    IF p_evidence->>'codigo_activo' IS DISTINCT FROM v_child.target_code
      OR p_evidence->>'repo_path' IS DISTINCT FROM
         v_child.manifest#>>'{owner_provenance,canonical_root_path}'
      OR p_evidence->>'exact_skill_resolved' IS DISTINCT FROM 'true'
      OR p_evidence->>'skill_identity' IS DISTINCT FROM 'PROFILE_CREATOR'
    THEN v_failure:='SKILL_UPDATE_SKILL_RESOLVE_MISMATCH'; END IF;
  ELSIF p_step='baseline_read' THEN
    IF p_evidence->>'baseline_revision' IS DISTINCT FROM
         v_child.manifest->>'initial_main_revision'
      OR jsonb_typeof(p_evidence->'baseline_files') IS DISTINCT FROM 'array'
      OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(
        coalesce(p_evidence->'baseline_files','[]'::jsonb)) f
        WHERE f->>'path'=v_child.target_path
          AND f->>'blob_sha'=v_child.manifest->>'initial_target_blob_sha')
      OR nullif(btrim(coalesce(p_evidence->>'before_evidence','')),'') IS NULL
    THEN v_failure:='SKILL_UPDATE_BASELINE_READ_NOT_BOUND'; END IF;
  ELSIF p_step='change_scope' THEN
    IF length(btrim(coalesce(p_evidence->>'defect','')))<20
      OR length(btrim(coalesce(p_evidence->>'root_cause','')))<20
      OR jsonb_typeof(p_evidence->'minimal_patch_scope') IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_evidence->'minimal_patch_scope')<>1
      OR p_evidence->'minimal_patch_scope'->>0 IS DISTINCT FROM v_child.target_path
      OR jsonb_typeof(p_evidence->'preserved_constraints') IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_evidence->'preserved_constraints')<2
      OR length(btrim(coalesce(p_evidence->>'evidence_ceiling','')))<12
    THEN v_failure:='SKILL_UPDATE_CHANGE_SCOPE_UNSUPPORTED'; END IF;
  ELSIF p_step='regression_plan' THEN
    IF jsonb_typeof(p_evidence->'positive_cases') IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_evidence->'positive_cases')<1
      OR jsonb_typeof(p_evidence->'negative_cases') IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_evidence->'negative_cases')<2
      OR jsonb_typeof(p_evidence->'adversarial_cases') IS DISTINCT FROM 'array'
      OR jsonb_array_length(p_evidence->'adversarial_cases')<2
      OR length(btrim(coalesce(p_evidence->>'holdout','')))<12
    THEN v_failure:='SKILL_UPDATE_REGRESSION_PLAN_INCOMPLETE'; END IF;
  ELSIF p_step='pre_write_execution_binding_gate' THEN
    v_write_plan:=p_evidence->'write_plan';
    IF p_evidence->>'execution_id' IS DISTINCT FROM p_child
      OR p_evidence->>'target_code' IS DISTINCT FROM v_child.target_code
      OR p_evidence->>'target_path' IS DISTINCT FROM v_child.target_path
      OR p_evidence->>'pre_write_gate_passed' IS DISTINCT FROM 'true'
      OR coalesce(v_current,'') !~ '^[0-9a-f]{40}$'
      OR jsonb_typeof(v_write_plan) IS DISTINCT FROM 'array'
      OR jsonb_array_length(v_write_plan)<>1
      OR v_write_plan->0->>'path' IS DISTINCT FROM v_child.target_path
      OR coalesce(v_write_plan->0->>'content_sha256','') !~ '^[0-9a-f]{64}$'
      OR p_evidence->>'bound_revision' IS DISTINCT FROM v_current
      OR p_evidence->>'source_blob_sha' IS DISTINCT FROM v_blob
      OR p_evidence->>'write_plan_hash' IS DISTINCT FROM
         encode(extensions.digest(convert_to(v_write_plan::text,'UTF8'),'sha256'),'hex')
    THEN v_failure:='SKILL_UPDATE_PREWRITE_BINDING_NOT_PROVEN'; END IF;
  END IF;
  IF v_failure IS NOT NULL THEN
    RETURN jsonb_build_object('outcome','BLOCKED','code',v_failure,'durable',false);
  END IF;

  -- Do not trust caller assertions. The existing recorder and active judge
  -- always derive the status, enforce order and perform persistent readback.
  v_result:=public.lf_record_operation_step_core_v1(
     p_child,p_step,p_evidence_ref,p_evidence,p_parent,
     'ACTUALIZACION_SKILL_LF','SKILL',
     'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
     jsonb_build_object(
        'valid',true,
        'source','OIDC_EDGE_EXACT_GITHUB_MAIN_AND_BLOB',
        'server_assertions','[]'::jsonb,
        'server_hard_fails','[]'::jsonb,
        'current_main_sha',v_current,
        'verified_target_blob_sha',v_blob),
     false,'lf_skill_update_child_step_v1'
  );

  -- The gate records a refreshed main revision if unrelated commits moved main
  -- but the source target blob and owner declaration have NOT changed.
  -- It never writes the file; the actual GitHub writer is a separate gate.
  IF p_step='pre_write_execution_binding_gate'
     AND v_result->>'outcome'='STEP_RECORDED'
     AND v_result->>'status'=v_binding.clean_result_value THEN
    UPDATE public.lf_operation_execution
       SET manifest=manifest||jsonb_build_object(
           'pre_write_bound_main_revision',v_current,
           'pre_write_bound_target_blob_sha',v_blob,
           'pre_write_bound_write_plan_sha256',p_evidence->>'write_plan_hash',
           'pre_write_readback_source','EXISTING_OIDC_EDGE_GITHUB_MAIN')
    WHERE execution_id=p_child;
  END IF;
  RETURN v_result || jsonb_build_object('no_file_write',true,
    'transport','EXISTING_PROFILE_OIDC_EDGE',
    'step_writer','lf_record_operation_step_core_v1');
END
$skill_step$;

REVOKE ALL ON FUNCTION public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb) TO service_role;

DO $skill_step_readback$
BEGIN
  IF to_regprocedure('public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb)') IS NULL
    OR NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1
      WHERE skill_code='SKILL_UPDATE_APPLY' AND required_operation='ACTUALIZACION_SKILL_LF'
        AND status='READY')
    OR NOT EXISTS(SELECT 1 FROM public.lf_router_governed_callers
      WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1' AND status='ACTIVE')
  THEN
    RAISE EXCEPTION 'LF_SKILL_STEP_INTEGRATION_NOT_READY';
  END IF;
END
$skill_step_readback$;
