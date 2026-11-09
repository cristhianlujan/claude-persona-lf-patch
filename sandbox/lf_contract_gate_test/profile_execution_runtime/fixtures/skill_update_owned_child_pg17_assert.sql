-- ISOLATED PG17 tests, never execute against LF or live Supabase.
DO $test$
DECLARE
  v_input jsonb;
  v_result jsonb;
  v_child constant text := 'EXEC-SKILL-FIXTURE-TEST';
  v_parent constant text := 'EXEC-PROFILE-GATE2-FIXTURE';
  v_run constant text := 'RUN-ABCDEF1234567890ABCD';
  v_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
  v_path constant text := 'skills/profile_creator/validators/compare_s26_profile_evolution_v1.py';
BEGIN
  v_input:=jsonb_build_object(
    'target_code','ACT-0045','target_path',v_path,
    '_trusted',jsonb_build_object(
      'main_sha',repeat('a',40),
      'target_blob_sha',repeat('b',40),
      'caller',jsonb_build_object(
        'method','GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1',
        'repository',v_repo,
        'run_id','1234567890','workflow_sha',repeat('d',40),
        'workflow_ref',v_repo||'/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main'),
      'github_owner',jsonb_build_object(
        'asset_code','ACT-0045',
        'root_path','skills/profile_creator',
        'readme_path','skills/profile_creator/README.md',
        'readme_blob_sha',repeat('e',40),
        'main_sha',repeat('a',40))));

  v_result:=public.lf_skill_h_skill_update_propose_v1(v_input);
  IF v_result->>'escribe' IS DISTINCT FROM 'false'
    OR v_result->>'operacion_requerida' IS DISTINCT FROM 'ACTUALIZACION_SKILL_LF'
  THEN RAISE EXCEPTION 'FAIL_HANDLER_PROPOSE_ONLY'; END IF;
  RAISE NOTICE 'PASS_HANDLER_PROPOSE_ONLY';
  BEGIN
    PERFORM public.lf_skill_h_skill_update_propose_v1(
      jsonb_build_object('target_code','ACT-0045',
        'target_path','skills/profile_creator/../evil.py'));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_HANDLER_INVALID_TARGET%'
    THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS_HANDLER_TRAVERSAL_BLOCK';

  INSERT INTO public.lf_skill_invocation_v1 VALUES (
    v_run,'SKILL_UPDATE_APPLY',v_parent,v_child,
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','COMPLETED',
    encode(extensions.digest(convert_to(v_input::text,'UTF8'),'sha256'),'hex'));

  -- G1 is deliberately unresolved: canonical asset carries only Drive history.
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(
      v_child,v_input,v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_RATIFIED%'
    THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_child)
  THEN RAISE EXCEPTION 'FAIL_NO_CHILD_BEFORE_OWNER'; END IF;
  RAISE NOTICE 'PASS_UNRATIFIED_OWNER_BLOCKS';

  INSERT INTO public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,manifest,
    request_sha256,created_by_execution_id) VALUES(
    'EXEC-SKILL-G1-CURRENT','ACTUALIZACION_SKILL_LF','SKILL',
    'ACT-0045','COMPLETED','{}',repeat('a',64),'TEST');
  UPDATE public.lf_activos SET metadata=jsonb_build_object(
    'github_owner_binding',jsonb_build_object(
      'schema_version','LF_SKILL_GITHUB_OWNER_BINDING_V1',
      'status','CURRENT_VERIFIED','repository',v_repo,
      'root_path','skills/profile_creator',
      'approval_execution_id','EXEC-SKILL-G1-CURRENT',
      'receipt_ref','supabase://public/lf_operation_execution/EXEC-SKILL-G1-CURRENT'))
    WHERE codigo_activo='ACT-0045';

  -- Even with a synthetic approved owner, caller remains disabled.
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(
      v_child,v_input,v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_ROUTER_REDERIVATION_DENIED%'
    THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_child)
  THEN RAISE EXCEPTION 'FAIL_NO_CHILD_BEFORE_CALLER'; END IF;
  RAISE NOTICE 'PASS_DISABLED_CALLER_BLOCKS';

  UPDATE public.lf_router_governed_callers SET status='ACTIVE'
    WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1';
  -- Caller cannot fake a service-role trust envelope while keeping original
  -- invocation hash.
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(
      v_child,
      jsonb_set(v_input,'{_trusted,caller,method}','"FORGED"'::jsonb),
      v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_SERVER_TRUST_MISSING%'
    THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS_FORGED_CALLER_BLOCKS';

  -- Synthetic positive only: verifies no product write and exactly one
  -- child init row under already-satisfied stubs. This is NOT live authority.
  v_result:=public.lf_skill_o_skill_update_v1(
    v_child,v_input,v_parent,v_run,repeat('a',64));
  IF v_result->>'init_step' IS DISTINCT FROM 'RECORDED'
    OR v_result->>'next_step' IS DISTINCT FROM 'router'
    OR (SELECT count(*) FROM public.lf_operation_execution_steps
       WHERE execution_id=v_child AND step_id='init_execution'
       AND status='STEP_PASS_WITH_EVIDENCE')<>1
    OR (SELECT count(*) FROM public.lf_operation_execution_steps
       WHERE execution_id=v_child)<>1
    OR (SELECT manifest->>'github_write_executed'
       FROM public.lf_operation_execution WHERE execution_id=v_child)
       IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'FAIL_ONE_GOVERNED_CHILD_INIT_ONLY'; END IF;
  RAISE NOTICE 'PASS_ONE_CHILD_INIT_ONLY';
END $test$;
