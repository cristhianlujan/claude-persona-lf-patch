-- Re-anchor live IG plan contract sanitation in Git migration authority.
-- Idempotent by design: desired metadata already exists live; this migration makes it reproducible from source.

do $pre$
begin
  if not exists (
    select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code in ('M5.6','M5.9','M6.7','M8.5','M10.5','T-PRIVACY','M8.10','M9.7','M10.13','M5.10','M6.13')
    group by plan_code
    having count(*)=11
  ) then
    raise exception 'BLOCK_IG_CONTRACT_METADATA_UNITS_MISSING';
  end if;

  if exists (
    select 1
    from programacion.engineering_plan_units u
    join programacion.engineering_work_items w on w.id=u.work_item_id
    where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and u.unit_code in ('M0.6','M7.2','M6.0','T-EVID','M3.4','M1.4')
      and w.status<>'DONE'
  ) then
    raise exception 'BLOCK_IG_CONSUMPTION_UPSTREAM_NOT_DONE';
  end if;
end
$pre$;

-- Six checkpoints are consumers/readbacks, not writers.
with fixes(unit_code,checkpoint_code,reason) as (
  values
    ('M5.6','GOLDEN_BOUND','CONSUME_UPSTREAM_GOLDEN'),
    ('M5.9','RECEIPT_MODEL','CONSUME_CANONICAL_RECEIPT_MODEL'),
    ('M6.7','RECEIPT_MODEL','CONSUME_CANONICAL_RECEIPT_MODEL'),
    ('M8.5','ELIGIBILITY_SOURCE','CONSUME_ELIGIBILITY_REGISTRY'),
    ('M10.5','PERF_M8_GREEN','READBACK_UPSTREAM_PERFORMANCE_RECEIPTS'),
    ('T-PRIVACY','IG_BINDING','VERIFY_CONSUMER_BINDING')
), src as (
  select u.unit_code,f.checkpoint_code,f.reason,c.title,
         coalesce(
           u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',f.checkpoint_code],
           u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',f.checkpoint_code],
           '{}'::jsonb
         ) s
  from fixes f
  join programacion.engineering_plan_units u
    on u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   and u.unit_code=f.unit_code
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=u.work_item_id
   and c.checkpoint_code=f.checkpoint_code
), specs as (
  select unit_code,checkpoint_code,
         jsonb_build_object(
           'status','READY',
           'precision','EXPLICIT_CONSUMPTION_READBACK',
           'action_kind','READBACK_ONCE',
           'recipe_mode','READBACK_EXACT',
           'requires_material_execution',false,
           'mutation_policy','NO_DOMAIN_MUTATION',
           'target',jsonb_build_object(
             'checkpoint',checkpoint_code,
             'declared_objects',coalesce(s#>'{inputs,db_objects}','[]'::jsonb),
             'declared_assets',coalesce(s#>'{inputs,assets}','[]'::jsonb),
             'declared_artifacts','[]'::jsonb,
             'declared_events',coalesce(s#>'{inputs,events}','[]'::jsonb)
           ),
           'verification_queries',coalesce(s#>'{inputs,queries}','[]'::jsonb),
           'expected',title,
           'action_steps',jsonb_build_array(
             'READ_DECLARED_AUTHORITY_ONCE',
             'ASSERT_EXACT_STATE',
             'PERSIST_CHECKPOINT_ONLY',
             'USE_RETURNED_BOOTSTRAP'
           ),
           'contract_reason',reason,
           'forbidden',jsonb_build_array(
             'INFER_WRITE_FROM_READBACK',
             'REEXECUTE_DEPENDENCY_OWNED_TESTS',
             'MUTATE_DOMAIN_DATA'
           )
         ) spec
  from src
)
update programacion.engineering_plan_units u
set unit_metadata=jsonb_set(
      u.unit_metadata,
      '{action_specs_v1}',
      coalesce(u.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(s.checkpoint_code,s.spec),
      true
    )
from specs s
where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and u.unit_code=s.unit_code;

-- Historical missing markers resolved by completed canonical dependencies are not blockers.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(unit_metadata,'{source_pack_v1,checkpoint_inputs,GOLDEN_BOUND,missing_typed}','[]'::jsonb,true)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M5.6';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(unit_metadata,'{source_pack_v1,checkpoint_inputs,RECEIPT_MODEL,missing_typed}','[]'::jsonb,true)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code in ('M5.9','M6.7');

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(unit_metadata,'{source_pack_v1,checkpoint_inputs,ELIGIBILITY_SOURCE,missing_typed}','[]'::jsonb,true)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M8.5';

-- M8.10: real missing deliverables/adapters stay fail-closed; declared capability routes remain inactive until authored.
update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    jsonb_set(
      unit_metadata,
      '{action_specs_v1}',
      coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'CORPUS_FIXED',jsonb_build_object(
          'status','BLOCK_BENCHMARK_CORPUS_CONTRACT_NOT_AUTHORED',
          'precision','EXPLICIT_MATERIAL_DELIVERABLE_REQUIRED',
          'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
          'recipe_mode','GIT_FIRST_OR_VERSIONED_CONTRACT',
          'requires_material_execution',true,
          'mutation_policy','ONLY_DECLARED_TARGETS',
          'target',jsonb_build_object(
            'checkpoint','CORPUS_FIXED',
            'declared_objects',jsonb_build_array('lf_ops.pantallas','programacion.input_readiness_runs'),
            'declared_assets','[]'::jsonb,'declared_artifacts','[]'::jsonb,'declared_events','[]'::jsonb
          ),
          'expected','Define one canonical versioned benchmark corpus contract (screens x fixtures) with deterministic SHA and exact-source reference before T-PERF execution; do not infer the corpus from the live universe at runtime.',
          'forbidden',jsonb_build_array('INFER_WRITE_FROM_READ_QUERIES','DIRECT_UNVERSIONED_MUTATION','CREATE_PARALLEL_AUTHORITY','SYNTHETIC_READY_WITHOUT_DELIVERABLE')
        ),
        'BENCH_VIA_TPERF',jsonb_build_object(
          'status','BLOCK_CONSUMER_ADAPTER_MISSING',
          'precision','EXPLICIT_TRANSVERSAL_CONSUMER_ADAPTER_REQUIRED',
          'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
          'requires_material_execution',true,
          'mutation_policy','NO_DOMAIN_MUTATION',
          'expected','M8.10 consumer adapter must bind the M8.1 phase model to executable callables and invoke PERFORMANCE_EXACT_SOURCE_BENCHMARK against an exact source SHA; fixture lambdas are forbidden.',
          'forbidden',jsonb_build_array('HARDCODE_TEST_FIXTURE_PHASES','INVENT_PHASE_CALLABLES','BYPASS_T_PERF')
        ),
        'PHASE_BUDGET',jsonb_build_object(
          'status','BLOCK_CONSUMER_ADAPTER_MISSING',
          'precision','EXPLICIT_TRANSVERSAL_CONSUMER_ADAPTER_REQUIRED',
          'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
          'requires_material_execution',true,
          'mutation_policy','NO_DOMAIN_MUTATION',
          'expected','M8.10 consumer adapter must feed the exact benchmark receipt and M8.1 phase policy into TIMEOUT_PHASE_BUDGET_POLICY; blind timeout extension is forbidden.',
          'forbidden',jsonb_build_array('HARDCODE_TEST_POLICY','BLIND_TIMEOUT_EXTENSION','BYPASS_T_PERF')
        )
      ),
      true
    ),
    '{transversal_execution_v1}',
    coalesce(unit_metadata->'transversal_execution_v1','{}'::jsonb)
    || jsonb_build_object(
      'BENCH_VIA_TPERF',jsonb_build_object(
        'mode','EXPLICIT','activation','DECLARED_ONLY',
        'capabilities',jsonb_build_array(jsonb_build_object('handler','REPOSITORY_CAPABILITY_EXECUTOR','capability_code','PERFORMANCE_EXACT_SOURCE_BENCHMARK')),
        'execution_order','PLAN_ORDER_ONE_BY_ONE','admission_required',false,'dependency_resolution','MANIFEST_GRAPH'
      ),
      'PHASE_BUDGET',jsonb_build_object(
        'mode','EXPLICIT','activation','DECLARED_ONLY',
        'capabilities',jsonb_build_array(jsonb_build_object('handler','REPOSITORY_CAPABILITY_EXECUTOR','capability_code','TIMEOUT_PHASE_BUDGET_POLICY')),
        'execution_order','PLAN_ORDER_ONE_BY_ONE','admission_required',false,'dependency_resolution','MANIFEST_GRAPH'
      )
    ),
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M8.10';

-- M9.7: schema registration is Git-first; receipt producer is separate real implementation work.
update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    jsonb_set(
      unit_metadata,
      '{action_specs_v1}',
      coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'TYPED_SCHEMA',jsonb_build_object(
          'status','BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED',
          'precision','EXPLICIT_GIT_FIRST_TYPED_SCHEMA_REGISTRATION',
          'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
          'recipe_mode','GIT_FIRST_MIGRATION',
          'requires_material_execution',true,
          'mutation_policy','ONLY_DECLARED_TARGETS',
          'target',jsonb_build_object(
            'checkpoint','TYPED_SCHEMA',
            'declared_objects',jsonb_build_array('private.lf_typed_evidence_schema_registry_v3','private.fn_lf_typed_evidence_payload_valid_v3'),
            'declared_assets',jsonb_build_array('TYPED_EVIDENCE_REGISTRY'),
            'declared_artifacts','[]'::jsonb,'declared_events','[]'::jsonb
          ),
          'material_contract',jsonb_build_object(
            'pattern_ref','M3.7/SCHEMA_DEFINE_REGISTER',
            'git_first_required',true,
            'registration_store','private.lf_typed_evidence_schema_registry_v3',
            'validation_entrypoint','private.fn_lf_typed_evidence_payload_valid_v3',
            'migration_train_required',true
          ),
          'expected','Register one versioned shadow-receipt schema in the canonical typed registry and extend the canonical validator in the same Git-first migration; no new table and no direct registry mutation outside migration.',
          'forbidden',jsonb_build_array('CALL_VALIDATOR_AS_SCHEMA_REGISTRAR','CREATE_PARALLEL_TYPED_EVIDENCE_TABLE','DIRECT_UNVERSIONED_REGISTRY_INSERT','SYNTHETIC_READY_WITHOUT_MIGRATION_ARTIFACT')
        ),
        'RECEIPT_FIELDS',jsonb_build_object(
          'status','BLOCK_SHADOW_RECEIPT_PRODUCER_NOT_IMPLEMENTED',
          'precision','EXPLICIT_CONSUMER_ADAPTER_REQUIRED',
          'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
          'recipe_mode','CAPABILITY_CONSUMER_ADAPTER',
          'requires_material_execution',true,
          'mutation_policy','CAPABILITY_OWNED_EFFECTS_ONLY',
          'target',jsonb_build_object(
            'checkpoint','RECEIPT_FIELDS',
            'declared_objects','[]'::jsonb,
            'declared_assets',jsonb_build_array('EVIDENCE_LEDGER','TYPED_EVIDENCE_REGISTRY'),
            'declared_artifacts','[]'::jsonb,'declared_events','[]'::jsonb
          ),
          'expected','After TYPED_SCHEMA exists, implement the shadow receipt producer carrying CURRENT/CANDIDATE release refs, source snapshot SHA, comparison and duration into the canonical evidence plane.',
          'forbidden',jsonb_build_array('GENERIC_WRITE_DB','CREATE_PARALLEL_ENGINE','REEXECUTE_DEPENDENCY_OWNED_TESTS','SYNTHETIC_RECEIPT')
        )
      ),
      true
    ),
    '{transversal_execution_v1,TYPED_SCHEMA}',
    'null'::jsonb,
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7';

-- Remove null key to leave no stale transversal execution for TYPED_SCHEMA.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{transversal_execution_v1}',
  coalesce(unit_metadata->'transversal_execution_v1','{}'::jsonb) - 'TYPED_SCHEMA',
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7';

-- M10.13: MIGRATION_SOURCE_PARITY inputs are references resolved by the capability-owned runner, not literal snapshots.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,GIT_RUNTIME_PARITY}',
  jsonb_build_object(
    'mode','EXPLICIT','activation','ACTIVE',
    'capabilities',jsonb_build_array(jsonb_build_object(
      'handler','REPOSITORY_CAPABILITY_EXECUTOR',
      'capability_code','MIGRATION_SOURCE_PARITY',
      'execution_input',jsonb_build_object(
        'local',jsonb_build_object('source','CURRENT_REPOSITORY_MIGRATIONS','resolver','CAPABILITY_OWNED_RUNNER','runner_ref','sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py'),
        'remote',jsonb_build_object('source','SUPABASE_MIGRATION_LEDGER_CURRENT','resolver','CAPABILITY_OWNED_RUNNER','runner_ref','sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py'),
        'statement_counts',jsonb_build_object('source','SUPABASE_MIGRATION_LEDGER_CARDINALITY','resolver','CAPABILITY_OWNED_RUNNER','runner_ref','sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py'),
        'runner_ref','sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py',
        'execution_mode','FULL_CURRENT_STATE',
        'base_ref','main',
        'resolve_base_sha','CURRENT_MAIN',
        'resolve_head_sha','CURRENT_REPOSITORY_HEAD',
        'literal_snapshot_payload','FORBIDDEN'
      )
    )),
    'execution_order','PLAN_ORDER_ONE_BY_ONE',
    'admission_required',false,
    'dependency_resolution','MANIFEST_GRAPH'
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.13';

-- M5/M6 closure checkpoints execute the existing post-PASE router/orchestrator sequence.
with x(unit_code,checkpoint_code,scope_code,source_checkpoint) as (
  values
    ('M5.10','FINAL_EVIDENCE_SADM','IG_M5_CLOSURE','M5_UNITS_READBACK'),
    ('M6.13','FINAL_EVIDENCE_SADM','IG_M6_CLOSURE','M6_UNITS_READBACK')
)
update programacion.engineering_plan_units u
set unit_metadata=jsonb_set(
  u.unit_metadata,
  array['transversal_execution_v1',x.checkpoint_code],
  jsonb_build_object(
    'mode','EXPLICIT','activation','ACTIVE',
    'capabilities',jsonb_build_array(
      jsonb_build_object(
        'handler','REPOSITORY_CAPABILITY_EXECUTOR',
        'capability_code','POST_PASE_ROUTER',
        'execution_input',jsonb_build_object('capability_input',jsonb_build_object(
          'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
          'input_contract','LF_POST_PASE_ROUTER_REQUEST_V1',
          'scope_code',x.scope_code,
          'source_checkpoint',x.source_checkpoint,
          'resolution','CURRENT_UNIT_STATE_PLUS_CURRENTNESS_AUTHORITY',
          'literal_payload','FORBIDDEN'
        ))
      ),
      jsonb_build_object(
        'handler','REPOSITORY_CAPABILITY_EXECUTOR',
        'capability_code','POST_PASE_ORCHESTRATOR',
        'execution_input',jsonb_build_object('capability_input',jsonb_build_object(
          'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
          'input_contract','LF_POST_PASE_PLAN_V1',
          'scope_code',x.scope_code,
          'source','PREVIOUS_TRANSVERSAL_STEP_OUTPUT',
          'resolution','EXACT_IMMUTABLE_PLAN_FROM_POST_PASE_ROUTER',
          'literal_payload','FORBIDDEN'
        ))
      )
    ),
    'execution_order','PLAN_ORDER_ONE_BY_ONE',
    'admission_required',false,
    'dependency_resolution','MANIFEST_GRAPH'
  ),
  true
)
from x
where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and u.unit_code=x.unit_code;

-- Fail if the source-anchored result does not compile to the intended semantics.
do $verify$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from (values
    ('M5.6','GOLDEN_BOUND','READY','READBACK_ONCE'),
    ('M5.9','RECEIPT_MODEL','READY','READBACK_ONCE'),
    ('M6.7','RECEIPT_MODEL','READY','READBACK_ONCE'),
    ('M8.5','ELIGIBILITY_SOURCE','READY','READBACK_ONCE'),
    ('M10.5','PERF_M8_GREEN','READY','READBACK_ONCE'),
    ('T-PRIVACY','IG_BINDING','READY','READBACK_ONCE'),
    ('M8.10','CORPUS_FIXED','BLOCK_BENCHMARK_CORPUS_CONTRACT_NOT_AUTHORED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.10','BENCH_VIA_TPERF','BLOCK_CONSUMER_ADAPTER_MISSING','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.10','PHASE_BUDGET','BLOCK_CONSUMER_ADAPTER_MISSING','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M9.7','TYPED_SCHEMA','BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M9.7','RECEIPT_FIELDS','BLOCK_SHADOW_RECEIPT_PRODUCER_NOT_IMPLEMENTED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.13','GIT_RUNTIME_PARITY','READY','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION'),
    ('M5.10','FINAL_EVIDENCE_SADM','READY','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION'),
    ('M6.13','FINAL_EVIDENCE_SADM','READY','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION')
  ) e(unit_code,checkpoint_code,expected_status,expected_kind)
  where (
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',e.unit_code,e.checkpoint_code
    )->>'status',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',e.unit_code,e.checkpoint_code
    )->>'action_kind'
  ) is distinct from (e.expected_status,e.expected_kind);

  if v_bad<>0 then
    raise exception 'BLOCK_IG_CONTRACT_METADATA_SOURCE_PARITY:%',v_bad;
  end if;
end
$verify$;
