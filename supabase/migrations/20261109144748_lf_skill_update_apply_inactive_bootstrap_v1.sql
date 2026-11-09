-- LF | Skill update binding: disabled-by-default bootstrap.
-- APPROVED SCOPE 2026-11-09: existing ACT-0001 -> Reparador -> lf_skill_invoke_v1.
-- LF Migration Merge Train is the sole database-apply path.
-- No Router code, profile source, ACL, EXECUTION_RUN, write, model or prod promotion.
--
-- IMPORTANT: intentionally NOT READY / NOT ACTIVE.
-- The skill handler/opener, exact GitHub owner currentness, governed skill-update
-- run/step recorder, exact OIDC/Edge path & parent profile allowlist must be
-- separately validated BEFORE a future, separately governed activation.
-- See issue #3724 (G1-G5) and EKB INPUT GOVERNANCE LF V1.4.

DO $lf_skill_update_bootstrap$
DECLARE
  v_skill constant text := 'SKILL_UPDATE_APPLY';
  v_method constant text := 'GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1';
  v_ref constant text :=
    'cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main';
  v_callercode constant text := 'CALLER-GHA-NATIVE-SKILL-UPDATE-V1';
  v_skill_row public.lf_skill_catalog_v1%rowtype;
  v_caller_row public.lf_router_governed_callers%rowtype;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='ACTUALIZACION_SKILL_LF'
      AND applies_to_asset_type='SKILL'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'LF_SKILL_UPDATE_OPERATION_NOT_OPERATIONAL';
  END IF;
  IF (SELECT count(*) FROM public.lf_router_action_registry
      WHERE asset_type='SKILL' AND action_code='SKILL_UPDATE'
        AND operation_code='ACTUALIZACION_SKILL_LF' AND status='ACTIVE'
        AND write_allowed IS TRUE)<>1
  THEN
    RAISE EXCEPTION 'LF_SKILL_UPDATE_ROUTER_ACTION_NOT_EXACT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND operation_code='ACTUALIZACION_SKILL_LF' AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'LF_SKILL_UPDATE_REPARADOR_OPERATION_NOT_AUTHORIZED';
  END IF;

  -- No migration ever upgrades a pre-existing row, including a DRAFT one:
  -- an unexpected row is a source-drift conflict requiring reconciliation.
  IF EXISTS (SELECT 1 FROM public.lf_skill_catalog_v1
              WHERE skill_code=v_skill)
     OR EXISTS (SELECT 1 FROM public.lf_router_governed_callers
                WHERE caller_code=v_callercode OR caller_method=v_method)
  THEN
    RAISE EXCEPTION 'LF_SKILL_UPDATE_BOOTSTRAP_IDENTITY_CONFLICT';
  END IF;

  INSERT INTO public.lf_skill_catalog_v1(
    skill_code,description,required_operation,handler_fn,effect,
    input_required,status,opener_fn,child_caller)
  VALUES (
    v_skill,
    'Perfil propietario: actualizacion gobernada de skills LF, sin Router alternativo. BOOTSTRAP INACTIVO; faltan owner binding, handler, opener, Edge, pruebas y gate prewrite.',
    'ACTUALIZACION_SKILL_LF','lf_skill_h_skill_update_propose_v1','WRITE_GOVERNED',
    ARRAY['target_code','target_path']::text[],'DRAFT',
    'lf_skill_o_skill_update_v1',
    jsonb_build_object(
      'method',v_method,
      'repository','cristhianlujan/claude-persona-lf-patch',
      'workflow_ref',v_ref)
  );

  INSERT INTO public.lf_router_governed_callers(
    caller_code,caller_method,repository,workflow_ref,
    asset_type,action_code,operation_code,literal_template,status,notes)
  VALUES (
    v_callercode,v_method,'cristhianlujan/claude-persona-lf-patch',
    v_ref,'SKILL','SKILL_UPDATE','ACTUALIZACION_SKILL_LF',
    'Actualizar skill {target}', 'DISABLED',
    'Bootstrap solamente. Reutiliza OIDC del transporte de perfil; Router permanece ACT-0001. No activar hasta comprobacion G1-G5 y pre-write de operacion hija.'
  );

  SELECT * INTO v_skill_row FROM public.lf_skill_catalog_v1
  WHERE skill_code=v_skill;
  SELECT * INTO v_caller_row FROM public.lf_router_governed_callers
  WHERE caller_code=v_callercode;

  IF v_skill_row.skill_code IS DISTINCT FROM v_skill
     OR v_skill_row.status IS DISTINCT FROM 'DRAFT'
     OR v_skill_row.required_operation IS DISTINCT FROM 'ACTUALIZACION_SKILL_LF'
     OR v_skill_row.effect IS DISTINCT FROM 'WRITE_GOVERNED'
     OR v_caller_row.caller_method IS DISTINCT FROM v_method
     OR v_caller_row.operation_code IS DISTINCT FROM 'ACTUALIZACION_SKILL_LF'
     OR v_caller_row.status IS DISTINCT FROM 'DISABLED'
  THEN
    RAISE EXCEPTION 'LF_SKILL_UPDATE_BOOTSTRAP_READBACK_FAILED';
  END IF;
END
$lf_skill_update_bootstrap$;
