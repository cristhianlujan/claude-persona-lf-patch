-- LF | First governed update for an already registered candidate skill.
-- Scope: ONLY the existing ACTUALIZACION_SKILL_LF child opener. No new
-- runner, owner table, privileged role, execution, promotion or runtime write.
-- Historical 14/14 updates retain their original authority path.
-- The initial-registration path additionally requires the exact README
-- declaration, unique catalog path and COMPLETED LF Migration Merge Train run.
-- Apply ONLY through ACTUALIZACION_DB_LF / DB_WRITE_TRANSPORT / Merge Train.
BEGIN;

DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_skill_catalog_v1
       WHERE skill_code='SKILL_UPDATE_APPLY' AND status='READY'
         AND required_operation='ACTUALIZACION_SKILL_LF')
     OR NOT EXISTS (SELECT 1 FROM public.lf_router_governed_callers
       WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
         AND status='ACTIVE' AND operation_code='ACTUALIZACION_SKILL_LF')
     OR to_regprocedure('public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text)') IS NULL
  THEN RAISE EXCEPTION 'BLOCK_SKILL_INITIAL_OWNER_PRECONDITIONS'; END IF;
END $pre$;

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
  v_registration_count integer;
  v_owner_authority_kind text := 'HISTORICAL_COMPLETED_SKILL_UPDATE';
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
  IF v_hist_count=0 THEN
    -- First update only: establish ownership from the GOVERNED initial asset
    -- registration, not from a fabricated 14-step historical skill update.
    IF v_owner->>'declaration_kind' IS DISTINCT FROM 'REGISTERED_CANDIDATE'
      OR v_asset.estado_documental IS DISTINCT FROM 'CANDIDATO'
      OR v_asset.estado_operativo IS DISTINCT FROM 'READ_ONLY'
      OR v_asset.runtime_estado IS DISTINCT FROM 'CANDIDATE_READ_ONLY'
      OR v_asset.impacto_automatico IS DISTINCT FROM 'BLOQUEADO'
      OR v_asset.ruta_esperada IS DISTINCT FROM v_root||'/SKILL.md'
      OR v_asset.raw_payload->>'path' IS DISTINCT FROM v_asset.ruta_esperada
      OR v_asset.raw_payload->>'repository' IS DISTINCT FROM v_repo
      OR v_asset.raw_payload->>'source_kind' IS DISTINCT FROM 'GITHUB_MAIN'
      OR v_asset.raw_payload->>'asset_registration_only' IS DISTINCT FROM 'true'
      OR v_asset.metadata->>'asset_registration_mode'
         IS DISTINCT FROM 'EXISTING_GITHUB_SKILL_CANDIDATE'
      OR v_asset.metadata->>'runtime_binding_enabled' IS DISTINCT FROM 'false'
      OR v_asset.metadata->>'production_authorized' IS DISTINCT FROM 'false'
      OR v_asset.metadata->>'no_runtime_activation' IS DISTINCT FROM 'true'
      OR coalesce(v_asset.raw_payload->>'source_blob_sha1','') !~ '^[0-9a-f]{40}$'
      OR coalesce(v_asset.raw_payload->>'source_merge_sha','') !~ '^[0-9a-f]{40}$'
      OR v_asset.raw_payload->>'registered_by_execution_id'
         IS DISTINCT FROM v_asset.created_by_execution_id
      OR v_asset.metadata->>'governed_migration_execution_id'
         IS DISTINCT FROM v_asset.created_by_execution_id
      OR v_asset.created_by_execution_id IS NULL
      OR (SELECT count(*) FROM public.lf_activos a
           WHERE a.archived_at IS NULL AND a.ruta_esperada=v_asset.ruta_esperada)<>1
      OR EXISTS (SELECT 1 FROM public.lf_operation_execution e
           WHERE e.operation_code=v_op AND e.target_code=v_target)
    THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED'; END IF;

    SELECT count(*) INTO v_registration_count
    FROM public.lf_operation_execution e
    WHERE e.execution_id=v_asset.created_by_execution_id
      AND e.operation_code='ACTUALIZACION_DB_LF'
      AND e.target_type='MIGRATION'
      AND e.status='COMPLETED'
      AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
      AND e.manifest->>'producer'='lf-migration-merge-train'
      AND coalesce(e.manifest->>'pr','') ~ '^[0-9]+$'
      AND coalesce(e.manifest->>'train_run_id','') ~ '^[0-9]+$';
    IF v_registration_count<>1
    THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_INITIAL_REGISTRATION_NOT_VERIFIED'; END IF;
    v_owner_execution:=v_asset.created_by_execution_id;
    v_canonical_root:=v_root;
    v_owner_authority_kind:='GOVERNED_INITIAL_ASSET_REGISTRATION';
  ELSE
    IF v_root_count<>1 OR v_canonical_root IS DISTINCT FROM v_root
    THEN RAISE EXCEPTION 'SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED'; END IF;
  END IF;
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
        'owner_authority_kind',v_owner_authority_kind,
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
    'owner_authority_kind',v_owner_authority_kind,
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

-- Extension of the ALREADY governed 10..60 recorder, no second runner.
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
      AND target_type='SKILL'
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
     OR coalesce(v_child.manifest#>>'{owner_provenance,canonical_root_path}','')
           !~ '^skills/[a-z0-9_-]+$'
     OR v_child.manifest->>'target_root_path' IS DISTINCT FROM
           v_child.manifest#>>'{owner_provenance,canonical_root_path}'
     OR v_child.target_path NOT LIKE
           (v_child.manifest#>>'{owner_provenance,canonical_root_path}')||'/%'
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
      OR (p_evidence->>'skill_identity' IS DISTINCT FROM v_child.target_code
           AND p_evidence->>'skill_identity' IS DISTINCT FROM
               upper(split_part(v_child.manifest#>>'{owner_provenance,canonical_root_path}','/',2)))
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

REVOKE ALL ON FUNCTION public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text) TO service_role;

DO $post$
DECLARE v_source text;
BEGIN
  v_source:=pg_get_functiondef('public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text)'::regprocedure);
  IF position('SKILL_UPDATE_CHILD_INITIAL_REGISTRATION_NOT_VERIFIED' in v_source)=0
     OR position('HISTORICAL_COMPLETED_SKILL_UPDATE' in v_source)=0
     OR position('REGISTERED_CANDIDATE' in v_source)=0
  THEN RAISE EXCEPTION 'BLOCK_SKILL_INITIAL_OWNER_POSTWRITE_READBACK'; END IF;
END $post$;
COMMIT;
