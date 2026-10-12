-- ENGINEERING specific technical contract reduction v1
-- Converts remaining technical-specific blockers to bounded executable work.
-- True owner/upstream gates are intentionally untouched.

create or replace function programacion.fn_engineering_bounded_repository_adapter_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb,
  p_adapter_role text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_target jsonb := coalesce(v_spec->'target','{}'::jsonb);
  v_role text := upper(coalesce(p_adapter_role,''));
  v_path text;
  v_mutation jsonb;
  v_queries jsonb := coalesce(v_spec->'verification_queries','[]'::jsonb);
begin
  if v_role not in (
    'CONSUMER_ADAPTER','RECEIPT_ADAPTER','ADJUDICATION_ADAPTER','GIT_GUARD'
  ) then
    raise exception 'ENGINEERING_REPOSITORY_ADAPTER_ROLE_UNSUPPORTED:%',p_adapter_role;
  end if;

  v_path :=
    'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_adapters/'||
    lower(regexp_replace(p_unit_code,'[^A-Za-z0-9]+','_','g'))||'/'||
    lower(regexp_replace(p_checkpoint_code,'[^A-Za-z0-9]+','_','g'))||'.py';

  v_mutation:=jsonb_build_array(jsonb_build_object(
    'path',v_path,
    'role','MUTATION_TARGET',
    'target_kind','EXACT_NEW_OR_UPDATE_FILE',
    'purpose',v_role
  ));

  if v_role='GIT_GUARD' then
    v_mutation:=v_mutation||jsonb_build_array(jsonb_build_object(
      'path','cristhianlujan/claude-persona-lf-patch:scripts/lf_contract_check.py',
      'role','MUTATION_TARGET',
      'target_kind','EXACT_FILE',
      'purpose','INTEGRATE_GOVERNED_FREEZE_GUARD'
    ));
  end if;

  v_target:=v_target||jsonb_build_object(
    'evidence_artifacts',coalesce(v_target->'evidence_artifacts',v_target->'declared_artifacts','[]'::jsonb),
    'mutation_artifacts',v_mutation,
    'declared_artifacts',v_mutation
  );

  return (
    v_spec||jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','BOUNDED_REPOSITORY_ADAPTER_AUTHORING_V1',
      'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
      'recipe_mode','BOUNDED_REPOSITORY_ADAPTER',
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'contract_family','BOUNDED_REPOSITORY_ADAPTER',
      'target',v_target,
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'adapter_written',true,
          'git_merged',true,
          'readback_passed',true
        )
      ),
      'adapter_contract',jsonb_build_object(
        'role',v_role,
        'path',v_path,
        'scope','CURRENT_CHECKPOINT_ONLY',
        'declared_db_targets',coalesce(v_target->'declared_objects','[]'::jsonb),
        'declared_queries',v_queries,
        'governed_git_required',true,
        'synthetic_pass','FORBIDDEN',
        'post_merge_readback_required',true,
        'runtime_activation','NOT_IMPLIED'
      ),
      'expected','Author the exact bounded adapter/guard, merge through governed Git, execute its declared checkpoint behavior, and prove the canonical readback before DONE.'
    )
  )-'required_contract';
end;
$function$;

comment on function programacion.fn_engineering_bounded_repository_adapter_spec_v1(text,text,text,jsonb,text)
is 'Bounded repository-adapter authoring for technical gaps whose reusable authority exists but consumer/receipt/adjudication/CI adapter is missing.';

do $repair$
declare
  r record;
  v_spec jsonb;
  v_new jsonb;
