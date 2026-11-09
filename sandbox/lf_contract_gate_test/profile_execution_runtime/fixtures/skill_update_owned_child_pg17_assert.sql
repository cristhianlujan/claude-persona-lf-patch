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

  -- Negative: current README alone does not replace a completed 14/14 LF run.
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(v_child,v_input,v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED%' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_child)
  THEN RAISE EXCEPTION 'FAIL_NO_CHILD_BEFORE_OWNER'; END IF;
  RAISE NOTICE 'PASS_NO_CANONICAL_LEDGER_BLOCKS';

  -- Synthetic historical 14/14 clean operation, NOT live authority.
  INSERT INTO public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,manifest,
    request_sha256,created_by_execution_id,target_path)
  VALUES('EXEC-SKILL-G1-CURRENT','ACTUALIZACION_SKILL_LF','SKILL',
    'ACT-0045','COMPLETED','{}',repeat('a',64),'TEST','skills/profile_creator');
  INSERT INTO public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_payload)
  SELECT 'EXEC-SKILL-G1-CURRENT',step_order,step_id,'STEP_PASS_WITH_EVIDENCE',
    CASE WHEN step_id='skill_resolve' THEN
      jsonb_build_object('codigo_activo','ACT-0045',
        'repo_path','skills/profile_creator','exact_skill_resolved',true)
    ELSE '{}'::jsonb END
  FROM public.lf_operation_step_contracts
  WHERE operation_code='ACTUALIZACION_SKILL_LF' AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_execution_steps SET status='STEP_BLOCKED'
  WHERE execution_id='EXEC-SKILL-G1-CURRENT' AND step_id='semantic_judge';
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(v_child,v_input,v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED%' THEN RAISE; END IF;
  END;
  UPDATE public.lf_operation_execution_steps SET status='STEP_PASS_WITH_EVIDENCE'
  WHERE execution_id='EXEC-SKILL-G1-CURRENT' AND step_id='semantic_judge';
  RAISE NOTICE 'PASS_PARTIAL_LEDGER_BLOCKS';

  -- Wrong input with original run must fail invocation hash first.
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(
      v_child,
      jsonb_set(v_input,'{_trusted,github_owner,asset_code}','"ACT-9999"'::jsonb),
      v_parent,v_run,repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_INVOCATION_UNBOUND%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS_FORGED_INPUT_HASH_BLOCKS';

  -- A separate synthetically bound invocation verifies the owner check itself.
  INSERT INTO public.lf_skill_invocation_v1 VALUES(
    'RUN-ABCDEF1234567890FAKE','SKILL_UPDATE_APPLY',
    v_parent,'EXEC-SKILL-FORGED-OWNER',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','COMPLETED',
    encode(extensions.digest(convert_to(
      jsonb_set(v_input,'{_trusted,github_owner,asset_code}','"ACT-9999"'::jsonb)::text,
      'UTF8'),'sha256'),'hex'));
  BEGIN
    PERFORM public.lf_skill_o_skill_update_v1(
      'EXEC-SKILL-FORGED-OWNER',
      jsonb_set(v_input,'{_trusted,github_owner,asset_code}','"ACT-9999"'::jsonb),
      v_parent,'RUN-ABCDEF1234567890FAKE',repeat('a',64));
    RAISE EXCEPTION 'NEGATIVE_DID_NOT_BLOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%SKILL_UPDATE_CHILD_CURRENT_OWNER_PROOF_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS_FORGED_README_PROOF_BLOCKS';

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
