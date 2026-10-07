-- M7.11 NEG_CASE_MUTATED contract and owned negative case.
-- No persistent mutation of the 50 governed Gold50 cases.

do $pre$
begin
  if not exists (
    select 1
    from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and test_code='CI-API-04'
      and metadata->>'unit_code'='M7.11'
      and expected_output->>'decision'='HUMAN_REQUIRED'
  ) then
    raise exception 'M711_NEG_API04_CANONICAL_SOURCE_NOT_READY';
  end if;

  if exists (
    select 1
    from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and (
        test_code='M711_NEG_API04_EXPECTED_MUTATION'
        or test_order=711051
      )
  ) then
    raise exception 'M711_NEG_TEST_ID_OR_ORDER_ALREADY_USED';
  end if;
end;
$pre$;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
values (
  'INPUT_GOVERNANCE_REGRESSION',
  'M711_NEG_API04_EXPECTED_MUTATION',
  711051,
  array[]::text[],
  'M7.11 negative — adjudicated CI-API-04 expected decision mutated',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'CI-API-04 exists as an M7.11 governed Gold50 case',
    'CI-API-04 adjudicated decision is HUMAN_REQUIRED',
    'mutation is transaction-local and must not update the governed case'
  ),
  jsonb_build_object(
    'schema_version','M711_NEG_MUTATED_EXPECTED_FIXTURE_V1',
    'fixture_kind','EXPECTED_OUTPUT_MUTATION',
    'source_case','CI-API-04',
    'source_oracle','INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2',
    'canonical_decision','HUMAN_REQUIRED',
    'mutated_decision','GLOBAL_ESCALATE',
    'side_effects',false,
    'rollback_required',true
  ),
  jsonb_build_object(
    'decision','REJECT_EXPECTED_DRIFT',
    'typed_finding','M711_GOLD_EXPECTED_DECISION_DRIFT'
  ),
  jsonb_build_object(
    'false_pass',true,
    'untyped_failure',true,
    'persistent_gold_case_mutation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M7.11',
    'work_code','PAULO-064',
    'checkpoint_code','NEG_CASE_MUTATED',
    'source_case','CI-API-04',
    'source_adjudication_blob_sha','32ec59b23a70e09b77245579145233a5ee462c11',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_incremental/m711_neg_mutated_expected_v1.sql'
  ),
  'CHATGPT-IG-M711-NEG-MUTATED-20261007',
  'CHATGPT-IG-M711-NEG-MUTATED-20261007'
);

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'NEG_CASE_MUTATED',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','NEG_CASE_MUTATED',
      'checkpoint_title','Negativo: un caso con esperado alterado falla',
      'action_kind','DECLARED_TEST_EXECUTION',
      'recipe_mode','RUN_EXACT_TEST_SET',
      'precision','EXPLICIT_M711_NEG_MUTATED_EXPECTED_V1',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',true,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Execute exactly one M7.11-owned negative case. Mutating CI-API-04 expected decision from adjudicated HUMAN_REQUIRED to GLOBAL_ESCALATE must be detected with typed finding M711_GOLD_EXPECTED_DECISION_DRIFT; the governed Gold50 row must remain unchanged.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_cases',
          'programacion.fn_engineering_run_test_persist_v1'
        ),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_incremental/m711_neg_mutated_expected_v1.sql',
            'role','TEST_HARNESS_EVIDENCE'
          )
        ),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'test_case_codes',jsonb_build_array(
        'M711_NEG_API04_EXPECTED_MUTATION'
      ),
      'test_case_set_sha256',programacion.fn_v09_sha256_jsonb(
        jsonb_build_array('M711_NEG_API04_EXPECTED_MUTATION')
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'tests_total',1,
          'tests_passed',1,
          'tests_failed',0,
          'tests_blocked',0,
          'tests_review_required',0,
          'receipt_bundle_status','VERIFIED',
          'typed_finding','M711_GOLD_EXPECTED_DECISION_DRIFT',
          'canonical_decision_unchanged','HUMAN_REQUIRED'
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
select
  count(*)=1 as negative_case_registered,
  max(input_payload->>'canonical_decision')='HUMAN_REQUIRED' as canonical_decision_exact,
  max(input_payload->>'mutated_decision')='GLOBAL_ESCALATE' as mutation_exact,
  max(expected_output->>'typed_finding')='M711_GOLD_EXPECTED_DECISION_DRIFT' as typed_finding_exact
from public.lf_test_suite_cases
where suite_code='INPUT_GOVERNANCE_REGRESSION'
  and test_code='M711_NEG_API04_EXPECTED_MUTATION'
  and metadata->>'unit_code'='M7.11'
  and metadata->>'checkpoint_code'='NEG_CASE_MUTATED'
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'MUTATE_GOVERNED_GOLD50_ROW',
        'DISCOVER_EXTRA_TEST_CASES',
        'EXECUTE_FOREIGN_UNIT_TEST_CASES',
        'UNTYPED_FAILURE',
        'SYNTHETIC_PASS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M7.11'
  and disposition='ASSIGNED';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-M711-EXPECTED-DRIFT-NEGATIVE-001',
  'INPUT_GOVERNANCE',
  'Gold50 negative test must detect expected-output drift without mutating governed case',
  'M7.11 NEG_CASE_MUTATED uses CI-API-04 because adjudication v2 corrected it to HUMAN_REQUIRED. A transaction-local mutation to GLOBAL_ESCALATE must be rejected with typed finding M711_GOLD_EXPECTED_DECISION_DRIFT. The persisted Gold50 row is never changed.',
  'The checkpoint required a negative case but the source pack only exposed aggregate suite reads and no exact mutation/oracle contract.',
  'NEGATIVE_EXPECTED_DRIFT_WITHOUT_EXACT_CASE_OR_TYPED_ORACLE',
  'Own one exact negative test case in M7.11, mutate only an in-memory or rollback copy, compare against adjudicated authority, persist the test receipt, and prohibit changes to the governed Gold50 row.',
  'PASS when the harness reports the typed drift finding, canonical CI-API-04 remains HUMAN_REQUIRED, exact one-case suite run is VERIFIED, and no governed Gold50 row is mutated.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_incremental/m711_neg_mutated_expected_v1.sql; supabase://public.lf_test_suite_cases/CI-API-04',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M7.11 NEG_CASE_MUTATED',
  'supabase://public.lf_test_suite_cases'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
