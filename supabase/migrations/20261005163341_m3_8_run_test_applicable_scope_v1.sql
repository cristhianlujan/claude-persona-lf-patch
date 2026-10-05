DO $$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v3';
  IF v_md5 IS DISTINCT FROM '33ddde6034108a7ec77f5f64144f8733' THEN
    RAISE EXCEPTION 'ACTION_SPEC_V3_FINGERPRINT_DRIFT expected=% actual=%','33ddde6034108a7ec77f5f64144f8733',v_md5;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'programacion','public','pg_catalog'
AS $function$
with s as materialized (
  select programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,p_checkpoint_code) spec
), x as materialized (
  select spec,lower(coalesce(spec->>'checkpoint_title','')) title_l,
         coalesce(spec->>'checkpoint_code','') checkpoint_code,
         coalesce((spec->>'requires_material_execution')::boolean,false) is_material,
         coalesce(jsonb_array_length(spec#>'{target,declared_artifacts}'),0) artifact_count,
         coalesce(jsonb_array_length(spec->'verification_queries'),0) verification_count,
         coalesce(spec#>'{target,declared_objects}','[]'::jsonb) objects
  from s
)
select case
  when spec is null then null
  when checkpoint_code='HANDOFF_EVENT' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_CLOSURE_EVENT',
      'action_kind','MUTATION_EXECUTION','recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
      'requires_material_execution',true,'mutation_policy','ONLY_DECLARED_TARGETS',
      'target',jsonb_build_object('checkpoint',checkpoint_code,'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_objects',jsonb_build_array('public.lf_eventos'),'declared_artifacts','[]'::jsonb),
      'verification_queries',jsonb_build_array(format('select programacion.fn_engineering_closure_event_v1(%L,%L,%L)',p_plan_code,p_unit_code,'HANDOFF')),
      'action_steps',jsonb_build_array('EMIT_CANONICAL_HANDOFF_EVENT','VERIFY_EVENT_READBACK','PERSIST_DONE','USE_RETURNED_BOOTSTRAP'))
  when checkpoint_code='INDEPENDENT_READBACK_TERMINAL' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_CLOSURE_EVENT',
      'action_kind','MUTATION_EXECUTION','recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
      'requires_material_execution',true,'mutation_policy','ONLY_DECLARED_TARGETS',
      'target',jsonb_build_object('checkpoint',checkpoint_code,'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_objects',jsonb_build_array('public.lf_eventos'),'declared_artifacts','[]'::jsonb),
      'verification_queries',jsonb_build_array(format('select programacion.fn_engineering_closure_event_v1(%L,%L,%L)',p_plan_code,p_unit_code,'INDEPENDENT_READBACK')),
      'action_steps',jsonb_build_array('EMIT_CANONICAL_INDEPENDENT_READBACK','VERIFY_EVENT_READBACK','PERSIST_DONE','USE_RETURNED_BOOTSTRAP'))
  when objects @> jsonb_build_array('public.lf_test_suite_runs','public.lf_test_assertion_results')
       and (checkpoint_code='RUN_PERSIST' or (title_l like '%lf_test_suite_runs%' and title_l like '%assertion%')) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','COMPILED_TEST_PERSISTENCE_GRAPH',
      'action_kind','DECLARED_TEST_PERSISTENCE_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_TEST_PERSISTENCE',
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'target',coalesce(spec->'target','{}'::jsonb) || jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_cases',
          'public.lf_test_suite_runs',
          'public.lf_test_runs',
          'public.lf_test_assertion_results'
        )
      ),
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','CAPABILITY_OWNED',
        'design_boundary','RUN_TEST_OWNS_CASE_CATALOG_AND_EXECUTION_GRAPH',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1',
        'execution_semantics','REAL_TEST_EXECUTION_REQUIRED',
        'scenario_policy','APPLICABLE_BY_RESOLVER_NOT_CARTESIAN'
      ),
      'action_steps',jsonb_build_array(
        'REGISTER_OR_REUSE_APPLICABLE_TEST_CASES',
        'EXECUTE_CURRENT_CHECKPOINT_TEST_SCOPE',
        'PERSIST_ATOMIC_SUITE_RUN_TEST_RUN_ASSERTION_GRAPH',
        'DERIVE_STATUS_FROM_ACTUAL_TEST_AND_ASSERTION_RESULTS',
        'PERSIST_DONE_ONLY_ON_REAL_PASS',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'scope_guard',jsonb_build_object(
        'new_shared_or_transversal_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'dependency_graph_mutation','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'cross_checkpoint_design','FORBIDDEN'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'CREATE_UNDECLARED_SHARED_ABSTRACTION',
        'MUTATE_UNDECLARED_TARGET',
        'SYNTHETIC_PASS_WITHOUT_TEST_EXECUTION',
        'ASSERTION_WITHOUT_TEST_RUN',
        'TEST_RUN_WITHOUT_SUITE_RUN',
        'ATTACH_ASSERTIONS_TO_UNRELATED_RUN',
        'FORCE_NON_APPLICABLE_SCENARIO_ON_RESOLVER'
      )
    )
  when (
    (checkpoint_code='DEPENDENCY_WIRING' and title_l like '%hallazgo%')
    or (coalesce(spec->>'recipe_mode','')='EXECUTE_DECLARED_DELIVERABLE' and title_l ~ '^(verificar|comprobar|readback|observar)' and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|registrar dependencia)')
    or (coalesce(spec->>'action_kind','')='MATERIALIZE_DECLARED_DELIVERABLE' and artifact_count=0 and verification_count>0 and title_l ~ '^(verificar|confirmar|recalcular|conteo|cobertura observada|precondici[oó]n|prerequisit|identificar|0 callers|suite .*verde|evidencia .*exist|aud-[0-9]+ cerrado|consumir .*en vez|elegibilidad le[ií]da|presupuesto .*consumido|hechos espec[ií]ficos jit)' and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|emitir|registrar|migraci)')
  ) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_READ_ONLY_GUARD',
      'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT','requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'action_steps',jsonb_build_array('READ_DECLARED_AUTHORITY_ONCE','ASSERT_EXACT_STATE','PERSIST_CHECKPOINT_ONLY','USE_RETURNED_BOOTSTRAP'),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb)||jsonb_build_array('MUTATE_DEPENDENCY_GRAPH','CREATE_UNDECLARED_SHARED_ABSTRACTION')) - 'material_contract'
  else
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
      'scope_guard',jsonb_build_object('new_shared_or_transversal_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED','dependency_graph_mutation','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED','cross_checkpoint_design','FORBIDDEN'),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb)||jsonb_build_array('CREATE_UNDECLARED_SHARED_ABSTRACTION','MUTATE_UNDECLARED_TARGET'))
