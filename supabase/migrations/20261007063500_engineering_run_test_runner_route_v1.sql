-- Route RUN_TEST to an actual connected runner instead of assuming the GitHub connector can execute arbitrary tests.
-- GitHub remains the governed source/artifact provider; the runner executes the exact merged SHA.

create or replace function programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(
  p_packet jsonb,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_contract jsonb := coalesce(p_action_spec->'test_execution_contract','{}'::jsonb);
  v_test_code text := nullif(v_contract->>'test_code','');
  v_test_path text := nullif(v_contract->>'test_path','');
  v_plan jsonb;
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

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
    jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','GITHUB',
        'operation','WRITE_GIT',
        'capability','WRITE_GIT',
        'mode','AUTHOR_CHECKPOINT_TEST',
        'targets',jsonb_build_array(jsonb_build_object(
          'path',v_test_path,
          'test_code',v_test_code
        )),
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

comment on function programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(jsonb,text,text,text,jsonb)
is 'Packet overlay for bounded checkpoint tests: governed Git authoring, exact merged-SHA execution on an operational SentinelX runner, assertion receipt, then transition.';

do $selftest$
declare
  v_packet jsonb;
begin
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'N-18',
    'NEG_OVERTRACKING',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','N-18','NEG_OVERTRACKING'
    ),
    '{}'::jsonb
  );

  if v_packet#>>'{connector_plan,1,provider}' is distinct from 'SENTINELX'
     or v_packet#>>'{connector_plan,1,operation}' is distinct from 'RUN_TEST'
     or v_packet#>>'{connector_plan,1,runner_contract,actual_execution_required}' is distinct from 'true'
     or v_packet#>>'{connector_plan,1,source_contract,ref_mode}' is distinct from 'EXACT_MERGED_SHA' then
    raise exception 'ENGINEERING_RUN_TEST_RUNNER_ROUTE_SELFTEST_FAIL:%',v_packet#>'{connector_plan,1}';
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-RUN-TEST-RUNNER-ROUTE-001',
  'ENGINEERING_ORCHESTRATION',
  'RUN_TEST must route to an executable runner, not an artifact-only Git connector',
  'Bounded checkpoint packets assigned RUN_TEST to GITHUB even when the connected GitHub surface could version files but could not execute arbitrary Python tests.',
  'Artifact transport and execution transport were incorrectly collapsed into one provider.',
  'RUN_TEST_PROVIDER_HAS_NO_EXECUTION_ACTION',
  'Keep WRITE_GIT on GitHub, then execute the exact merged SHA on a connected operational SentinelX runner and bind the observed result to the canonical assertion receipt.',
  'PASS when bounded checkpoint connector plan uses GITHUB for WRITE_GIT, SENTINELX for RUN_TEST, exact merged SHA as source, and requires actual execution with exit code 0.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/17b6a48a7017b1e02c77a98a1f0d58f057f3b676/sandbox/lf_contract_gate_test/engineering_checkpoints/n_18/neg_overtracking.py#sentinelx:scalora-vps:exit0',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Bounded checkpoint RUN_TEST routing',
  'supabase://programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
