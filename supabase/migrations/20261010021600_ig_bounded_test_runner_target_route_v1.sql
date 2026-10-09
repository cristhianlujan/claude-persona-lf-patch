-- Generic engineering bounded-test routing correction: an explicitly declared
-- evidence-acquisition runner must be included in WRITE_GIT, not silently ignored.
-- No new connector capabilities; RUN_TEST remains the authored test and may not
-- claim PASS without independent positive evidence + machine receipt.
-- Proven in sandbox rollback: 2 targets when declared; undeclared BLOCKED;
-- existing single-test packets preserve 1 target.
DO $guard$ BEGIN
 IF md5(pg_get_functiondef('programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(jsonb,text,text,text,jsonb)'::regprocedure)) <> '6ba24fcd4071c4d2aeeaefe1089809b4' THEN
   RAISE EXCEPTION 'BOUNDED_TEST_PACKET_SOURCE_DRIFT';
 END IF;
END $guard$;
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
  v_runner_path text;
  v_authoring_targets jsonb;
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
  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
    jsonb_build_array(
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
      ),
      jsonb_build_object(
        'seq',2,
        'provider','SENTINELX',
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
        'runner_contract',jsonb_build_object(
          'host_resolution','ANY_CONNECTED_OPERATIONAL_HOST',
          'interpreter','python3',
          'temporary_execution_allowed',true,
          'persistent_host_write_required',false,
          'actual_execution_required',true,
          'synthetic_pass','FORBIDDEN',
          'exit_code_required',0
        ),
        'test_execution_contract',v_contract,
        'result_contract',jsonb_build_object(
          'status','PASS',
          'test_code',v_test_code,
          'observed_required',true,
          'evidence_ref_required',true
        )
      ),
      jsonb_build_object(
        'seq',3,
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
        'seq',4,
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
    'capability_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
    'requires_material_execution',true,
    'effective_action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
    'verification_mode','AUTHORED_TEST_BOUND_TO_CANONICAL_EXIT_CRITERION',
    'explicit_test_case_set',jsonb_build_array(v_test_code),
    'block_reasons','[]'::jsonb,
    'connector_plan',v_plan,
    'mutation_policy','TEST_ARTIFACT_ONLY'
  );
end;
$function$;
COMMENT ON FUNCTION programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(jsonb,text,text,text,jsonb) IS
 'Bounded authored test routing includes only exactly declared evidence runner + test source targets, with fail-closed scope guard and unchanged other consumers.';
