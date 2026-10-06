-- M4.8 remaining checkpoint contracts.
-- This migration does not execute the concurrency probe. It declares the exact
-- authored negative contract and the final terminal readback.

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'NEG_CONCURRENT_VALIDATION',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','NEG_CONCURRENT_VALIDATION',
      'checkpoint_title','Negativo: dos validaciones concurrentes del mismo run → una espera o rechaza (prueba con ROLLBACK)',
      'action_kind','CONCURRENCY_EXECUTION',
      'recipe_mode','AUTHORED_NEGATIVE',
      'precision','EXPLICIT_SAME_RUN_CONCURRENCY_NEGATIVE',
      'requires_material_execution',true,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Two independent DB sessions targeting the same IG_VALIDATOR_RUN advisory key must not both acquire it concurrently. One session holds the run lock while the second pg_try_advisory_xact_lock returns false; no domain mutation is performed.',
      'action_steps',jsonb_build_array(
        'OPEN_TWO_INDEPENDENT_DB_SESSIONS',
        'SESSION_A_ACQUIRE_SAME_RUN_LOCK_AND_HOLD',
        'SESSION_B_TRY_SAME_RUN_LOCK',
        'ASSERT_SESSION_B_ACQUIRED_FALSE',
        'ALLOW_SESSION_A_TO_RELEASE',
        'PERSIST_DONE_ON_PASS',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'test_execution_contract',jsonb_build_object(
        'mode','AUTHORED_NEGATIVE',
        'test_code','M48_SAME_RUN_ADVISORY_LOCK_NEGATIVE',
        'session_model','TWO_INDEPENDENT_DB_SESSIONS',
        'side_effect_policy','NONE'
      ),
      'verification_queries',jsonb_build_array(
        $q$
select
  position(
    'IG_VALIDATOR_RUN:' in
    pg_get_functiondef(
      'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
    )
  )>0 as per_run_lock_contract_present,
  not has_function_privilege(
    'service_role',
    'programacion.fn_input_governance_validate_v2(bigint,text)',
    'EXECUTE'
  ) as direct_internal_strategy_denied
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'SIMULATE_CONCURRENCY_IN_ONE_SESSION',
        'USE_DIFFERENT_RUN_KEYS',
        'MUTATE_INPUT_READINESS_DOMAIN_DATA',
        'TREAT_STATIC_LOCK_READBACK_AS_CONCURRENCY_PROOF'
      ),
      'contract_correction','TWO_SESSION_SAME_RUN_NEGATIVE_REQUIRED'
    ),
    'LITERALS_READBACK',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','LITERALS_READBACK',
      'checkpoint_title','Readback: 0 literales; estado terminal',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'precision','EXPLICIT_M48_TERMINAL_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','M4.8 first five checkpoints are DONE; active Validator/template path has no numeric screen/component control-flow literals; canonical dispatcher retains the per-run lock and internal validate_v2 remains closed to application roles.',
      'verification_queries',jsonb_build_array(
        $q$
with unit_row as (
  select pu.work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code='M4.8'
), cp as (
  select count(*) filter(where c.sequence_no<=5 and c.status='DONE') as first_five_done
  from programacion.engineering_work_checkpoints c
  join unit_row u on u.work_item_id=c.work_item_id
), f as (
  select p.proname,p.prosrc
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_validator_rebind_v1',
      'fn_input_governance_validate_v2',
      'fn_input_governance_bootstrap_validate_v1',
      'fn_input_v58_assertion_template',
      'fn_input_v512_assertion_template',
      'fn_input_v58_build_assertions',
      'fn_input_owner_decision_assertions'
    )
)
select
  cp.first_five_done=5 as first_five_checkpoints_done,
  count(*) filter(where f.prosrc ~* 'component_id\s*=\s*[0-9]+')=0 as zero_component_assignment_literals,
  count(*) filter(where f.prosrc ~* '(p_|v_)?pantalla_id\s*=\s*[0-9]+')=0 as zero_screen_equality_literals,
  count(*) filter(where f.prosrc ~* '(p_|v_)?pantalla_id\s+in\s*\([^)]*[0-9]')=0 as zero_screen_in_literals,
  count(*) filter(where f.proname='fn_input_owner_decision_assertions' and f.prosrc ~* 'v_screen\s*=\s*[0-9]+')=0 as zero_owner_screen_equality_literals,
  position(
    'IG_VALIDATOR_RUN:' in
    pg_get_functiondef(
      'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
    )
  )>0 as per_run_lock_present,
  not has_function_privilege(
    'service_role',
    'programacion.fn_input_governance_validate_v2(bigint,text)',
    'EXECUTE'
  ) as direct_internal_strategy_denied
from cp cross join f
group by cp.first_five_done
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'NARRATIVE_TERMINAL_STATUS',
        'SKIP_CONCURRENCY_NEGATIVE',
        'REOPEN_COMPLETED_CHECKPOINTS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.8';
