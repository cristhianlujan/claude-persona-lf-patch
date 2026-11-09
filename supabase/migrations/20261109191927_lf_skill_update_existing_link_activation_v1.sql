-- LF | Activation of the EXISTING governed skill update link (G2+G3).
-- User-approved repair scope: Router ACT-0001 -> existing Reparador ->
-- lf_skill_invoke_v1 -> ACTUALIZACION_SKILL_LF child. NO new runner/dispatcher.
-- Activation must remain fail-closed: this does NOT execute a skill,
-- create an execution, write a skill/profile file or authorize production.
--
-- Evidence at exact source main e421d244815f25ec76157bb6bd9aa10b6212f926:
-- PR #3732 inactive catalog/caller, PR #3736 child handler+opener;
-- PR #3735 Edge source deployed v67 and exact-main readback,
-- Deno 49/49 and PG17 9/9. Source and contract currentness must be
-- reverified by LF Migration Merge Train before this migration is applied.
-- Current ordinary profile-update request still follows PROFILE_UPDATE_APPLY:
-- do not bypass its allowlist using an unrelated request.
DO $lf_skill_update_activate$
DECLARE
  v_current public.lf_skill_catalog_v1%ROWTYPE;
  v_caller public.lf_router_governed_callers%ROWTYPE;
  v_actor constant text := 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF';
  v_skill constant text := 'SKILL_UPDATE_APPLY';
  v_code constant text := 'ACT-0045';
  v_op constant text := 'ACTUALIZACION_SKILL_LF';
  v_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
  v_method constant text := 'GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1';
  v_ref constant text := 'cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main';
  v_historical_clean integer;
BEGIN
  SELECT * INTO v_current FROM public.lf_skill_catalog_v1
  WHERE skill_code=v_skill FOR UPDATE;
  SELECT * INTO v_caller FROM public.lf_router_governed_callers
  WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1' FOR UPDATE;
  IF v_current.status IS DISTINCT FROM 'DRAFT'
     OR v_current.required_operation IS DISTINCT FROM v_op
     OR v_current.effect IS DISTINCT FROM 'WRITE_GOVERNED'
     OR v_current.handler_fn IS DISTINCT FROM 'lf_skill_h_skill_update_propose_v1'
     OR v_current.opener_fn IS DISTINCT FROM 'lf_skill_o_skill_update_v1'
     OR v_current.input_required IS DISTINCT FROM ARRAY['target_code','target_path']::text[]
     OR v_current.child_caller->>'method' IS DISTINCT FROM v_method
     OR v_current.child_caller->>'repository' IS DISTINCT FROM v_repo
     OR v_current.child_caller->>'workflow_ref' IS DISTINCT FROM v_ref
     OR v_caller.status IS DISTINCT FROM 'DISABLED'
     OR v_caller.caller_method IS DISTINCT FROM v_method
     OR v_caller.repository IS DISTINCT FROM v_repo
     OR v_caller.workflow_ref IS DISTINCT FROM v_ref
     OR v_caller.asset_type IS DISTINCT FROM 'SKILL'
     OR v_caller.action_code IS DISTINCT FROM 'SKILL_UPDATE'
     OR v_caller.operation_code IS DISTINCT FROM v_op
  THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_BINDING_DRIFT'; END IF;

  IF to_regprocedure('public.lf_skill_invoke_v1(text,text,jsonb)') IS NULL
    OR to_regprocedure('public.lf_skill_h_skill_update_propose_v1(jsonb)') IS NULL
    OR to_regprocedure('public.lf_skill_o_skill_update_v1(text,jsonb,text,text,text)') IS NULL
    OR to_regprocedure('public.lf_router_governed_caller_route_v1(jsonb,text,text)') IS NULL
  THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_RUNTIME_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_write_authority_v1
     WHERE profile_code=v_actor AND operation_code=v_op AND status='ACTIVE'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
     WHERE asset_type='SKILL' AND action_code='SKILL_UPDATE'
       AND operation_code=v_op AND status='ACTIVE' AND write_allowed IS TRUE
  ) OR (SELECT count(*) FROM public.lf_operation_step_contracts
        WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')<>14
  THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_AUTHORITY_OR_STEPS_MISSING'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.lf_activos
    WHERE codigo_activo=v_code AND tipo_activo='SKILL' AND archived_at IS NULL
      AND estado_operativo='APROBADO')
  THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_CANONICAL_ASSET_NOT_CURRENT'; END IF;
  SELECT count(*) INTO v_historical_clean FROM public.lf_operation_execution e
  WHERE e.operation_code=v_op AND e.target_code=v_code AND e.target_type='SKILL'
    AND e.target_path='skills/profile_creator' AND e.status='COMPLETED'
    AND (SELECT count(*) FROM public.lf_operation_execution_steps st
         WHERE st.execution_id=e.execution_id)=14
    AND (SELECT count(*) FROM public.lf_operation_execution_steps st
         WHERE st.execution_id=e.execution_id
           AND st.status='STEP_PASS_WITH_EVIDENCE')=14
    AND EXISTS (
      SELECT 1 FROM public.lf_operation_execution_steps sr
      WHERE sr.execution_id=e.execution_id AND sr.step_id='skill_resolve'
        AND sr.status='STEP_PASS_WITH_EVIDENCE'
        AND sr.evidence_payload->>'codigo_activo'=v_code
        AND sr.evidence_payload->>'repo_path'='skills/profile_creator'
        AND sr.evidence_payload->>'exact_skill_resolved'='true'
    );
  IF v_historical_clean<1
  THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_CANONICAL_OWNER_NOT_EVIDENCED'; END IF;

  -- This is only a register-state transition. Real file writes require a
  -- NEW child 0->60 proof on the exact current source HEAD; historical 14/14
  -- is NOT an authorization to reuse old pre-write evidence.
  UPDATE public.lf_skill_catalog_v1 SET status='READY'
    WHERE skill_code=v_skill AND status='DRAFT';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_SKILL_WRITE_FAILED'; END IF;
  UPDATE public.lf_router_governed_callers SET status='ACTIVE'
    WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1' AND status='DISABLED';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_CALLER_WRITE_FAILED'; END IF;

  IF NOT EXISTS (
     SELECT 1 FROM public.lf_skill_catalog_v1
       WHERE skill_code=v_skill AND status='READY'
         AND required_operation=v_op AND effect='WRITE_GOVERNED'
  ) OR NOT EXISTS (
     SELECT 1 FROM public.lf_router_governed_callers
       WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1'
         AND status='ACTIVE' AND operation_code=v_op
  ) THEN RAISE EXCEPTION 'LF_SKILL_UPDATE_ACTIVATION_READBACK_FAILED'; END IF;
END
$lf_skill_update_activate$;
