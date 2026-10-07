-- Generic repair -> retest loop for failed authored checkpoint tests.
-- Activates only after a durable FAILED suite and explicit repair targets.
-- One repair attempt maximum; no unit-specific branching.

create or replace function programacion.fn_engineering_action_spec_apply_failed_authored_test_repair_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb
) returns jsonb
language plpgsql
stable
as $$
declare
  v_meta jsonb;
  v_targets jsonb;
  v_declared jsonb := coalesce(p_spec#>'{target,declared_objects}','[]'::jsonb);
  v_run_count integer := 0;
  v_latest_status text;
  v_latest_suite_run_id uuid;
  v_missing integer := 0;
begin
  if coalesce(p_spec->>'status','')<>'READY'
     or coalesce(p_spec->>'contract_family','')<>'BOUNDED_CHECKPOINT_TEST'
     or coalesce(p_spec->>'action_kind','')<>'BOUNDED_CHECKPOINT_TEST_AUTHORING' then
    return p_spec;
  end if;

  select count(*)::int,
         (array_agg(s.status order by s.created_at desc,s.suite_run_id desc))[1],
         (array_agg(s.suite_run_id order by s.created_at desc,s.suite_run_id desc))[1]
    into v_run_count,v_latest_status,v_latest_suite_run_id
  from public.lf_test_suite_runs s
  where s.metadata->>'plan_code'=p_plan_code
    and s.metadata->>'unit_code'=p_unit_code
    and s.metadata->>'checkpoint_code'=p_checkpoint_code;

  if v_run_count=0 or v_latest_status is distinct from 'FAILED' then
    return p_spec;
  end if;

  if v_run_count>=2 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_REPAIR_RETEST_EXHAUSTED',
      'repair_policy',jsonb_build_object(
        'mode','REPAIR_EXHAUSTED',
        'max_repairs',1,
        'observed_run_count',v_run_count,
        'latest_suite_run_id',v_latest_suite_run_id,
        'latest_status',v_latest_status
      )
    );
  end if;

  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  v_targets:=v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code,'mutation_target','db_objects'];

  if coalesce(jsonb_typeof(v_targets),'')<>'array'
     or jsonb_array_length(v_targets)=0 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_FAILED_TEST_REPAIR_TARGETS_REQUIRED',
      'repair_policy',jsonb_build_object(
        'mode','INPUT_REQUIRED_EXACT_TARGETS',
        'required','unit_metadata.runtime_repair_inputs_v1.<checkpoint>.mutation_target.db_objects[]',
        'inference','FORBIDDEN',
        'latest_suite_run_id',v_latest_suite_run_id
      )
    );
  end if;

  select count(*)::int into v_missing
  from jsonb_array_elements_text(v_targets) t(target)
  where not (v_declared ? t.target);

  if v_missing>0 then
    return p_spec || jsonb_build_object(
      'status','BLOCK_FAILED_TEST_REPAIR_TARGET_OUT_OF_SCOPE',
      'repair_policy',jsonb_build_object(
        'mode','TARGET_SCOPE_REJECTED',
        'mutation_targets',v_targets,
        'declared_objects',v_declared,
        'out_of_scope_count',v_missing,
        'inference','FORBIDDEN'
      )
    );
  end if;

  return p_spec || jsonb_build_object(
    'mutation_policy','ONLY_DECLARED_TARGETS',
    'repair_policy',jsonb_build_object(
      'mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
      'trigger','DURABLE_FAILED_TEST',
      'latest_suite_run_id',v_latest_suite_run_id,
      'mutation_scope','DECLARED_TARGETS_ONLY',
      'mutation_targets',v_targets,
      'repair_route',jsonb_build_array('WRITE_GIT','WRITE_DB'),
      'retest_capability','RUN_TEST',
      'retest_scope','SAME_CASE_SET',
      'max_repairs',1,
      'no_new_router_capability',true,
      'source_of_targets','EXPLICIT_RUNTIME_REPAIR_INPUT'
    ),
    'action_steps',coalesce(p_spec->'action_steps','[]'::jsonb)
      || jsonb_build_array(
        'REPAIR_DECLARED_TARGET',
        'APPLY_EXACT_MERGED_REPAIR',
        'RETEST_SAME_CASE_SET',
        'PERSIST_DONE_ONLY_ON_REAL_PASS'
      )
  );
end;
$$;

create or replace function programacion.fn_engineering_packet_apply_failed_authored_test_repair_v1(
  p_packet jsonb,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb
) returns jsonb
language plpgsql
stable
as $$
declare
  v_policy jsonb:=coalesce(p_action_spec->'repair_policy','{}'::jsonb);
  v_targets jsonb:=coalesce(v_policy->'mutation_targets','[]'::jsonb);
  v_contract jsonb:=coalesce(p_action_spec->'test_execution_contract','{}'::jsonb);
  v_test_code text:=nullif(v_contract->>'test_code','');
  v_test_path text:=nullif(v_contract->>'test_path','');
  v_plan jsonb;