end from x;
$function$;

UPDATE programacion.engineering_plan_units
SET exit_criterion='RUN_TEST verde con cobertura aplicable por resolver: contexto válido y fail-closed missing en primitives; partial, broken_ref y candidate solo donde el contrato del resolver los expresa; contradiction pertenece a la capa semántica y no se fuerza artificialmente en primitives; cached vs no-cached delegado a M7.8.',
    unit_metadata=jsonb_set(
      coalesce(unit_metadata,'{}'::jsonb),
      '{run_test_scope_policy_v1}',
      jsonb_build_object(
        'policy','APPLICABLE_BY_RESOLVER_NOT_CARTESIAN',
        'base_cases',jsonb_build_array('VALID_CONTEXT','MISSING_FAIL_CLOSED'),
        'specialized_cases',jsonb_build_array('BROKEN_REF','CANDIDATE','PARTIAL'),
        'specialized_only_when_resolver_expresses_semantics',true,
        'contradiction_owner','SEMANTIC_LAYER',
        'cached_vs_non_cached_owner','M7.8',
        'legacy_variants','PARITY_ONLY'
      ),
      true
    )
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M3.8';

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
) VALUES
('INPUT_GOVERNANCE_REGRESSION','M3_8_BASE_VALID_CONTEXT',380800,NULL,ARRAY[]::text[],'M3.8 resolver base — valid governed context','POSITIVE','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('pantalla_id',54,'version_id',19,'run_id',525,'family_codes',jsonb_build_array('VALIDATIONS','SECURITY')),
 jsonb_build_object('outcome','PASS','requirement','CANONICAL_RESOLVERS_RETURN_GOVERNED_RESULT'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','scope_policy','APPLICABLE_BY_RESOLVER_NOT_CARTESIAN','coverage','BASE_VALID_CONTEXT'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_MISSING_FAIL_CLOSED',380801,NULL,ARRAY[]::text[],'M3.8 resolver base — missing input fails closed','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('scenario','MISSING','invalid_pantalla_id',-1),jsonb_build_object('outcome','FAIL_CLOSED_OR_EXPLICIT_MISSING'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','coverage','MISSING'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_BROKEN_REF_FAIL_CLOSED',380802,NULL,ARRAY[]::text[],'M3.8 source resolver — broken ref fails closed','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('scenario','BROKEN_REF','ref',jsonb_build_object('kind','RULE','codigo','__M3_8_BROKEN__'),'pantalla_id',54,'version_id',19),jsonb_build_object('error_family','SOURCE_REF_UNRESOLVED'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','resolver_surface','programacion.fn_input_resolve_source_ref','coverage','BROKEN_REF'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_CANDIDATE_PRESERVED',380803,NULL,ARRAY[]::text[],'M3.8 source resolver — candidate remains read-only candidate','DETERMINISTIC','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('scenario','CANDIDATE','ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-033'),'pantalla_id',54,'version_id',19),jsonb_build_object('observed_state','CANDIDATO','auto_promoted',false), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','resolver_surface','programacion.fn_input_resolve_source_ref','coverage','CANDIDATE'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_PARTIAL_PRESERVED',380804,NULL,ARRAY[]::text[],'M3.8 security resolver — partial state remains explicit','DETERMINISTIC','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('scenario','PARTIAL','pantalla_id',54),jsonb_build_object('contains_status','PARTIAL'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','resolver_surface','programacion.fn_input_security_threat_expected','coverage','PARTIAL'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_LEGACY_PARITY',380805,NULL,ARRAY[]::text[],'M3.8 legacy resolver variants — parity only','DETERMINISTIC','AUTOMATED','MEDIUM','[]'::jsonb,
 jsonb_build_object('pantalla_id',54,'version_id',19,'family_code','SECURITY'),jsonb_build_object('source_ref_v510','EQUAL_CURRENT','security_threat_v510','EQUAL_CURRENT','subject_depth_v510','EQUAL_CURRENT'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','coverage','LEGACY_PARITY','cached_vs_non_cached','DELEGATED_M7.8'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_8_CONTRADICTION_BOUNDARY',380806,NULL,ARRAY[]::text[],'M3.8 contradiction ownership — semantic layer, not primitive resolver','DETERMINISTIC','AUTOMATED','HIGH','[]'::jsonb,
 jsonb_build_object('scenario','CONTRADICTION','primitive_layer',true),jsonb_build_object('owner','SEMANTIC_LAYER','primitive_synthetic_contradiction','FORBIDDEN'), '{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.8','coverage','CONTRADICTION_BOUNDARY','reason','PRIMITIVE_RESOLVERS_DO_NOT_SHARE_A_NATIVE_CONTRADICTION_STATE'),'GPT-5.6-SOL-M3.8-RUNTEST-V1','GPT-5.6-SOL-M3.8-RUNTEST-V1')
ON CONFLICT (suite_code,test_code) DO UPDATE SET
  title=excluded.title,test_type=excluded.test_type,execution_mode=excluded.execution_mode,severity=excluded.severity,
  input_payload=excluded.input_payload,expected_output=excluded.expected_output,prohibited_output=excluded.prohibited_output,
  status=excluded.status,metadata=excluded.metadata,updated_at=now(),updated_by_execution_id=excluded.updated_by_execution_id;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES (
  'ENGINEERING-RUN-TEST-CASE-OWNERSHIP-001','ENGINEERING_GOVERNANCE',
  'RUN_TEST owns case catalog and execution graph; scenarios are applicability-based',
  'Treating every semantic scenario as a cartesian requirement for every resolver created unbounded case growth and forced unrelated primitives to emulate states they do not own.',
  'The orchestration layer mixed scenario taxonomy with primitive resolver semantics and excluded lf_test_suite_cases from the RUN_TEST mutation boundary even though lf_test_runs has a foreign key to that catalog.',
  'resolver x every scenario -> bespoke cases -> orchestration changes -> FK blockers',
  'RUN_TEST owns lf_test_suite_cases plus suite/test/assertion runs. Base valid and missing behavior applies broadly; specialized scenarios apply only where the resolver contract exposes them. Semantic contradiction stays in the semantic layer; cached parity stays with M7.8.',
  'PASS when M3.8 RUN_PERSIST targets include lf_test_suite_cases and the three execution tables, M3.8 has seven compact canonical cases, and bootstrap still routes through RUN_TEST without adding a fifth router capability.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT','RUN_TEST capability boundary and resolver scenario applicability',
  'supabase://programacion.fn_engineering_checkpoint_action_spec_v3|supabase://public.lf_test_suite_cases/INPUT_GOVERNANCE_REGRESSION/M3.8'
)
ON CONFLICT (codigo) DO UPDATE SET
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref;

UPDATE public.lf_error_knowledge
SET prevencion='RUN_TEST owns lf_test_suite_cases plus suite/test/assertion execution graph. Scenario selection is applicability-based, not cartesian. Primitive resolvers receive base valid/missing checks; specialized states are tested only where contract semantics exist. Synthetic PASS and forced non-applicable scenarios are forbidden.',
    validacion='PASS when test-persistence checkpoints route as RUN_TEST, target case catalog plus execution graph, and no new router branch is introduced for scenario variants.'
WHERE codigo='ENGINEERING-TEST-PERSISTENCE-GRAPH-001';

DO $$
DECLARE
  v_boot jsonb;
  v_cases integer;
  v_exit text;
BEGIN
  v_boot:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8');
  IF NOT (v_boot#>'{action_spec,target,declared_objects}' @> jsonb_build_array('public.lf_test_suite_cases','public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results')) THEN
    RAISE EXCEPTION 'RUN_TEST_TARGET_BOUNDARY_INCOMPLETE targets=%',v_boot#>'{action_spec,target,declared_objects}';
  END IF;
  IF v_boot#>>'{execution_packet,connector_plan,0,operation}' IS DISTINCT FROM 'RUN_TEST' THEN
    RAISE EXCEPTION 'RUN_TEST_ROUTER_REGRESSION op=%',v_boot#>>'{execution_packet,connector_plan,0,operation}';
  END IF;
  IF v_boot#>>'{execution_packet,schema_version}' IS DISTINCT FROM 'ENGINEERING_EXECUTION_PACKET_V2' THEN
    RAISE EXCEPTION 'ROUTER_SCHEMA_REGRESSION schema=%',v_boot#>>'{execution_packet,schema_version}';
  END IF;
  SELECT count(*) INTO v_cases FROM public.lf_test_suite_cases WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code ~ '^M3_8_';
  IF v_cases<>7 THEN RAISE EXCEPTION 'M3_8_CASE_SET_INVALID count=%',v_cases; END IF;
  SELECT exit_criterion INTO v_exit FROM programacion.engineering_plan_units WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M3.8';
  IF position('cobertura aplicable por resolver' in v_exit)=0 THEN RAISE EXCEPTION 'M3_8_EXIT_CRITERION_NOT_SIMPLIFIED'; END IF;
END;
$$;
