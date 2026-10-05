begin;

do $guard$
declare
  v_action text;
  v_packet text;
begin
  select md5(p.prosrc) into v_action
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  select md5(p.prosrc) into v_packet
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  if v_action is distinct from '37d63f51f33a9959137c018ccf4286d5' then
    raise exception 'ACTION_SPEC_V3_DRIFT:%',v_action;
  end if;
  if v_packet is distinct from 'd02f6105c404362ca8eee83316f04491' then
    raise exception 'EXECUTION_PACKET_DRIFT:%',v_packet;
  end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code='CONTROL_EQUIVALENCE_JUDGE'
      and version='1.0.0'
      and manifest_sha256='57679dfcdc4de7bd70aa5458547722f3e8d8aba00d9407baad3566137abd3b52'
  ) then
    raise exception 'T_EQUIV_CURRENT_DRIFT';
  end if;

  if to_regprocedure('programacion.fn_input_governance_shadow_evaluate_v2(integer,bigint)') is null
     or to_regprocedure('programacion.fn_input_governance_shadow_sweep_v2(bigint)') is null then
    raise exception 'M3_9_CANONICAL_SHADOW_MISSING';
  end if;
end
$guard$;

create or replace function pg_temp.rep(src text,o text,n text)
returns text
language plpgsql
as $r$
begin
  if position(o in src)=0 then
    raise exception 'PATCH_ANCHOR_MISSING:%',left(o,140);
  end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then
    raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,140);
  end if;
  return replace(src,o,n);
end
$r$;

do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  d:=pg_temp.rep(
    d,
    $orig$  when objects @> jsonb_build_array('public.lf_test_suite_runs','public.lf_test_assertion_results')$orig$,
    $repl$  when checkpoint_code='SHADOW_RUN' and title_l like '%t-equiv%' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','COMPILED_CAPABILITY_TEST',
      'action_kind','DECLARED_CAPABILITY_TEST_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_CAPABILITY_TEST',
      'requires_material_execution',true,
      'mutation_policy','TEST_EVIDENCE_ONLY',
      'target',coalesce(spec->'target','{}'::jsonb) || jsonb_build_object(
        'declared_objects',coalesce(spec#>'{target,declared_objects}','[]'::jsonb) || jsonb_build_array(
          'programacion.fn_input_governance_shadow_evaluate_v2',
          'programacion.fn_input_governance_shadow_sweep_v2',
          'public.lf_capability_current',
          'public.lf_capability_binding',
          'public.lf_operation_execution',
          'public.lf_test_suite_cases',
          'public.lf_test_suite_runs',
          'public.lf_test_runs',
          'public.lf_test_assertion_results'
        )
      ),
      'capability_execution',jsonb_build_object(
        'contract','DECLARED_CAPABILITY_SHADOW_V1',
        'capability_code','CONTROL_EQUIVALENCE_JUDGE',
        'version_policy','CURRENT_EXACT_MANIFEST',
        'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
        'currentness_source','public.lf_capability_current',
        'orchestrator_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'consumer_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'dispatch_entrypoint','public.fn_lf_orchestrator_dispatch_receipt_v1',
        'binding_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'binding_readback_source','public.lf_capability_binding',
        'execution_readback_source','public.lf_operation_execution',
        'shadow_entrypoint','programacion.fn_input_governance_shadow_evaluate_v2',
        'fresh_receipt_required',true,
        'execution_id_prefix','T-EQUIV-IG-M3-9-',
        'orchestrator_execution_id_prefix','T-EQUIV-ORCH-IG-M3-9-',
        'plan_digest_seed','IG_CURATOR_VALIDATOR_REFACTOR_V2:M3.9|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY',
        'corpus_screen_ids',jsonb_build_array(1,2,3,5,43,51,52,53,54,55,56,57,58),
        'domain_mutation','FORBIDDEN',
        'comparison_only',true
      ),
      'verification_queries',jsonb_build_array(
        $q$with v as (
          select public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT') as version_id
        ), s(id) as (
          values (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58)
        )
        select jsonb_build_object(
          'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
          'version_id',max(v.version_id),
          'screen_count',count(*),
          'screens',jsonb_agg(
            jsonb_build_object(
              'pantalla_id',s.id,
              'shadow',programacion.fn_input_governance_shadow_evaluate_v2(s.id,v.version_id)
            ) order by s.id
          )
        )
        from s cross join v$q$
      ),
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','CAPABILITY_OWNED',
        'design_boundary','BIND_T_EQUIV_THEN_EXECUTE_EXISTING_SHADOW_ONLY',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1',
        'execution_semantics','REAL_SHADOW_AND_FRESH_RECEIPT_REQUIRED'
      ),
      'action_steps',jsonb_build_array(
        'BIND_CURRENT_T_EQUIV_AND_PERSIST_FRESH_RECEIPT',
        'EXECUTE_EXISTING_SHADOW_ON_DECLARED_CORPUS',
        'PERSIST_REAL_TEST_EVIDENCE',
        'VERIFY_BINDING_AND_SHADOW_RECEIPTS',
        'PERSIST_DONE_ONLY_AFTER_REAL_EXECUTION',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'CREATE_PARALLEL_SHADOW_ENGINE',
        'SYNTHETIC_PASS_WITHOUT_SHADOW_EXECUTION',
        'REUSE_OLD_BINDING_AS_THIS_RUN_RECEIPT',
        'MUTATE_DOMAIN_DATA'
      )
    )
  when objects @> jsonb_build_array('public.lf_test_suite_runs','public.lf_test_assertion_results')$repl$
  );
  execute d;