begin
  -- A) Technical DB/config contracts -> existing bounded migration authoring.
  for r in
    select * from (values
      ('M1.A8','IG_SPEC_OBLIGATIONS','MIGRATION'),
      ('M4.3','RELABEL_SOURCE_INTEGRITY','MIGRATION'),
      ('M8.10','CORPUS_FIXED','MIGRATION'),
      ('N-18','PRIVACY_SIGNAL_AND_PURPOSE','MIGRATION'),
      ('N-18','MINIMAL_DATA_CONTRACT','MIGRATION'),
      ('M9.9','ROLLBACK_CONDITIONS','MIGRATION'),
      ('M9.7','TYPED_SCHEMA','MIGRATION'),
      ('M9.7','RECEIPT_FIELDS','MIGRATION'),
      ('M9.8','CONTROLS_AS_RECEIPTS','MIGRATION'),
      ('M9.5','LEVEL_DECLARATION','MIGRATION'),
      ('M9.2','BIND_VIA_VERSION_REGISTRY','MIGRATION'),
      ('M9.9','COHORT_BINDING','MIGRATION'),
      ('M9.3','FULL_PIPELINE_CANDIDATE','MIXED_THREE_EDGE_MIGRATION')
    ) x(unit_code,checkpoint_code,authoring_mode)
  loop
    select unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code=r.unit_code
      and disposition='ASSIGNED';

    v_new:=programacion.fn_engineering_bounded_materialization_spec_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',
      r.unit_code,r.checkpoint_code,v_spec,r.authoring_mode
    );

    -- Attach exact reusable authority where the checkpoint is a consumer.
    if r.unit_code='N-18' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capability_code','PRIVACY_MINIMALITY_GUARD',
          'currentness_source','public.lf_capability_current',
          'evaluate','public.lf_privacy_minimality_guard_evaluate_v1',
          'validator','public.lf_privacy_minimality_guard_result_valid_v1',
          'legal_authority_inference','FORBIDDEN'
        )
      );
    elsif r.unit_code='M9.7' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capabilities',jsonb_build_array('EVIDENCE_LEDGER','TYPED_EVIDENCE_REGISTRY'),
          'duplicate_store','FORBIDDEN'
        )
      );
    elsif r.unit_code='M9.8' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capabilities',jsonb_build_array('FINAL_EVIDENCE','CLOSURE_GATE','EVIDENCE_LEDGER'),
          'local_gate','FORBIDDEN'
        )
      );
    elsif r.unit_code='M9.2' or r.unit_code='M9.9' then
      v_new:=v_new||jsonb_build_object(
        'cutover_pattern_contract',jsonb_build_object(
          'authority_unit','LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1:SADM-PP-L5-022',
          'mode','ISOLATED_REVERSIBLE_EXACT_HEAD',
          'promotion_entrypoint','public.fn_lf_capability_promote_v1',
          'bulk_cutover',false,
          'rollback_required',true,
          'runtime_or_production_activation','NOT_AUTHORIZED_BY_THIS_CHECKPOINT',
          'direct_pointer_mutation','FORBIDDEN'
        )
      );
    elsif r.unit_code='M9.3' then
      v_new:=v_new||jsonb_build_object(
        'comparison_authority',jsonb_build_object(
          'capability_code','CONTROL_EQUIVALENCE_JUDGE',
          'scope_source','M9.4_CANONICAL_COHORTS',
          'current','INPUT_READINESS_5_13',
          'candidate','VNEXT_FULL_PIPELINE',
          'authoritative_writes','FORBIDDEN'
        )
      );
    end if;

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         pu.unit_metadata,'{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           ||jsonb_build_object(r.checkpoint_code,v_new),true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';
  end loop;

  -- B) Missing repository adapters.
  for r in
    select * from (values
      ('M1.A8','RECEIPT_PER_RUN','RECEIPT_ADAPTER'),
      ('M4.7','FAIL_BLOCKED_PERSISTED','RECEIPT_ADAPTER'),
      ('M8.10','BENCH_VIA_TPERF','CONSUMER_ADAPTER'),
      ('M8.10','PHASE_BUDGET','CONSUMER_ADAPTER'),
      ('M4.10','ADJUDICATE_DIVERGENCES','ADJUDICATION_ADAPTER'),
      ('M9.6','ADJUDICATE_EACH','ADJUDICATION_ADAPTER'),
      ('M10.4','FREEZE_RULE','GIT_GUARD')
    ) x(unit_code,checkpoint_code,adapter_role)
  loop
    select unit_metadata#>array['action_specs_v1',r.checkpoint_code]
      into v_spec
    from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code=r.unit_code
      and disposition='ASSIGNED';

    v_new:=programacion.fn_engineering_bounded_repository_adapter_spec_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',
      r.unit_code,r.checkpoint_code,v_spec,r.adapter_role
    );

    if r.unit_code='M1.A8' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capabilities',jsonb_build_array('ASSURANCE_EVALUATOR','EVIDENCE_LEDGER','TYPED_EVIDENCE_REGISTRY'),
          'receipt_scope','ONE_READINESS_RUN',
          'all_clauses_marked_required',true
        )
      );
    elsif r.unit_code='M4.7' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capabilities',jsonb_build_array('EVIDENCE_LEDGER','TYPED_EVIDENCE_REGISTRY'),
          'states',jsonb_build_array('PASS','FAIL','BLOCKED'),
          'promotion_side_effect','FORBIDDEN'
        )
      );
    elsif r.unit_code='M8.10' and r.checkpoint_code='BENCH_VIA_TPERF' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capability_code','PERFORMANCE_EXACT_SOURCE_BENCHMARK',
          'required_inputs',jsonb_build_array('exact_source_sha256','source_ref','phases','sample_count','warmup_count'),
          'input_sources',jsonb_build_object(
            'exact_source_sha256','CURRENT_IG_SOURCE_SHA',
            'source_ref','CURRENT_IG_SOURCE_REF',
            'phases','M8.1_INSTRUMENTED_PHASES',
            'sample_count','CORPUS_FIXED',
            'warmup_count','CORPUS_FIXED'
          ),
          'own_benchmark_engine','FORBIDDEN'
        )
      );
    elsif r.unit_code='M8.10' and r.checkpoint_code='PHASE_BUDGET' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'capability_code','TIMEOUT_PHASE_BUDGET_POLICY',
          'required_inputs',jsonb_build_array('phase','requested_timeout_ms','policy','exact_source_sha256'),
          'input_sources',jsonb_build_object(
            'phase','M8.1_PHASE',
            'requested_timeout_ms','EDGE_LIMIT_DERIVED_BUDGET',
            'policy','M8.10_VERSIONED_PHASE_POLICY',
            'exact_source_sha256','CURRENT_IG_SOURCE_SHA'
          ),
          'automatic_timeout_mutation','FORBIDDEN'
        )
      );
    elsif r.adapter_role='ADJUDICATION_ADAPTER' then
      v_new:=v_new||jsonb_build_object(
        'consumer_authority',jsonb_build_object(
          'authority_adr','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
          'capabilities',jsonb_build_array('PLAN_AUTHORITY_DRIFT_GUARD','WAIVER_AUTHORITY','EVIDENCE_LEDGER'),
          'decision_persistence','programacion.human_decisions',
          'unresolved_after_execution',0,
          'local_override','FORBIDDEN'
        )
      );
    elsif r.adapter_role='GIT_GUARD' then
      v_new:=v_new||jsonb_build_object(
        'guard_contract',jsonb_build_object(
          'scope','M10.4_FROZEN_LEGACY_OBJECT_SET',
          'integration_target','scripts/lf_contract_check.py',
          'frozen_hash_source','CURRENT_M10.4_INVENTORY',
          'post_freeze_change','FAIL_CLOSED',
          'classifier_broadening','FORBIDDEN'
        )
      );
    end if;

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         pu.unit_metadata,'{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           ||jsonb_build_object(r.checkpoint_code,v_new),true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';
  end loop;

  -- C) M9.10 is the executable isolated/reversible cohort cutover drill.
  select unit_metadata#>'{action_specs_v1,COHORT_BY_COHORT}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.10';

  v_new:=programacion.fn_engineering_bounded_checkpoint_test_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.10','COHORT_BY_COHORT',v_spec
  )||jsonb_build_object(
    'cutover_pattern_contract',jsonb_build_object(
      'authority_unit','LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1:SADM-PP-L5-022',
      'mode','ISOLATED_REVERSIBLE_EXACT_HEAD',
      'promotion_entrypoint','public.fn_lf_capability_promote_v1',
      'cohort_source','M9.4',
      'rollback_drill_required',true,
      'zero_residue_required',true,
      'production_activation','FORBIDDEN'
    )
  );

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
      ||jsonb_build_object('COHORT_BY_COHORT',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.10';

  -- D) M9.12 can consume already-current FINAL_EVIDENCE then CLOSURE_GATE.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,
    '{transversal_execution_v1}',
    coalesce(pu.unit_metadata->'transversal_execution_v1','{}'::jsonb)
      ||jsonb_build_object(
        'CLOSURE_GATE_CONSUME',
        jsonb_build_object(
          'mode','EXPLICIT',
          'activation','ACTIVE',
          'capabilities',jsonb_build_array(
            jsonb_build_object(
              'handler','REPOSITORY_CAPABILITY_EXECUTOR',
              'capability_code','FINAL_EVIDENCE',
              'execution_input',jsonb_build_object(
                'capability_input',jsonb_build_object(
                  'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
                  'resolution','M9_8_PASS_M9_10_DRILL_M9_11_SOAK_PLUS_M9_0_BUNDLE',
                  'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
                  'unit_code','M9.12',
                  'source_checkpoint','CLOSURE_GATE_CONSUME',
                  'literal_payload','FORBIDDEN'
                )
              )
            ),
            jsonb_build_object(
              'handler','REPOSITORY_CAPABILITY_EXECUTOR',
              'capability_code','CLOSURE_GATE',
              'execution_input',jsonb_build_object(
                'capability_input',jsonb_build_object(
                  'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1',
                  'source','PREVIOUS_TRANSVERSAL_STEP_OUTPUT',
                  'resolution','FINAL_EVIDENCE_MANIFEST_PLUS_M9_0_BUNDLE',
                  'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
                  'unit_code','M9.12',
                  'required_verdict','PASS',
                  'output_receipt_kind','CUTOVER_READY',
                  'production_activation',false,
                  'literal_payload','FORBIDDEN'
                )
              )
            )
          ),
          'execution_order','PLAN_ORDER_ONE_BY_ONE',
          'admission_required',false,
          'dependency_resolution','MANIFEST_GRAPH'
        )
      ),
    true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code='M9.12';
