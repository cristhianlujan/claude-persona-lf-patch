-- M7.11 CASES_50 contract repair.
-- REGISTER_SUITE already materialized the exact 50 governed cases.
-- CASES_50 verifies fixture + expected + adjudicated oracle and proves no M7.2 duplication.
-- It must not write the cases a second time.

do $pre$
begin
  if (
    select count(*)
    from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and metadata->>'unit_code'='M7.11'
      and metadata->>'checkpoint_code'='REGISTER_SUITE'
  ) <> 50 then
    raise exception 'M711_CASES50_REGISTERED_CASES_NOT_50';
  end if;
end;
$pre$;

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'CASES_50',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','CASES_50',
      'checkpoint_title','50/50 casos con fixture, esperado y oráculo; sin duplicar el golden de M7.2',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','READBACK_EXACT',
      'precision','EXPLICIT_M711_CASES50_READBACK_V1',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Verify exactly the 50 M7.11 governed Gold50 cases already materialized by REGISTER_SUITE: every case has fixture provenance, adjudicated expected output and adjudicated-v2 oracle, and none is owned by or duplicates M7.2.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_cases'
        ),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch@5fa5e98d0c8400d4d685c378043557d8f1f308a0:sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json',
            'role','ADJUDICATED_ORACLE_EVIDENCE'
          )
        ),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'case_count_exact',true,
          'fixture_complete',true,
          'expected_complete',true,
          'oracle_exact',true,
          'm72_overlap_zero',true,
          'test_type_exact',true,
          'owner_exact',true
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
with c as (
  select *
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'unit_code'='M7.11'
    and metadata->>'checkpoint_code'='REGISTER_SUITE'
), overlap as (
  select count(*) n
  from c
  join public.lf_test_suite_cases m72
    on m72.suite_code=c.suite_code
   and m72.test_code=c.test_code
   and m72.metadata->>'unit_code'='M7.2'
)
select
  count(*)=50 as case_count_exact,
  bool_and(
    coalesce(input_payload->>'mutation','')<>''
    and coalesce(input_payload->>'source_anchor','')<>''
    and coalesce(input_payload->>'rationale','')<>''
    and coalesce(input_payload->>'case_family','')<>''
  ) as fixture_complete,
  bool_and(
    coalesce(expected_output->>'decision','')<>''
    and jsonb_typeof(expected_output->'impact_families')='array'
    and jsonb_array_length(expected_output->'impact_families')>0
  ) as expected_complete,
  bool_and(
    expected_output->>'oracle_version'='INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2'
  ) as oracle_exact,
  (select n from overlap)=0 as m72_overlap_zero,
  bool_and(test_type='QUALIFICATION') as test_type_exact,
  bool_and(metadata->>'unit_code'='M7.11') as owner_exact
from c
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'REINSERT_GOLD50_CASES',
        'COPY_M7_2_GOLDEN_CASES',
        'CREATE_PARALLEL_SUITE',
        'MUTATE_TEST_CASES_DURING_READBACK',
        'AUTHORIZE_SCOPED_PASS',
        'AUTHORIZE_DOWNSTREAM',
        'AUTHORIZE_PRODUCTION'
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
  'IG-M711-REGISTER-CASES-SEPARATION-001',
  'INPUT_GOVERNANCE',
  'REGISTER_SUITE materializes Gold50; CASES_50 verifies it and must not reinsert',
  'M7.11 has consecutive checkpoints REGISTER_SUITE and CASES_50. Once REGISTER_SUITE materializes the 50 governed cases, CASES_50 is a readback of fixture, expected output, adjudicated oracle and non-duplication versus M7.2. Treating CASES_50 as another materialization would duplicate work and violate ownership clarity.',
  'Generic title inference classified CASES_50 as a material deliverable although its required artifact was already produced by the immediately previous checkpoint.',
  'CONSECUTIVE_CHECKPOINT_REINSERTS_ALREADY_MATERIALIZED_DELIVERABLE',
  'Author an explicit readback Action Spec whenever a later checkpoint only verifies a deliverable materialized by an earlier checkpoint in the same unit. Do not carry materialization semantics forward from the title.',
  'PASS when CASES_50 compiles to READ/VERIFY_QUERY_ONCE, exact readback returns 50 cases, all fixtures/expected/oracles are complete, M7.2 overlap is zero, and no case mutation occurs.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.11; supabase://public.lf_test_suite_cases',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M7.11 CASES_50',
  'supabase://programacion.fn_engineering_checkpoint_action_spec_v3'
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
