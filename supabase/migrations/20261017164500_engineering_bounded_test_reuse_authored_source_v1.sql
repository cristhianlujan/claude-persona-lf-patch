-- Transversal: respect already-authored checkpoint tests, no duplicated Git authoring.
-- Preserve exact merged SHA + runner receipt and all legacy authoring-required behavior.
-- Governed through LF Migration Merge Train only, no direct database writes.
BEGIN;
DO $source_guard$ BEGIN
 IF md5(pg_get_functiondef('programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(jsonb,text,text,text,jsonb)'::regprocedure)) <> 'c494f08cbe122851f37bebedaaa02d97' THEN
   RAISE EXCEPTION 'BOUNDED_TEST_COMPILER_SOURCE_DRIFT';
 END IF;
END $source_guard$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v(p_packet jsonb, p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_contract jsonb := coalesce(p_action_spec->'test_execution_contract','{}'::jsonb);
  v_test_code text := nullif(v_contract->>'test_code','');
  v_test_path text := nullif(v_contract->>'test_path','');
  v_plan jsonb;
  v_execution_route jsonb;
  v_runner_path text;
  v_authoring_targets jsonb;
  v_authoring_required boolean := coalesce((v_contract->>'authoring_required')::boolean,true);
begin
  if coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce(p_action_spec->>'contract_family','')<>'BOUNDED_CHECKPOINT_TEST' then
    return p_packet;
  end if;

  if v_test_code is null or v_test_path is null
     or nullif(v_contract->>'canonical_exit_criterion','') is null then
    return p_packet||jsonb_build_object(
      'status','BLOCK_BOUNDED_CHECKPOINT_TEST_CONTRACT_INCOMPLETE',
      'execution_allowed',false
    );
  end if;

  v_authoring_targets:=jsonb_build_array(jsonb_build_object('path',v_test_path,'test_code',v_test_code));
  IF p_action_spec ? 'evidence_acquisition_contract' THEN
    v_runner_path:=nullif(v_contract->>'runner_path','');
    IF v_runner_path IS NULL
      OR v_runner_path IS DISTINCT FROM p_action_spec#>>'{evidence_acquisition_contract,runner_path}'
      OR v_runner_path = v_test_path
      OR v_runner_path NOT LIKE 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/%'
      OR v_runner_path LIKE '%..%'
      OR NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(coalesce(p_action_spec#>'{target,mutation_artifacts}','[]'::jsonb)) t(value)
        WHERE t.value->>'path'=v_runner_path
          AND t.value->>'role'='MUTATION_TARGET'
          AND t.value->>'purpose'='CHECKPOINT_EVIDENCE_ACQUISITION_RUNNER'
      ) THEN
      RETURN p_packet || jsonb_build_object('status','BLOCK_UNDECLARED_SHADOW_RUNNER','execution_allowed',false);
    END IF;
    v_authoring_targets:=v_authoring_targets||jsonb_build_array(jsonb_build_object('path',v_runner_path,'role','MUTATION_TARGET','purpose','CHECKPOINT_EVIDENCE_ACQUISITION_RUNNER'));
  END IF;

  v_execution_route:=programacion.fn_engineering_test_executor_resolve_v1(p_action_spec);
  IF v_execution_route->>'status'<>'READY' THEN
    RETURN p_packet || jsonb_build_object(
      'status',v_execution_route->>'status',
      'execution_allowed',false,
      'test_executor_resolution',v_execution_route
    );
  END IF;

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(

    (case when v_authoring_required then jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','GITHUB',
        'operation','WRITE_GIT',
        'capability','WRITE_GIT',
        'mode','AUTHOR_CHECKPOINT_TEST',
        'targets',v_authoring_targets,
        'authoring_contract',jsonb_build_object(
          'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION',
          'canonical_exit_criterion',v_contract->>'canonical_exit_criterion',
          'checkpoint_title_context',v_contract->>'checkpoint_title_context',
          'declared_queries',coalesce(v_contract->'declared_queries','[]'::jsonb),
          'declared_objects',coalesce(v_contract->'declared_objects','[]'::jsonb),
          'negative_required',coalesce((v_contract->>'negative_required')::boolean,false),
          'synthetic_pass','FORBIDDEN',
          'fallback_case_discovery','FORBIDDEN',
          'scope','CURRENT_CHECKPOINT_ONLY'
        ),
        'executor_contract',jsonb_build_object(
          'branch_required',true,
          'pull_request_required',true,
          'governed_merge_required',true,
          'direct_main_write','FORBIDDEN',
          'exact_test_path_required',true
        )
      )
    ) else '[]'::jsonb end) || jsonb_build_array(
      jsonb_build_object(
        'seq',case when v_authoring_required then 2 else 1 end,
        'provider',v_execution_route->>'provider',
        'operation','RUN_TEST',
        'capability','RUN_TEST',
        'mode','AUTHORED_CHECKPOINT_TEST',
        'targets',jsonb_build_array(jsonb_build_object(
          'path',v_test_path,
          'test_code',v_test_code
        )),
        'source_contract',jsonb_build_object(
          'provider','GITHUB',
          'ref_mode','EXACT_MERGED_SHA',
          'merged_source_required',true
        ),
        'runner_contract',v_execution_route->'runner_contract',
        'test_execution_contract',v_contract,
        'result_contract',jsonb_build_object(
          'status','PASS',
          'test_code',v_test_code,
          'observed_required',true,
          'evidence_ref_required',true
        )
      ),
      jsonb_build_object(
        'seq',case when v_authoring_required then 3 else 2 end,
        'provider','SUPABASE',
        'operation','CHECKPOINT_ASSERTION_RECORD',
        'capability','WRITE_DB',
        'entrypoint','programacion.fn_engineering_checkpoint_assertion_record_v1',
        'result_source','PREVIOUS_RUN_TEST_RESULT',
        'result_mapping',jsonb_build_object(
          'status','PASS',
          'evidence_ref','RUN_TEST_EVIDENCE_REF',
          'observed','RUN_TEST_OBSERVED'
        )
      ),
      jsonb_build_object(
        'seq',case when v_authoring_required then 4 else 3 end,
        'provider','SUPABASE',
        'operation','CHECKPOINT_TRANSITION'
      )
    ),
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return p_packet||jsonb_build_object(
    'status','READY',
    'execution_allowed',true,
    'execution_capability','RUN_TEST',
    'capability_mode',case when v_authoring_required then 'AUTHOR_AND_RUN_CHECKPOINT_TEST' else 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST' end,
    'requires_material_execution',true,
    'effective_action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
    'verification_mode','AUTHORED_TEST_BOUND_TO_CANONICAL_EXIT_CRITERION',
    'explicit_test_case_set',jsonb_build_array(v_test_code),
    'block_reasons','[]'::jsonb,
    'test_executor_resolution',v_execution_route,
    'connector_plan',v_plan,
    'mutation_policy','TEST_ARTIFACT_ONLY'
  );
end;
$function$



DO $regression$
DECLARE
  s jsonb;
  route jsonb := jsonb_build_object('provider','GITHUB_ACTIONS','workflow_path','.github/workflows/lf-router-level2-advisory-tests.yml','job_name','router-level2-advisory-contract','check_name','router-level2-advisory-contract');
  no_auth jsonb;
  auth jsonb;
  legacy jsonb;
  invalid jsonb;
  p jsonb;
  ops text[];
BEGIN
  s:=programacion.fn_engineering_checkpoint_action_spec_v3('LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2');
  IF s->>'status' IS DISTINCT FROM 'READY' OR s#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'REGRESSION_SOURCE_NOT_READY';
  END IF;
  no_auth:=jsonb_set(s,'{test_execution_contract,execution_route}',route,true);
  auth:=jsonb_set(no_auth,'{test_execution_contract,authoring_required}','true'::jsonb,true);
  legacy:=no_auth#-'{test_execution_contract,authoring_required}';
  invalid:=no_auth#-'{test_execution_contract,execution_route,check_name}';
  p:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1('{"status":"READY"}'::jsonb,'LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2',no_auth);
  SELECT array_agg(x.value->>'operation' ORDER BY x.ordinality) INTO ops
  FROM jsonb_array_elements(coalesce(p->'connector_plan','[]'::jsonb)) WITH ORDINALITY x(value,ordinality);
  IF p->>'status' IS DISTINCT FROM 'READY'
     OR p->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR ops IS DISTINCT FROM ARRAY['RUN_TEST','CHECKPOINT_ASSERTION_RECORD','CHECKPOINT_TRANSITION']::text[]
     OR p->>'capability_mode' IS DISTINCT FROM 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST'
     OR (SELECT bool_and((elem->>'seq')::int=ord::int) FROM jsonb_array_elements(p->'connector_plan') WITH ORDINALITY a(elem,ord)) IS NOT TRUE
     OR p#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
     OR p#>>'{connector_plan,0,runner_contract,verified_run_id_required}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'REGRESSION_EXISTING_TEST_MODE_INVALID:%',p; END IF;
  p:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1('{"status":"READY"}'::jsonb,'LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2',auth);
  SELECT array_agg(x.value->>'operation' ORDER BY x.ordinality) INTO ops
  FROM jsonb_array_elements(coalesce(p->'connector_plan','[]'::jsonb)) WITH ORDINALITY x(value,ordinality);
  IF p->>'status' IS DISTINCT FROM 'READY'
    OR ops IS DISTINCT FROM ARRAY['WRITE_GIT','RUN_TEST','CHECKPOINT_ASSERTION_RECORD','CHECKPOINT_TRANSITION']::text[]
    OR p->>'capability_mode' IS DISTINCT FROM 'AUTHOR_AND_RUN_CHECKPOINT_TEST'
  THEN RAISE EXCEPTION 'REGRESSION_AUTHOR_REQUIRED_MODE_INVALID:%',p; END IF;
  p:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1('{"status":"READY"}'::jsonb,'LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2',legacy);
  IF p->>'status' IS DISTINCT FROM 'READY' OR p#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'WRITE_GIT'
  THEN RAISE EXCEPTION 'REGRESSION_LEGACY_DEFAULT_MUST_AUTHOR:%',p; END IF;
  p:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1('{"status":"READY"}'::jsonb,'LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2',invalid);
  IF p->>'status' <> 'BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE' OR p->>'execution_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'REGRESSION_MISSING_CHECK_SHOULD_BLOCK:%',p; END IF;
  p:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1('{"status":"READY"}'::jsonb,'LF_ROUTER_ARCHITECTURE_WAVE_V1','RW1-01','RW1-01_C2',
    jsonb_set(no_auth,'{test_execution_contract,execution_route,provider}','"UNREGISTERED"'::jsonb,true));
  IF p->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED' OR p->>'execution_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'REGRESSION_UNKNOWN_PROVIDER_SHOULD_BLOCK:%',p; END IF;
END
$regression$;

COMMIT;