end
$patch_action$;

do $patch_packet$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  d:=pg_temp.rep(
    d,
    $orig$      'ROLLBACK_DRILL','VERIFY_QUERY_ONCE','FAULT_INJECTION','DECLARED_TEST_EXECUTION',$orig$,
    $repl$      'ROLLBACK_DRILL','VERIFY_QUERY_ONCE','FAULT_INJECTION','DECLARED_TEST_EXECUTION','DECLARED_CAPABILITY_TEST_EXECUTION',$repl$
  );

  d:=pg_temp.rep(
    d,
    $orig$            'ROLLBACK_DRILL','FAULT_INJECTION','FAULT_INJECTION_TIMEOUT','DECLARED_TEST_EXECUTION',$orig$,
    $repl$            'ROLLBACK_DRILL','FAULT_INJECTION','FAULT_INJECTION_TIMEOUT','DECLARED_TEST_EXECUTION','DECLARED_CAPABILITY_TEST_EXECUTION',$repl$
  );

  d:=pg_temp.rep(
    d,
    $orig$    when execution_capability='RUN_TEST' then jsonb_build_array(
      jsonb_build_object(
        'seq',1,'provider','SUPABASE','operation','RUN_TEST','capability','RUN_TEST','mode',capability_mode,
        'targets',objects,'queries',verification_queries,
        'test_scope',jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
        'executor_contract',jsonb_build_object(
          'case_authority','public.lf_test_suite_cases',
          'persistence_owner','RUN_TEST_EXECUTOR',
          'canonical_persistence_graph',jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'),
          'persist_graph_when_required_by_checkpoint',true,
          'synthetic_pass','FORBIDDEN',
          'full_suite_rerun','FORBIDDEN_UNLESS_EXPLICIT_SCOPE',
          'executor','ENGINEERING_AGENT_RUN_TEST_V1',
          'case_resolution','EXACT_UNIT_CHECKPOINT_CASES_ELSE_AUTHORED_NEGATIVE',
          'case_filter',jsonb_build_object('unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
          'repair_loop',case
            when p_action_spec#>>'{repair_policy,mode}'='REPAIR_DECLARED_TARGET_THEN_RETEST'
            then jsonb_build_object(
              'enabled',true,
              'trigger','CONTRADICTION',
              'max_repairs',1,
              'declared_targets_only',true,
              'route',jsonb_build_array('WRITE_GIT','WRITE_DB','RUN_TEST'),
              'write_git_mode','MIGRATION',
              'retest_scope','SAME_CASE_SET',
              'stop_on','SECOND_FAILURE_OR_UNDECLARED_TARGET'
            )
            else jsonb_build_object('enabled',false)
          end,
          'return_evidence_for_transition',true
        )
      ),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )$orig$,
    $repl$    when execution_capability='RUN_TEST' then
      case when action_kind='DECLARED_CAPABILITY_TEST_EXECUTION' then jsonb_build_array(
        jsonb_build_object(
          'seq',1,'provider','SUPABASE','operation','WRITE_DB','capability','WRITE_DB','mode','CAPABILITY_BIND_RECEIPT',
          'targets',jsonb_build_array('public.lf_operation_execution','public.lf_capability_binding'),
          'capability_execution',coalesce(p_action_spec->'capability_execution','{}'::jsonb),
          'executor_contract',jsonb_build_object(
            'fresh_receipt_required',true,
            'reuse_old_receipt_as_current','FORBIDDEN',
            'domain_mutation','FORBIDDEN',
            'reserve_orchestrator_then_consumer',true,
            'dispatch_before_bind',true,
            'bind_current_exact_manifest',true,
            'complete_operation_receipts',true,
            'return_binding_evidence_to_next_step',true
          )
        ),
        jsonb_build_object(
          'seq',2,'provider','SUPABASE','operation','RUN_TEST','capability','RUN_TEST','mode',capability_mode,
          'targets',objects,'queries',verification_queries,
          'capability_execution',coalesce(p_action_spec->'capability_execution','{}'::jsonb),
          'test_scope',jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
          'executor_contract',jsonb_build_object(
            'case_authority','public.lf_test_suite_cases',
            'persistence_owner','RUN_TEST_EXECUTOR',
            'canonical_persistence_graph',jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'),
            'persist_graph_when_required_by_checkpoint',true,
            'synthetic_pass','FORBIDDEN',
            'executor','ENGINEERING_AGENT_RUN_TEST_V1',
            'case_resolution','EXACT_UNIT_CHECKPOINT_CASES_REQUIRED',
            'case_filter',jsonb_build_object('unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
            'binding_receipt_from_previous_step','REQUIRED',
            'execute_declared_queries',true,
            'return_evidence_for_transition',true
          )
        ),
        jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
      ) else jsonb_build_array(
        jsonb_build_object(
          'seq',1,'provider','SUPABASE','operation','RUN_TEST','capability','RUN_TEST','mode',capability_mode,
          'targets',objects,'queries',verification_queries,
          'test_scope',jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
          'executor_contract',jsonb_build_object(
            'case_authority','public.lf_test_suite_cases',
            'persistence_owner','RUN_TEST_EXECUTOR',
            'canonical_persistence_graph',jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'),
            'persist_graph_when_required_by_checkpoint',true,
            'synthetic_pass','FORBIDDEN',
            'full_suite_rerun','FORBIDDEN_UNLESS_EXPLICIT_SCOPE',
            'executor','ENGINEERING_AGENT_RUN_TEST_V1',
            'case_resolution','EXACT_UNIT_CHECKPOINT_CASES_ELSE_AUTHORED_NEGATIVE',
            'case_filter',jsonb_build_object('unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
            'repair_loop',case
              when p_action_spec#>>'{repair_policy,mode}'='REPAIR_DECLARED_TARGET_THEN_RETEST'
              then jsonb_build_object(
                'enabled',true,
                'trigger','CONTRADICTION',
                'max_repairs',1,
                'declared_targets_only',true,
                'route',jsonb_build_array('WRITE_GIT','WRITE_DB','RUN_TEST'),
                'write_git_mode','MIGRATION',
                'retest_scope','SAME_CASE_SET',
                'stop_on','SECOND_FAILURE_OR_UNDECLARED_TARGET'
              )
              else jsonb_build_object('enabled',false)
            end,
            'return_evidence_for_transition',true
          )
        ),
        jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
      ) end$repl$
  );
  execute d;
end
$patch_packet$;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,
  execution_mode,severity,preconditions,input_payload,expected_output,
  prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
) values (
  'INPUT_GOVERNANCE_REGRESSION',
  'M3_9_SHADOW_T_EQUIV_CORPUS',
  390900,
  null,
  array[]::text[],
  'M3.9 shadow corpus via T-EQUIV exact-only',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_object(
    'capability_current','CONTROL_EQUIVALENCE_JUDGE@CURRENT',
    'shadow_entrypoint','programacion.fn_input_governance_shadow_evaluate_v2'
  ),
  jsonb_build_object(
    'corpus_screen_ids',jsonb_build_array(1,2,3,5,43,51,52,53,54,55,56,57,58),
    'version_resolver','public.fn_lf_version_compatibility_current_version_id_v1',
    'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS'
  ),
  jsonb_build_object(
    'shadow_execution','REAL',
    'screen_count',13,
    'fresh_t_equiv_binding_receipt',true,
    'domain_mutation',false,
    'diff_adjudication','NEXT_CHECKPOINT'
  ),
  jsonb_build_object(
    'synthetic_pass',true,
    'old_binding_reused_as_current',true,
    'parallel_shadow_engine',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'unit_code','M3.9',
    'checkpoint_code','SHADOW_RUN',
    'executor','ENGINEERING_AGENT_RUN_TEST_V1',
    'execution_contract','DECLARED_CAPABILITY_SHADOW_V1',
    'capability_code','CONTROL_EQUIVALENCE_JUDGE',
    'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
    'shadow_entrypoint','programacion.fn_input_governance_shadow_evaluate_v2',
    'receipt_required',true,
    'comparison_only',true
  ),
  'GPT-5.6-SOL-M3.9-T-EQUIV-CHAIN-V1',
  'GPT-5.6-SOL-M3.9-T-EQUIV-CHAIN-V1'
)
on conflict (suite_code,test_code) do update set
  title=excluded.title,
  test_type=excluded.test_type,
  execution_mode=excluded.execution_mode,
  severity=excluded.severity,
  preconditions=excluded.preconditions,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  status=excluded.status,
  metadata=excluded.metadata,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

do $verify$
declare
  v_spec jsonb;
  v_packet jsonb;
  v_count integer;
begin
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN'
  );
  if v_spec->>'action_kind' is distinct from 'DECLARED_CAPABILITY_TEST_EXECUTION' then
    raise exception 'M3_9_ACTION_KIND_NOT_CAPABILITY_TEST:%',v_spec->>'action_kind';
  end if;
  if v_spec#>>'{capability_execution,capability_code}' is distinct from 'CONTROL_EQUIVALENCE_JUDGE' then
    raise exception 'M3_9_T_EQUIV_NOT_COMPILED';
  end if;
  if jsonb_array_length(coalesce(v_spec->'verification_queries','[]'::jsonb))<>1 then
    raise exception 'M3_9_SHADOW_QUERY_COUNT_INVALID';
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN',v_spec,'{}'::jsonb
  );
  if v_packet->>'execution_capability' is distinct from 'RUN_TEST' then
    raise exception 'M3_9_PACKET_NOT_RUN_TEST:%',v_packet->>'execution_capability';
  end if;
  if jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb))<>3 then
    raise exception 'M3_9_CONNECTOR_PLAN_NOT_THREE_STEPS:%',jsonb_array_length(coalesce(v_packet->'connector_plan','[]'::jsonb));
  end if;
  if v_packet#>>'{connector_plan,0,mode}' is distinct from 'CAPABILITY_BIND_RECEIPT'
     or v_packet#>>'{connector_plan,1,operation}' is distinct from 'RUN_TEST'
     or v_packet#>>'{connector_plan,2,operation}' is distinct from 'CHECKPOINT_TRANSITION' then
    raise exception 'M3_9_CONNECTOR_SEQUENCE_INVALID:%',v_packet->'connector_plan';
  end if;

  select count(*) into v_count
  from public.lf_test_suite_cases
  where metadata->>'unit_code'='M3.9'
    and metadata->>'checkpoint_code'='SHADOW_RUN'
    and metadata->>'executor'='ENGINEERING_AGENT_RUN_TEST_V1';
  if v_count<>1 then
    raise exception 'M3_9_CANONICAL_CASE_COUNT:%',v_count;
  end if;
end
$verify$;

commit;
