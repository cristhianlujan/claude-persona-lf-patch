-- Contract corrections for T-PRIVACY and M4.5.
-- Live-validated on 2026-10-06 before source reconciliation.

update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{action_specs_v1,NON_IG_CONSUMER}',
  jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'status','READY',
    'checkpoint_code','NON_IG_CONSUMER',
    'checkpoint_title','Segundo consumer no-IG aplica minimalidad',
    'action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT',
    'precision','EXPLICIT_NON_IG_CONSUMER_GUARD_EVALUATION',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'target',jsonb_build_object(
      'checkpoint','NON_IG_CONSUMER',
      'declared_assets',jsonb_build_array('PRIVACY_MINIMALITY_GUARD'),
      'declared_events','[]'::jsonb,
      'declared_artifacts','[]'::jsonb,
      'declared_objects',jsonb_build_array(
        'public.lf_privacy_minimality_guard_evaluate_v1',
        'public.lf_privacy_minimality_guard_result_valid_v1',
        'public.lf_capability_registry',
        'public.lf_capability_current',
        'public.lf_capability_version_registry'
      )
    ),
    'expected','A non-IG consumer probe is evaluated by PRIVACY_MINIMALITY_GUARD and returns a valid PASS with authorized_to_proceed=true when requested_items are minimal and caller-proven need/authority refs are supplied.',
    'action_steps',jsonb_build_array(
      'READ_CURRENT_PRIVACY_MINIMALITY_GUARD',
      'EVALUATE_NON_IG_CONSUMER_PROBE',
      'ASSERT_RESULT_VALID_AND_PASS',
      'PERSIST_DONE_ON_PASS',
      'USE_RETURNED_BOOTSTRAP'
    ),
    'verification_queries',jsonb_build_array(
      $q$with r as (
        select public.lf_privacy_minimality_guard_evaluate_v1(
          jsonb_build_object(
            'consumer_ref','NON_IG_CONSUMER_PROBE:T-PRIVACY',
            'operation','USE',
            'need',jsonb_build_object(
              'state','DECLARED',
              'ref','engineering://T-PRIVACY/NON_IG_CONSUMER/need'
            ),
            'authority',jsonb_build_object(
              'state','VALID',
              'ref','engineering://T-PRIVACY/NON_IG_CONSUMER/authority',
              'context_ref','engineering://T-PRIVACY/NON_IG_CONSUMER'
            ),
            'requested_items',jsonb_build_array('opaque_customer_reference'),
            'necessary_items',jsonb_build_array('opaque_customer_reference')
          )
        ) result
      )
      select result,
             public.lf_privacy_minimality_guard_result_valid_v1(result) result_valid,
             result->>'state' state,
             (result->>'authorized_to_proceed')::boolean authorized_to_proceed
      from r$q$,
      $q$select r.capability_code,r.status,c.version,v.release_state,v.manifest_sha256
          from public.lf_capability_registry r
          join public.lf_capability_current c using(capability_code)
          join public.lf_capability_version_registry v
            on v.capability_code=c.capability_code
           and v.version=c.version
           and v.manifest_sha256=c.manifest_sha256
          where r.capability_code='PRIVACY_MINIMALITY_GUARD'$q$
    ),
    'persist',jsonb_build_object(
      'on_pass','DONE',
      'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'next_state','RETURNED_BOOTSTRAP_ONLY'
    ),
    'forbidden',jsonb_build_array(
      'MUTATE_CAPABILITY_REGISTRY',
      'CREATE_SYNTHETIC_BINDING',
      'INFER_LEGAL_AUTHORITY',
      'RECLASSIFY_AS_WRITE_DB'
    ),
    'contract_correction','NON_IG_CONSUMER_IS_A_GUARD_EVALUATION_NOT_A_CAPABILITY_MATERIALIZATION'
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='T-PRIVACY';