begin
  if coalesce(v_policy->>'mode','')<>'REPAIR_DECLARED_TARGET_THEN_RETEST' then
    return p_packet;
  end if;

  if jsonb_array_length(v_targets)=0 or v_test_code is null or v_test_path is null then
    return p_packet || jsonb_build_object(
      'status','BLOCK_FAILED_TEST_REPAIR_PACKET_INCOMPLETE',
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
        'mode','REPAIR_DECLARED_DB_TARGETS',
        'targets',v_targets,
        'authoring_contract',jsonb_build_object(
          'scope','CURRENT_CHECKPOINT_ONLY',
          'repair_reason','DURABLE_FAILED_TEST',
          'mutation_targets',v_targets,
          'target_inference','FORBIDDEN',
          'migration_required',true,
          'direct_main_write','FORBIDDEN',
          'new_shared_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED'
        ),
        'executor_contract',jsonb_build_object(
          'branch_required',true,
          'pull_request_required',true,
          'governed_merge_required',true,
          'exact_targets_required',true
        )
      ),
      jsonb_build_object(
        'seq',2,
        'provider','SUPABASE',
        'operation','WRITE_DB',
        'capability','WRITE_DB',
        'mode','APPLY_EXACT_MERGED_MIGRATION',
        'targets',v_targets,
        'source_contract',jsonb_build_object(
          'provider','GITHUB',
          'ref_mode','EXACT_MERGED_SHA',
          'merged_source_required',true,
          'source_parity_required',true
        )
      ),
      jsonb_build_object(
        'seq',3,
        'provider','SENTINELX',
        'operation','RUN_TEST',
        'capability','RUN_TEST',
        'mode','RETEST_AUTHORED_CHECKPOINT_TEST',
        'targets',jsonb_build_array(jsonb_build_object('path',v_test_path,'test_code',v_test_code)),
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
        'repair_loop',jsonb_build_object(
          'enabled',true,
          'repair_attempt',1,
          'max_repairs',1,
          'retest_scope','SAME_CASE_SET',
          'stop_on','SECOND_FAILURE_OR_UNDECLARED_TARGET'
        )
      ),
      jsonb_build_object(
        'seq',4,
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
        'seq',5,
        'provider','SUPABASE',
        'operation','CHECKPOINT_TRANSITION'
      )
    ),
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return p_packet || jsonb_build_object(
    'status','READY',
    'execution_allowed',true,
    'execution_capability','RUN_TEST',
    'capability_mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
    'requires_material_execution',true,
    'effective_action_kind','REPAIR_AND_RETEST_DECLARED_TARGETS',
    'verification_mode','RETEST_SAME_AUTHORED_CASE',
    'repair_policy',v_policy,
    'block_reasons','[]'::jsonb,
    'connector_plan',v_plan,
    'mutation_policy','ONLY_DECLARED_TARGETS'
  );
end;
$$;

do $patch_action_spec$
declare
  v_def text;
  v_anchor text := E'  v_base:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_base);\n';
  v_patch text := E'  v_base:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_base);\n'
    || E'  v_base:=programacion.fn_engineering_action_spec_apply_failed_authored_test_repair_v1(\n'
    || E'    p_plan_code,p_unit_code,v_cp,v_base\n'
    || E'  );\n';
begin
  select pg_get_functiondef('programacion.fn_engineering_checkpoint_action_spec_v3(text,text,text)'::regprocedure)
    into v_def;
  if position('fn_engineering_action_spec_apply_failed_authored_test_repair_v1' in v_def)>0 then
    return;
  end if;
  if position(v_anchor in v_def)=0 then
    raise exception 'AUTHORED_TEST_REPAIR_ACTION_SPEC_ANCHOR_MISSING';
  end if;
  execute replace(v_def,v_anchor,v_patch);
end;
$patch_action_spec$;

do $patch_packet$
declare
  v_def text;
  v_anchor text := E'  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(\n'
    || E'    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec\n'
    || E'  );\n';
  v_patch text := E'  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(\n'
    || E'    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec\n'
    || E'  );\n'
    || E'  v_packet:=programacion.fn_engineering_packet_apply_failed_authored_test_repair_v1(\n'
    || E'    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec\n'
    || E'  );\n';
begin
  select pg_get_functiondef('programacion.fn_engineering_execution_packet_from_spec_v1(text,text,text,jsonb,jsonb)'::regprocedure)
    into v_def;
  if position('fn_engineering_packet_apply_failed_authored_test_repair_v1' in v_def)>0 then
    return;
  end if;
  if position(v_anchor in v_def)=0 then
    raise exception 'AUTHORED_TEST_REPAIR_PACKET_ANCHOR_MISSING';
  end if;
  execute replace(v_def,v_anchor,v_patch);
end;
$patch_packet$;

comment on function programacion.fn_engineering_action_spec_apply_failed_authored_test_repair_v1(text,text,text,jsonb)
is 'Generic authored-test failure overlay: durable FAIL + explicit in-scope DB targets -> one REPAIR_DECLARED_TARGET_THEN_RETEST attempt; second FAIL blocks.';
comment on function programacion.fn_engineering_packet_apply_failed_authored_test_repair_v1(jsonb,text,text,text,jsonb)
is 'Compiles the governed repair migration/apply/retest/assert/transition packet for a failed authored checkpoint test.';
