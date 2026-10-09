-- M4.2 remaining explicit contracts.
-- Reuse already-qualified M7.2 Golden 5.13 evidence; do not re-run dependency-owned tests.

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'GOLDEN_PARITY_513',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','GOLDEN_PARITY_513',
      'checkpoint_title','Paridad contra golden 5.13 (M7.2) y suite INPUT_GOVERNANCE_REGRESSION sin regresiones',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'precision','EXPLICIT_REUSE_M72_GOLDEN_513',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Reuse qualified M7.2 Golden 5.13 evidence: suite run e35352af... PASSED 141/141 with zero failures/blocks/review, baseline historical 611, differences=0, mutation negative detected and rollback clean.',
      'verification_queries',jsonb_build_array(
        $q$
with g as (
  select *
  from public.lf_test_suite_runs
  where suite_run_id='e35352af-8014-4a68-8ce1-de2c4ceb0700'::uuid
), e as (
  select payload
  from public.lf_eventos
  where id=20324
), m72 as (
  select wi.status,wp.progress_pct,wp.done_checkpoint_count,wp.checkpoint_count
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items wi on wi.id=pu.work_item_id
  join programacion.v_engineering_work_progress wp on wp.id=wi.id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code='M7.2'
)
select
  (select status='DONE' and progress_pct=100 and done_checkpoint_count=checkpoint_count from m72) as m72_terminal_done,
  (select status='PASSED' and tests_total=141 and tests_passed=141 and tests_failed=0 and tests_blocked=0 and tests_review_required=0 from g) as golden_run_pass,
  (select manifest#>>'{baseline,historical_rows}'='611' and manifest->>'differences'='0'
          and manifest->>'fresh_total'='141' and manifest->>'fresh_passed'='141'
          and manifest#>>'{mutation_negative,detected_differences}'='1'
          and manifest#>>'{mutation_negative,rollback_clean}'='true'
          and manifest#>>'{mutation_negative,rollback_residual_rows}'='0'
     from g) as golden_manifest_exact,
  (select payload->>'suite_run_id'='e35352af-8014-4a68-8ce1-de2c4ceb0700'
          and payload->>'historical_reused'='611'
          and payload->>'fresh_executed'='141'
          and payload->>'fresh_passed'='141'
          and payload->>'differences'='0'
          and payload->>'fanout_performed'='false'
     from e) as event_20324_exact
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'REEXECUTE_M7_2_GOLDEN',
        'REUSE_LATEST_UNRELATED_ONE_CASE_SUITE_RUN',
        'EXPAND_TO_DEPENDENCY_OWNED_TESTS'
      ),
      'contract_correction','REUSE_EXACT_QUALIFIED_GOLDEN_EVIDENCE'
    ),
    'SINGLE_VALIDATOR_READBACK',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','SINGLE_VALIDATOR_READBACK',
      'checkpoint_title','Readback: 1 entrypoint en pg_proc/Edge, 0 caminos PASS sin oracle; estado terminal',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'precision','EXPLICIT_SINGLE_VALIDATOR_ORACLE_TERMINAL_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','First five M4.2 checkpoints DONE; only the public Validator facade is executable by service_role; it routes to the internal dispatcher; internal strategies are not application-executable; oracle builder and enabled persistence guard both fail closed on assertion failure.',
      'verification_queries',jsonb_build_array(
        $q$
with u as (
  select pu.work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code='M4.2'
), cp as (
  select count(*) filter(where c.sequence_no<=5 and c.status='DONE') as first_five_done
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id=c.work_item_id
), defs as (
  select
    pg_get_functiondef('public.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure) as facade_def,
    pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure) as guard_def,
    pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure) as builder_def
), trg as (
  select count(*) filter(
    where p.proname='fn_guard_input_family_assessment_update'
      and t.tgenabled='O'
  ) as enabled_guard_count
  from pg_trigger t
  join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='programacion.input_family_assessments'::regclass
    and not t.tgisinternal
), surfaces as (
  select
    count(*) filter(
      where has_function_privilege('service_role',p.oid,'EXECUTE')
    ) as service_role_executable_count,
    count(*) filter(
      where n.nspname='public'
        and p.proname='fn_input_governance_validator_validate_v1'
        and has_function_privilege('service_role',p.oid,'EXECUTE')
    ) as public_facade_exec_count,
    count(*) filter(
      where n.nspname='programacion'
        and has_function_privilege('service_role',p.oid,'EXECUTE')
    ) as internal_service_exec_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where p.proname in (
    'fn_input_governance_validator_validate_v1',
    'fn_input_governance_validate_v2',
    'fn_input_governance_validator_rebind_v1',
    'fn_input_governance_bootstrap_validate_v1'
  )
    and n.nspname in ('public','programacion')
)
select
  cp.first_five_done=5 as first_five_checkpoints_done,
  surfaces.service_role_executable_count=1 as one_service_role_entrypoint,
  surfaces.public_facade_exec_count=1 as public_facade_is_entrypoint,
  surfaces.internal_service_exec_count=0 as internal_strategies_closed,
  position('programacion.fn_input_governance_validator_validate_v1' in defs.facade_def)>0 as facade_routes_to_dispatcher,
  trg.enabled_guard_count=1 as persistence_oracle_guard_enabled,
  position('fn_input_evaluate_assertion' in defs.guard_def)>0
    and position('VALIDATOR_ASSERTION_FAILED' in defs.guard_def)>0 as persistence_guard_fail_closed,
  position('fn_input_rebind_assertion' in defs.builder_def)>0
    and position('V58_REBOUND_ASSERTION_FAILED' in defs.builder_def)>0 as builder_oracle_fail_closed
from cp cross join defs cross join trg cross join surfaces
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'COUNT_INTERNAL_STRATEGY_AS_PUBLIC_ENTRYPOINT',
        'INFER_ORACLE_ONLY_FROM_WRITER_UPDATE_TEXT',
        'REOPEN_COMPLETED_CHECKPOINTS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.2';