end;
$repair$;

do $selftest$
declare
  v_bad int;
  v_m912 jsonb;
begin
  with mapped(unit_code,checkpoint_code) as (
    values
      ('M1.A8','IG_SPEC_OBLIGATIONS'),
      ('M1.A8','RECEIPT_PER_RUN'),
      ('M4.3','RELABEL_SOURCE_INTEGRITY'),
      ('M4.7','FAIL_BLOCKED_PERSISTED'),
      ('M4.10','ADJUDICATE_DIVERGENCES'),
      ('M8.10','CORPUS_FIXED'),
      ('M8.10','BENCH_VIA_TPERF'),
      ('M8.10','PHASE_BUDGET'),
      ('M9.2','BIND_VIA_VERSION_REGISTRY'),
      ('M9.3','FULL_PIPELINE_CANDIDATE'),
      ('M9.5','LEVEL_DECLARATION'),
      ('M9.6','ADJUDICATE_EACH'),
      ('M9.7','TYPED_SCHEMA'),
      ('M9.7','RECEIPT_FIELDS'),
      ('M9.8','CONTROLS_AS_RECEIPTS'),
      ('M9.9','ROLLBACK_CONDITIONS'),
      ('M9.9','COHORT_BINDING'),
      ('M9.10','COHORT_BY_COHORT'),
      ('M9.12','CLOSURE_GATE_CONSUME'),
      ('M10.4','FREEZE_RULE'),
      ('N-18','PRIVACY_SIGNAL_AND_PURPOSE'),
      ('N-18','MINIMAL_DATA_CONTRACT')
  ), x as (
    select m.*,
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',m.unit_code,m.checkpoint_code
      ) spec
    from mapped m
  )
  select count(*) into v_bad
  from x
  where spec->>'status'<>'READY';

  if v_bad<>0 then
    raise exception 'ENGINEERING_SPECIFIC_TECHNICAL_REPAIR_NOT_READY:%',v_bad;
  end if;

  v_m912:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.12','CLOSURE_GATE_CONSUME'
  );
  if v_m912->>'transversal_capability_code'<>'FINAL_EVIDENCE'
     or v_m912->>'status'<>'READY' then
    raise exception 'ENGINEERING_M9_12_FIRST_TRANSVERSAL_NOT_READY:%',v_m912;
  end if;

  if programacion.fn_engineering_execution_packet_from_spec_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.10','COHORT_BY_COHORT',
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.10','COHORT_BY_COHORT'
      ),
      '{}'::jsonb
    )->>'status'<>'READY' then
    raise exception 'ENGINEERING_M9_10_CUTOVER_DRILL_PACKET_NOT_READY';
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-SPECIFIC-TECHNICAL-CONTRACT-REDUCTION-001',
  'ENGINEERING_ORCHESTRATION',
  'Specific technical blockers must become bounded executable work without weakening owner/upstream gates',
  'After generic family repair, remaining technical blockers represented missing consumers, receipts, cutover-pattern bindings, versioned data contracts and CI adapters. These are buildable engineering work, not reasons to exclude the unit from scheduling.',
  'Specific implementation debt remained encoded as BLOCK_* action-spec status instead of bounded authoring or current transversal execution.',
  'TECHNICAL_IMPLEMENTATION_DEBT_MISCLASSIFIED_AS_UNCLAIMABLE_PREFLIGHT',
  'Map exact technical checkpoints to bounded migration, repository adapter, checkpoint test, or current transversal execution. Reuse SADM-PP-L5-022 for cutover semantics; never register CAPABILITY_CUTOVER as a fake current capability. Preserve owner decisions and upstream receipts as real blockers.',
  'PASS when the 22 exact technical checkpoints mapped by this migration compile READY, M9.12 starts with CURRENT FINAL_EVIDENCE, M9.10 has executable rollback drill packet, and no owner/upstream gate is modified.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_bounded_repository_adapter_spec_v1; plan://LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1/SADM-PP-L5-022',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Specific post-family contract reduction',
  'supabase://programacion.fn_engineering_bounded_repository_adapter_spec_v1'
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