update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{action_specs_v1,REGISTRY_SOURCE_RESOLUTION}',
  jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'status','READY',
    'checkpoint_code','REGISTRY_SOURCE_RESOLUTION',
    'checkpoint_title','Descubrimiento de fuentes por familia consumiendo T-SOURCE (SOURCE_RESOLUTION_POLICY), no refs del Curator',
    'action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT',
    'precision','EXPLICIT_CONSUMER_PROCEDURE_READBACK',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'target',jsonb_build_object(
      'checkpoint','REGISTRY_SOURCE_RESOLUTION',
      'declared_assets',jsonb_build_array('SOURCE_RESOLUTION_POLICY'),
      'declared_events','[]'::jsonb,
      'declared_artifacts','[]'::jsonb,
      'declared_objects',jsonb_build_array(
        'programacion.fn_input_resolve_source_ref',
        'public.v_lf_fuente_operativa',
        'programacion.input_readiness_runs',
        'programacion.input_family_assessments',
        'public.lf_capability_registry',
        'public.lf_capability_current',
        'public.lf_capability_version_registry'
      )
    ),
    'expected','M4.5 evaluates its own consumer procedure: SOURCE_RESOLUTION_POLICY is ACTIVE/CURRENT/RELEASED and the completed validator assessment universe contains all 47 families. Dependency-owned M2.1/T-SOURCE test cases are reused only as prior evidence and are not re-executed or persisted as M4.5 cases.',
    'action_steps',jsonb_build_array(
      'READ_CURRENT_SOURCE_RESOLUTION_POLICY',
      'ASSERT_47_FAMILIES_PRESENT',
      'ASSERT_DEPENDENCY_TEST_CASESET_NOT_REEXECUTED',
      'PERSIST_DONE_ON_PASS',
      'USE_RETURNED_BOOTSTRAP'
    ),
    'verification_queries',jsonb_build_array(
      $q$select count(distinct a.family_code) families_completed
          from programacion.input_family_assessments a
          join programacion.input_readiness_runs r on r.id=a.run_id
          where r.status='COMPLETED'$q$,
      $q$select r.capability_code,r.status,c.version,v.release_state,v.manifest_sha256
          from public.lf_capability_registry r
          join public.lf_capability_current c using(capability_code)
          join public.lf_capability_version_registry v
            on v.capability_code=c.capability_code and v.version=c.version
          where r.capability_code='SOURCE_RESOLUTION_POLICY'
            and r.status='ACTIVE'
            and v.release_state='RELEASED'$q$
    ),
    'persist',jsonb_build_object(
      'on_pass','DONE',
      'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'next_state','RETURNED_BOOTSTRAP_ONLY'
    ),
    'forbidden',jsonb_build_array(
      'REEXECUTE_DEPENDENCY_OWNED_TEST_CASESET',
      'PERSIST_M2_1_CASES_AS_M4_5_CASES',
      'USE_CURATOR_SOURCE_REFS_AS_VALIDATOR_AUTHORITY',
      'CROSS_CHECKPOINT_NEGATIVE_INJECTION'
    ),
    'dependency_evidence_policy',jsonb_build_object(
      'T_SOURCE','CONSUME_DONE_CURRENT_AUTHORITY',
      'M2_1_CASESET','HISTORICAL_EVIDENCE_ONLY_NO_REEXECUTION',
      'ownership_transfer','FORBIDDEN'
    ),
    'contract_correction','DEPENDENCY_DONE_ENABLES_CONSUMPTION_BUT_DOES_NOT_TRANSFER_TEST_OWNERSHIP'
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.5';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-DEPENDENCY-TEST-OWNERSHIP-TRANSFER-001',
  'ENGINEERING_ORCHESTRATION',
  'A DONE dependency enables consumption but does not transfer its test case ownership',
  'M4.5 was configured to re-execute the 32 M2.1 T-SOURCE regression cases even though all M4.5 development dependencies were already DONE. This mixed dependency evidence with consumer-procedure validation.',
  'The consumer action spec used EXPLICIT_REUSED_TEST_CASESET and embedded dependency-owned test codes as if they were owned by the consumer checkpoint.',
  'DEPENDENCY_DONE_BUT_TEST_CASESET_REEXECUTED_BY_CONSUMER',
  'When an upstream dependency is DONE/current, downstream units consume its released capability and evidence. They must evaluate their own procedure and must not re-execute or persist dependency-owned test cases unless the downstream checkpoint explicitly owns those cases.',
  'PASS 2026-10-06: M4.5 REGISTRY_SOURCE_RESOLUTION action spec is READBACK_ONCE/EXPLICIT_CONSUMER_PROCEDURE_READBACK, no test_case_codes, execution_capability=READ, readiness READY, 47 families observed, SOURCE_RESOLUTION_POLICY@1.4.0 ACTIVE/RELEASED.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.5#REGISTRY_SOURCE_RESOLUTION',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE',
  'PROCESS_DEPENDENT',
  'M4.5 consumer contract correction',
  'supabase://programacion.fn_engineering_unit_bootstrap_v3/IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.5'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001',
  'ENGINEERING_ORCHESTRATION',
  'A pure consumer capability probe must not be compiled as WRITE_DB materialization',
  'T-PRIVACY NON_IG_CONSUMER only needs to prove that a non-IG consumer can be evaluated by PRIVACY_MINIMALITY_GUARD. It was compiled as MATERIALIZE_DECLARED_DELIVERABLE/WRITE_DB despite having no mutation to perform.',
  'The generated checkpoint contract inferred materialization from the checkpoint semantics instead of declaring the exact consumer evaluation operation.',
  'READ_ONLY_CONSUMER_PROBE_CLASSIFIED_AS_WRITE_DB',
  'For consumer-genericity checks, prefer an explicit READBACK_ONCE/VERIFY_QUERY_ONCE calling the released capability evaluator with opaque test-only references. Do not create synthetic bindings or mutate capability registries unless the checkpoint explicitly requires a persisted binding.',
  'PASS 2026-10-06: T-PRIVACY NON_IG_CONSUMER compiles to READBACK_ONCE, execution_capability=READ, readiness READY, bootstrap CONTINUE_CURRENT_CHECKPOINT; live probe returned MINIMALITY_SATISFIED/PASS, result_valid=true, authorized_to_proceed=true.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/T-PRIVACY#NON_IG_CONSUMER',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE',
  'PROCESS_DEPENDENT',
  'T-PRIVACY consumer probe contract correction',
  'supabase://programacion.fn_engineering_unit_bootstrap_v3/IG_CURATOR_VALIDATOR_REFACTOR_V2/T-PRIVACY'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

update public.lf_error_knowledge
set evidencia = case
      when position('[2026-10-06_M4.5_CORRECTION]' in coalesce(evidencia,'')) > 0 then evidencia
      else coalesce(evidencia,'') || E'\n[2026-10-06_M4.5_CORRECTION] M4.5 no longer consumes RUN_TEST; its checkpoint now validates its own consumer procedure via READBACK. Generic RUN_TEST material executor gap remains active for checkpoints that legitimately require RUN_TEST.'
    end,
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-RUN-TEST-EXECUTOR-GAP-001';
