-- ENGINEERING contract reduction: bounded materialization authoring v1
-- Root fix: construction checkpoints must be executable before their future
-- output artifact exists. The contract bounds repository roots, DB targets,
-- readbacks and assertion receipt; the worker resolves the concrete filename
-- before WRITE_GIT.

create or replace function programacion.fn_engineering_bounded_materialization_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb,
  p_authoring_mode text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_target jsonb := coalesce(v_spec->'target','{}'::jsonb);
  v_evidence jsonb := coalesce(v_target->'evidence_artifacts',v_target->'declared_artifacts','[]'::jsonb);
  v_mutation jsonb := '[]'::jsonb;
  v_queries jsonb := coalesce(v_spec->'verification_queries','[]'::jsonb);
  v_mode text := upper(coalesce(p_authoring_mode,''));
  v_has_migration boolean := false;
begin
  if v_mode not in (
    'MIGRATION',
    'MIXED_CURATOR_MIGRATION',
    'EDGE_VALIDATOR_AGENT',
    'MIXED_THREE_EDGE_MIGRATION',
    'SANDBOX_FIXTURE_MIGRATION'
  ) then
    raise exception 'ENGINEERING_BOUNDED_AUTHORING_MODE_UNSUPPORTED:%',p_authoring_mode;
  end if;

  if v_mode in ('MIGRATION','MIXED_CURATOR_MIGRATION','MIXED_THREE_EDGE_MIGRATION','SANDBOX_FIXTURE_MIGRATION') then
    v_mutation:=v_mutation||jsonb_build_array(jsonb_build_object(
      'path','cristhianlujan/claude-persona-lf-patch:supabase/migrations/',
      'role','MUTATION_TARGET',
      'target_kind','ALLOWED_OUTPUT_ROOT',
      'resolve_concrete_path_before_write',true,
      'naming_contract','<timestamp>_ig_'||
        lower(replace(replace(p_unit_code,'.','_'),'-','_'))||'_'||
        lower(replace(p_checkpoint_code,'-','_'))||'.sql'
    ));
    v_has_migration:=true;
  end if;

  if v_mode='MIXED_CURATOR_MIGRATION' then
    v_mutation:=v_mutation||jsonb_build_array(jsonb_build_object(
      'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-curator-v1/index.ts',
      'role','MUTATION_TARGET',
      'target_kind','EXACT_FILE'
    ));
  elsif v_mode='EDGE_VALIDATOR_AGENT' then
    v_mutation:=v_mutation
      ||jsonb_build_array(
        jsonb_build_object(
          'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-validator-v1/index.ts',
          'role','MUTATION_TARGET','target_kind','EXACT_FILE'
        ),
        jsonb_build_object(
          'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-agent-v1/index.ts',
          'role','MUTATION_TARGET','target_kind','EXACT_FILE'
        )
      );
  elsif v_mode='MIXED_THREE_EDGE_MIGRATION' then
    v_mutation:=v_mutation
      ||jsonb_build_array(
        jsonb_build_object(
          'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-agent-v1/index.ts',
          'role','MUTATION_TARGET','target_kind','EXACT_FILE'
        ),
        jsonb_build_object(
          'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-curator-v1/index.ts',
          'role','MUTATION_TARGET','target_kind','EXACT_FILE'
        ),
        jsonb_build_object(
          'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-validator-v1/index.ts',
          'role','MUTATION_TARGET','target_kind','EXACT_FILE'
        )
      );
  elsif v_mode='SANDBOX_FIXTURE_MIGRATION' then
    v_mutation:=v_mutation||jsonb_build_array(jsonb_build_object(
      'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/input_governance_e2e/',
      'role','MUTATION_TARGET',
      'target_kind','ALLOWED_OUTPUT_ROOT',
      'resolve_concrete_path_before_write',true
    ));
  end if;

  v_target:=v_target||jsonb_build_object(
    'evidence_artifacts',v_evidence,
    'mutation_artifacts',v_mutation,
    'declared_artifacts',v_mutation
  );

  return (
    v_spec
    || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','BOUNDED_IMPLEMENTATION_AUTHORING_V1',
      'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
      'recipe_mode',case when v_has_migration then 'GIT_FIRST_MIGRATION' else 'BOUNDED_IMPLEMENTATION_AUTHORING' end,
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'contract_family','BOUNDED_IMPLEMENTATION_AUTHORING',
      'target',v_target,
      'verification_queries',v_queries,
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'implementation_written',true,
          'git_merged',true,
          'readback_passed',true
        )
      ),
      'authoring_contract',jsonb_build_object(
        'mode',v_mode,
        'concrete_output_path_required_before_write',true,
        'allowed_roots_only',true,
        'db_targets_exact',coalesce(v_target->'declared_objects','[]'::jsonb),
        'verification_queries_required',jsonb_array_length(v_queries)>0,
        'git_route','SCOPED_BRANCH_PR_MERGE',
        'direct_main_write','FORBIDDEN',
        'synthetic_pass','FORBIDDEN',
        'post_merge_readback_required',true,
        'runtime_activation','NOT_IMPLIED'
      ),
      'expected','Implement the canonical checkpoint outcome only inside the declared Git roots/DB targets, merge through governed Git flow, then prove the declared readback before DONE.'
    )
  ) - 'required_contract';
end;
$function$;

comment on function programacion.fn_engineering_bounded_materialization_spec_v1(text,text,text,jsonb,text)
is 'Reusable bounded construction compiler. It makes real implementation work scheduler-executable without requiring the future file to exist beforehand; exact roots, DB targets, governed Git route, readback and assertion receipt remain mandatory.';

do $bind$
declare
  r record;
  v_spec jsonb;
  v_new jsonb;
begin
  for r in
    select * from (values
      ('M10.1','PROFILES_ADAPTERS_CONSUMERS','MIGRATION'),
      ('M10.1','ROUTER_MIGRATED','MIGRATION'),
      ('M10.11','REVOKE_MIGRATION','MIGRATION'),
      ('M10.12','BATCH_DROP_NO_CASCADE','MIGRATION'),
      ('M10.2','SWITCH_ONLY_MIGRATION','MIGRATION'),
      ('M5.2','DECISION_TABLE','MIGRATION'),
      ('M5.2','NO_REVISION_LITERALS','MIGRATION'),
      ('M5.2','PLAN_EXECUTE_SPLIT','MIXED_CURATOR_MIGRATION'),
      ('M5.3','CANARY_FORMALIZED','MIXED_CURATOR_MIGRATION'),
      ('M5.3','CONTEXT_OBJECT','MIXED_CURATOR_MIGRATION'),
      ('M5.3','ONE_GRAPH_COUNT','MIXED_CURATOR_MIGRATION'),
      ('M5.4','CORE_INVOCATION','MIXED_CURATOR_MIGRATION'),
      ('M5.4','SEMANTIC_PLAN_RESOLVERS','MIXED_CURATOR_MIGRATION'),
      ('M5.5','EXPLICIT_FINGERPRINT','MIGRATION'),
      ('M5.5','TRIGGER_VERIFY_ONLY','MIGRATION'),
      ('M5.6','SINGLE_PIPELINE','MIGRATION'),
      ('M5.8','APPLY_POLICY','MIGRATION'),
      ('M5.8','POLICY_DECLARED','MIGRATION'),
      ('M5.9','PERSIST_RECEIPT','MIXED_CURATOR_MIGRATION'),
      ('M6.10','API_CONTRACT','MIGRATION'),
      ('M6.10','READONLY_IMPL','MIGRATION'),
      ('M6.12','MANIFEST_VIEW','MIGRATION'),
      ('M6.2','GRAPH_SHA_RECEIPT','MIGRATION'),
      ('M6.7','INHERIT_PARENT_SHA','MIGRATION'),
      ('M7.10','FIXTURES','SANDBOX_FIXTURE_MIGRATION'),
      ('M7.12','SUITE_REGISTER_MIGRATION','MIGRATION'),
      ('M7.13','CRITERIA_AS_CONTROLS','MIGRATION'),
      ('M7.9','REBIND_CASES','MIGRATION'),
      ('M8.11','RECEIPT_PER_RUN','MIXED_THREE_EDGE_MIGRATION'),
      ('M8.2','PER_FAMILY_RESOLVER','MIXED_CURATOR_MIGRATION'),
      ('M8.2','TIMING_SINK','MIGRATION'),
      ('M8.5','JIT_EXEC','MIXED_CURATOR_MIGRATION'),
      ('M8.6','BATCH_COMMON','MIGRATION'),
      ('M8.8','DEADLINE_CHUNKING','EDGE_VALIDATOR_AGENT'),
      ('N-6','DERIVE_FROM_RULE','MIGRATION')
    ) x(unit_code,checkpoint_code,authoring_mode)
  loop
    select pu.unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    if v_spec is null then
      raise exception 'ENGINEERING_BOUNDED_AUTHORING_SPEC_MISSING:%/%',r.unit_code,r.checkpoint_code;
    end if;

    v_new:=programacion.fn_engineering_bounded_materialization_spec_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',
      r.unit_code,
      r.checkpoint_code,
      v_spec,
      r.authoring_mode
    );

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         pu.unit_metadata,
         '{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           || jsonb_build_object(r.checkpoint_code,v_new),
         true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';
  end loop;

  -- Clear stale dependency notes whose producer is already DONE.
  update programacion.engineering_plan_units pu
  set unit_metadata=
    jsonb_set(
      jsonb_set(
        pu.unit_metadata,
        '{source_pack_v1,checkpoint_inputs,CORE_INVOCATION,missing}',
        '[]'::jsonb,true
      ),
      '{source_pack_v1,checkpoint_inputs,CORE_INVOCATION,missing_typed}',
      '[]'::jsonb,true
    )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M5.4';

  update programacion.engineering_plan_units pu
  set unit_metadata=
    jsonb_set(
      jsonb_set(
        pu.unit_metadata,
        '{source_pack_v1,checkpoint_inputs,ONE_GRAPH_COUNT,missing}',
        '[]'::jsonb,true
      ),
      '{source_pack_v1,checkpoint_inputs,ONE_GRAPH_COUNT,missing_typed}',
      '[]'::jsonb,true
    )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M5.3';

  update programacion.engineering_plan_units pu
  set unit_metadata=
    jsonb_set(
      jsonb_set(
        pu.unit_metadata,
        '{source_pack_v1,checkpoint_inputs,FIXTURES,missing}',
        '[]'::jsonb,true
      ),
      '{source_pack_v1,checkpoint_inputs,FIXTURES,missing_typed}',
      '[]'::jsonb,true
    )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M7.10';

  -- True upstream owner binding, not construction.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object(
        'BUNDLE_M9_BINDING',
        (pu.unit_metadata#>'{action_specs_v1,BUNDLE_M9_BINDING}')
          ||jsonb_build_object(
            'status','BLOCK_UPSTREAM_OWNER_BINDING_PENDING',
            'precision','EXPLICIT_OWNER_BUNDLE_BINDING_V1',
            'action_kind','DECISION_GATE',
            'recipe_mode','OWNER_BUNDLE_BINDING_GATE_V1',
            'requires_material_execution',false,
            'contract_family','UPSTREAM_OWNER_BINDING_PENDING',
            'binding_contract',jsonb_build_object(
              'producer_bundle_unit','M9.0',
              'cutover_receipt_unit','M9.12',
              'decision','CUTOVER_AUTHORIZED',
              'decision_table','programacion.human_decisions',
              'head_sha_must_equal_bundle',true,
              'cutover_ready_receipt_required',true
            )
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.0';

  -- Archived bundle is a readback after M9.0 exists, not a new materialization.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object(
        'ARCHIVED_BUNDLE_RECOVERABLE',
        (pu.unit_metadata#>'{action_specs_v1,ARCHIVED_BUNDLE_RECOVERABLE}')
          ||jsonb_build_object(
            'status','BLOCK_UPSTREAM_BUNDLE_PENDING',
            'precision','EXPLICIT_ARCHIVED_BUNDLE_READBACK_V1',
            'action_kind','READBACK_ONCE',
            'recipe_mode','UPSTREAM_BUNDLE_RECOVERABILITY_GATE_V1',
            'requires_material_execution',false,
            'contract_family','UPSTREAM_BUNDLE_PENDING',
            'upstream_contract',jsonb_build_object(
              'producer_unit','M9.0',
              'readback','GIT_EXACT_SHA_RECOVERABLE',
              'rebuild','FORBIDDEN'
            )
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.8';

  -- Material-looking run/correlation checkpoints are tests.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object(
        'NEW_RUNS_VNEXT',
        (pu.unit_metadata#>'{action_specs_v1,NEW_RUNS_VNEXT}')
          ||jsonb_build_object(
            'status','BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
            'precision','RECLASSIFIED_EXACT_TEST_EXECUTION_V1',
            'action_kind','DECLARED_TEST_EXECUTION',
            'contract_family','TEST_EXECUTION_CONTRACT_REQUIRED',
            'test_scope_contract',jsonb_build_object(
              'suite_code','INPUT_GOVERNANCE_REGRESSION',
              'screen_scope','13_CANONICAL_SCREENS',
              'release','VNEXT_CURRENT_CANDIDATE',
              'fresh_runs_required',true
            )
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.5';

  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object(
        'CORRELATION_RERUN',
        (pu.unit_metadata#>'{action_specs_v1,CORRELATION_RERUN}')
          ||jsonb_build_object(
            'status','BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
            'precision','RECLASSIFIED_CORRELATION_TEST_V1',
            'action_kind','DECLARED_TEST_EXECUTION',
            'contract_family','AUTHORED_TEST_DRILL_REQUIRED',
            'test_scope_contract',jsonb_build_object(
              'authority','M4.1_CORRELATION_INVENTORY',
              'subject','CURRENT_VALIDATOR',
              'pass_condition','ZERO_SHARED_CONCLUSION_DEPENDENCIES'
            )
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M4.12';

  -- Full pipeline candidate belongs to T-EQUIV scope authoring, not DB materialization.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object(
        'FULL_PIPELINE_CANDIDATE',
        (pu.unit_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}')
          ||jsonb_build_object(
            'status','BLOCK_TRANSVERSAL_SHADOW_SCOPE_CONTRACT_REQUIRED',
            'precision','EXPLICIT_T_EQUIV_SCOPE_REQUIRED_V1',
            'action_kind','DECLARED_CAPABILITY_TEST_EXECUTION',
            'contract_family','TRANSVERSAL_SHADOW_SCOPE_PENDING',
            'capability_code','CONTROL_EQUIVALENCE_JUDGE',
            'required_scope','M9.4_CANONICAL_COHORTS_FULL_PIPELINE_5_13_VS_VNEXT'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M9.3';

  -- Legacy retirement consumes current transversal authority; exact batch
  -- execution input is resolved from the current M10.12 inventory.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{transversal_execution_v1,REUSE_LEGACY_RETIREMENT}',
    jsonb_build_object(
      'mode','EXPLICIT',
      'activation','ACTIVE',
      'capabilities',jsonb_build_array(jsonb_build_object(
        'handler','REPOSITORY_CAPABILITY_EXECUTOR',
        'capability_code','ASSET_RETIREMENT_GOVERNANCE',
        'execution_input',jsonb_build_object(
          'capability_input',jsonb_build_object(
            'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
            'resolution','CURRENT_M10_12_LEGACY_INVENTORY_AND_LIVE_DEPENDENCY_GRAPH',
            'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
            'unit_code','M10.12',
            'source_checkpoint','LEGACY_INVENTORY',
            'literal_payload','FORBIDDEN'
          )
        )
      )),
      'execution_order','PLAN_ORDER_ONE_BY_ONE',
      'admission_required',false,
      'dependency_resolution','MANIFEST_GRAPH'
    ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.12';

  -- Runtime preflight consumes current RUNTIME_DEPLOY_VERIFICATION authority.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{transversal_execution_v1,RUNTIME_PREFLIGHT}',
    jsonb_build_object(
      'mode','EXPLICIT',
      'activation','ACTIVE',
      'capabilities',jsonb_build_array(jsonb_build_object(
        'handler','REPOSITORY_CAPABILITY_EXECUTOR',
        'capability_code','RUNTIME_DEPLOY_VERIFICATION',
        'execution_input',jsonb_build_object(
          'capability_input',jsonb_build_object(
            'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
            'resolution','CURRENT_MAIN_EDGE_CONTRACT_AND_RELEASE_BINDING',
            'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
            'unit_code','M10.2',
            'source_checkpoint','SWITCH_ONLY_MIGRATION',
            'literal_payload','FORBIDDEN'
          )
        )
      )),
      'execution_order','PLAN_ORDER_ONE_BY_ONE',
      'admission_required',false,
      'dependency_resolution','MANIFEST_GRAPH'
    ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M10.2';

  -- Final-evidence checkpoints consume the existing current capability.
  for r in
    select * from (values
      ('M7.14','M7_EVIDENCE_BUNDLE'),
      ('M8.12','M8_EVIDENCE_BUNDLE'),
      ('M9.0','BUNDLE_MANIFEST_SHA'),
      ('M9.13','M9_EVIDENCE_BUNDLE')
    ) x(unit_code,checkpoint_code)
  loop
    update programacion.engineering_plan_units pu
    set unit_metadata=jsonb_set(
      pu.unit_metadata,
      array['transversal_execution_v1',r.checkpoint_code],
      jsonb_build_object(
        'mode','EXPLICIT',
        'activation','ACTIVE',
        'capabilities',jsonb_build_array(jsonb_build_object(
          'handler','REPOSITORY_CAPABILITY_EXECUTOR',
          'capability_code','FINAL_EVIDENCE',
          'execution_input',jsonb_build_object(
            'capability_input',jsonb_build_object(
              'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
              'resolution','CURRENT_UNIT_DEPENDENCY_EVIDENCE_AND_CURRENTNESS',
              'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
              'unit_code',r.unit_code,
              'source_checkpoint',r.checkpoint_code,
              'literal_payload','FORBIDDEN'
            )
          )
        )),
        'execution_order','PLAN_ORDER_ONE_BY_ONE',
        'admission_required',false,
        'dependency_resolution','MANIFEST_GRAPH'
      ),
      true
    )
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code;
  end loop;
end;
$bind$;

do $selftest$
declare
  v_generic int;
  v_ready_authoring int;
  v_expected_authoring int := 35;
begin
  with x as (
    select pu.unit_code,c.checkpoint_code,
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      ) s
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and c.required and c.status not in ('DONE','NOT_APPLICABLE')
  )
  select
    count(*) filter(where s->>'status'='BLOCK_MATERIALIZATION_CONTRACT_REQUIRED'),
    count(*) filter(where s->>'precision'='BOUNDED_IMPLEMENTATION_AUTHORING_V1' and s->>'status'='READY')
  into v_generic,v_ready_authoring
  from x;

  if v_generic<>0 then
    raise exception 'ENGINEERING_MATERIALIZATION_GENERIC_BLOCKS_REMAIN:%',v_generic;
  end if;

  if v_ready_authoring<>v_expected_authoring then
    raise exception 'ENGINEERING_BOUNDED_AUTHORING_READY_COUNT expected=% actual=%',
      v_expected_authoring,v_ready_authoring;
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-BOUNDED-MATERIALIZATION-AUTHORING-001',
  'ENGINEERING_ORCHESTRATION',
  'Construction work must be claimable before the future output file exists',
  'Materialization family sanitation required an implementation_ref/mutation artifact to exist before scheduler admission, creating a circular dependency: the worker could not claim the checkpoint that was supposed to create that artifact.',
  'Future implementation output existence was confused with bounded implementation authority.',
  'FUTURE_OUTPUT_REQUIRED_BEFORE_CONSTRUCTION_WORKER_CAN_RUN',
  'Compile real construction checkpoints to BOUNDED_IMPLEMENTATION_AUTHORING with explicit allowed Git roots/exact files, exact DB targets, governed branch/PR/merge, required readback and assertion receipt. The worker resolves the concrete migration filename before WRITE_GIT. Reclassify capability/test/upstream items out of materialization.',
  'PASS when open plan has 0 BLOCK_MATERIALIZATION_CONTRACT_REQUIRED; 35 real construction checkpoints compile READY with bounded authoring; remaining former materializations are exact capability/test/upstream gates rather than generic contract debt.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_bounded_materialization_spec_v1; supabase://programacion.engineering_plan_units',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Plan-wide materialization contract reduction',
  'supabase://programacion.fn_engineering_bounded_materialization_spec_v1'
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
