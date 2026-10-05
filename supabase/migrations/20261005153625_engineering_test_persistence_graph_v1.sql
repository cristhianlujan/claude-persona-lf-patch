DO $$
DECLARE
  v_action_md5 text;
  v_packet_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_action_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v3';

  SELECT md5(p.prosrc) INTO v_packet_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';

  IF v_action_md5 IS DISTINCT FROM '67749345a126df856fd37b51a58c73b9' THEN
    RAISE EXCEPTION 'ACTION_SPEC_V3_FINGERPRINT_DRIFT expected=% actual=%','67749345a126df856fd37b51a58c73b9',v_action_md5;
  END IF;
  IF v_packet_md5 IS DISTINCT FROM '358ccc15d42c422e6d63fefdf775a651' THEN
    RAISE EXCEPTION 'EXECUTION_PACKET_V1_FINGERPRINT_DRIFT expected=% actual=%','358ccc15d42c422e6d63fefdf775a651',v_packet_md5;
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
          'public.lf_test_suite_runs',
          'public.lf_test_runs',
          'public.lf_test_assertion_results'
        )
      ),
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','RETURNED_ID_GRAPH_READBACK',
        'design_boundary','CANONICAL_LF_TEST_PERSISTENCE_GRAPH_ONLY',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1',
        'execution_semantics','REAL_TEST_EXECUTION_REQUIRED'
      ),
      'action_steps',jsonb_build_array(
        'EXECUTE_CURRENT_CHECKPOINT_TEST_SCOPE',
        'PERSIST_ATOMIC_SUITE_RUN_TEST_RUN_ASSERTION_GRAPH',
        'DERIVE_STATUS_FROM_ACTUAL_TEST_AND_ASSERTION_RESULTS',
        'READBACK_CREATED_GRAPH_BY_RETURNED_IDS',
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
        'ATTACH_ASSERTIONS_TO_UNRELATED_RUN'
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

CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'programacion','public','pg_catalog'
AS $function$
with x as materialized (
  select
    coalesce(p_action_spec->>'status','') spec_status,
    coalesce(p_action_spec->>'action_kind','') action_kind,
    lower(coalesce(p_action_spec->>'checkpoint_title','')) title_l,
    exists(
      select 1
      from programacion.engineering_plan_units pu
      join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
      join programacion.engineering_work_checkpoints cur on cur.work_item_id=pu.work_item_id and cur.checkpoint_code=p_checkpoint_code
      where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and c.sequence_no<cur.sequence_no
    ) has_predecessor,
    coalesce((p_action_spec->>'requires_material_execution')::boolean,false) declared_material,
    coalesce(p_action_spec#>'{target,declared_objects}','[]'::jsonb) objects,
    coalesce(p_action_spec#>'{target,declared_artifacts}','[]'::jsonb) artifacts,
    coalesce(p_action_spec->'verification_queries','[]'::jsonb) verification_queries
), f as materialized (
  select x.*,
    (
      declared_material
      and title_l ~ '^(conteo|readback|verificar|comprobar|observar|listar|inspeccionar)'
      and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|emitir|registrar|migraci)'
    ) read_only_reclass,
    (jsonb_array_length(objects)>0 or jsonb_array_length(artifacts)>0) has_target,
    (jsonb_array_length(artifacts)>0) has_artifact,
    (jsonb_array_length(objects)>0 and jsonb_array_length(verification_queries)>0) has_db_deliverable,
    (jsonb_array_length(verification_queries)>0) has_verification,
    action_kind in (
      'ROLLBACK_DRILL','VERIFY_QUERY_ONCE','FAULT_INJECTION','DECLARED_TEST_EXECUTION',
      'DECLARED_TEST_PERSISTENCE_EXECUTION',
      'DECISION_GATE','CONCURRENCY_EXECUTION','REPRODUCIBILITY_EXECUTION','OBSERVE_ONCE',
      'TERMINAL_RECONCILE','MUTATION_EXECUTION'
    ) inherent_operation,
    exists(
      select 1
      from jsonb_array_elements(artifacts) a
      where coalesce(a->>'path','') like '%:supabase/migrations/%'
    ) has_migration_artifact,
    (title_l ~ '(migraci|git-first)' and title_l !~ '(fuera de|sin|excepto|salvo) (las |los )?migraci') expects_migration
  from x
), d as materialized (
  select *,
    (declared_material and not read_only_reclass) effective_material,
    case
      when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'
      when action_kind='VERIFY_QUERY_ONCE' and not has_verification and not has_predecessor then 'BLOCK_SPEC_INCOMPLETE'
      when not (declared_material and not read_only_reclass) then 'READY'
      when not has_target then 'BLOCK_SPEC_INCOMPLETE'
      when expects_migration and not has_migration_artifact then 'BLOCK_SPEC_INCOMPLETE'
      when action_kind<>'DECLARED_TEST_PERSISTENCE_EXECUTION' and not has_verification and not has_migration_artifact then 'BLOCK_SPEC_INCOMPLETE'
      when inherent_operation or has_artifact or has_db_deliverable then 'READY'
      else 'BLOCK_SPEC_INCOMPLETE'
    end packet_status
  from f
)
select jsonb_build_object(
  'schema_version','ENGINEERING_EXECUTION_PACKET_V1',
  'status',packet_status,
  'plan_code',p_plan_code,
  'unit_code',p_unit_code,
  'checkpoint_code',p_checkpoint_code,
  'requires_material_execution',effective_material,
  'effective_action_kind',case when read_only_reclass then 'READBACK_ONCE' else action_kind end,
  'verification_mode',case
    when action_kind='DECLARED_TEST_PERSISTENCE_EXECUTION' then 'RETURNED_ID_GRAPH_READBACK'
    when effective_material and has_migration_artifact and not has_verification then 'DERIVED_MIGRATION_POST_APPLY_READBACK'
    when has_verification then 'DECLARED_QUERY_READBACK'
    when action_kind='VERIFY_QUERY_ONCE' and has_predecessor then 'AUTHORED_NEGATIVE_WITH_POSITIVE_CONTROL'
    else 'NOT_REQUIRED'
  end,
  'block_reasons',
      (case when effective_material and not has_target then jsonb_build_array('MISSING_DECLARED_TARGET') else '[]'::jsonb end)
    || (case when effective_material and expects_migration and not has_migration_artifact then jsonb_build_array('MISSING_OUTPUT_MIGRATION_ARTIFACT') else '[]'::jsonb end)
    || (case when action_kind<>'DECLARED_TEST_PERSISTENCE_EXECUTION' and ((effective_material and not has_migration_artifact) or (action_kind='VERIFY_QUERY_ONCE' and not effective_material and not has_predecessor)) and not has_verification then jsonb_build_array('MISSING_VERIFICATION') else '[]'::jsonb end)
    || (case when effective_material and has_target and (has_verification or has_migration_artifact or action_kind='DECLARED_TEST_PERSISTENCE_EXECUTION') and not inherent_operation and not has_artifact and not has_db_deliverable then jsonb_build_array('MISSING_EXECUTABLE_ARTIFACT_OR_OPERATION') else '[]'::jsonb end),
  'connector_plan',programacion.fn_engineering_plan_add_transition_args_v1(case
    when packet_status<>'READY' then '[]'::jsonb
    when action_kind='VERIFY_QUERY_ONCE' and not has_verification and has_predecessor then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','EXECUTE_AUTHORED_NEGATIVE_CASES',
        'transaction','SINGLE_STATEMENT_DO_BLOCK_WITH_FORCED_ROLLBACK',
        'requires',jsonb_build_array('ONE_POSITIVE_CONTROL_MUST_BE_ACCEPTED','AT_LEAST_ONE_NEGATIVE_REJECTED_PER_CLAUSE_OF_CHECKPOINT_TITLE','TARGETS_ARE_OBJECTS_CREATED_BY_PRECEDING_CHECKPOINTS_OF_THE_SAME_UNIT','NO_PERSISTENT_MUTATION'),
        'on_control_rejected','CONTRADICTION_DELIVERABLE_NOT_FUNCTIONAL',
        'on_missing_target','MISSING_CANONICAL_OBJECT',
        'evidence_must_include',jsonb_build_array('control_result','negative_results','statement_sha256')),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when not effective_material then coalesce((select jsonb_agg(jsonb_build_object('seq',t.ord,'provider','SUPABASE','operation','EXECUTE_SQL_READONLY','query',t.q,'statement_index',t.ord,'statement_count',jsonb_array_length(verification_queries)) order by t.ord) from jsonb_array_elements_text(verification_queries) with ordinality t(q,ord)),'[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('seq',jsonb_array_length(verification_queries)+1,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION'))
    when action_kind='DECLARED_TEST_PERSISTENCE_EXECUTION' then jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','SUPABASE',
        'operation','EXECUTE_DECLARED_TEST_PERSISTENCE',
        'targets',objects,
        'source_case_authority','public.lf_test_suite_cases',
        'scope','CURRENT_CHECKPOINT_ONLY',
        'requires',jsonb_build_array(
          'EXECUTE_REAL_CURRENT_CHECKPOINT_TEST_SCOPE',
          'PERSIST_SUITE_RUN_BEFORE_TEST_RUNS',
          'PERSIST_TEST_RUN_BEFORE_ASSERTION_RESULTS',
          'DERIVE_STATUS_FROM_ACTUAL_RESULTS',
          'ATOMIC_GRAPH_OR_FULL_ROLLBACK'
        ),
        'forbidden',jsonb_build_array(
          'SYNTHETIC_PASS_WITHOUT_TEST_EXECUTION',
          'ASSERTION_WITHOUT_TEST_RUN',
          'TEST_RUN_WITHOUT_SUITE_RUN',
          'ATTACH_ASSERTIONS_TO_UNRELATED_RUN'
        ),
        'result_contract',jsonb_build_object(
          'required_fields',jsonb_build_array('suite_run_id','test_run_ids','assertion_result_ids','suite_status'),
          'suite_status_rule','DERIVED_FROM_ACTUAL_TEST_AND_ASSERTION_RESULTS',
          'no_synthetic_pass',true
        ),
        'on_missing_executor','MISSING_CANONICAL_TEST_EXECUTOR',
        'on_unexecutable_case','CONTRADICTION'
      ),
      jsonb_build_object(
        'seq',2,
        'provider','SUPABASE',
        'operation','READBACK_DECLARED_TEST_PERSISTENCE_GRAPH',
        'bind_from_seq',1,
        'targets',objects,
        'requires',jsonb_build_array(
          'SUITE_RUN_ID_EXISTS',
          'ALL_TEST_RUN_IDS_REFERENCE_SUITE_RUN_ID',
          'ALL_ASSERTION_RESULT_IDS_REFERENCE_RETURNED_TEST_RUN_IDS',
          'NO_ORPHAN_GRAPH_ROWS',
          'READBACK_STATUS_EQUALS_PERSISTED_STATUS'
        )
      ),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when inherent_operation then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation',action_kind,'queries',verification_queries,'targets',objects),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when has_db_deliverable and not has_artifact then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','MATERIALIZE_DECLARED_DB_OBJECTS','targets',objects,
        'authority','AUTHOR_MINIMAL_SQL_THAT_MAKES_CHECKPOINT_TITLE_TRUE_ON_DECLARED_TARGETS_ONLY',
        'procedure',jsonb_build_array('IF_TITLE_ONLY_VERIFIES_EXISTING_STATE_SKIP_AUTHORING_AND_RUN_VERIFICATION_QUERIES','AUTHOR_MINIMAL_SQL','DRY_RUN_IN_SINGLE_DO_BLOCK_WITH_FORCED_ROLLBACK_AND_RUN_VERIFICATION_QUERIES','APPLY_ONCE_VIA_APPLY_MIGRATION_WITH_GUARDS','RUN_VERIFICATION_QUERIES_ONE_PER_CALL','PERSIST_DONE_ONLY_IF_READBACK_MATCHES_TITLE'),
        'forbidden',jsonb_build_array('TOUCH_OBJECTS_OUTSIDE_DECLARED_TARGETS','SKIP_DRY_RUN','DESTRUCTIVE_DDL_NOT_REQUIRED_BY_TITLE'),
        'on_title_not_expressible_as_sql','MISSING_CANONICAL_OBJECT'),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when has_migration_artifact then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','GITHUB','operation','USE_OR_CREATE_DECLARED_MIGRATION_ARTIFACT','targets',artifacts),
      jsonb_build_object('seq',2,'provider','GITHUB','operation','OPEN_AND_MERGE_SCOPED_PR'),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','APPLY_DECLARED_MIGRATION'),
      jsonb_build_object(
        'seq',4,
        'provider','SUPABASE',
        'operation',case when has_verification then 'EXECUTE_SQL_READBACK' else 'VERIFY_APPLIED_MIGRATION_AND_DECLARED_EFFECTS' end,
        'queries',verification_queries,
        'targets',objects,
        'artifacts',artifacts
      ),
      jsonb_build_object('seq',5,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    else jsonb_build_array(
      jsonb_build_object('seq',1,'provider','GITHUB','operation','USE_OR_CREATE_DECLARED_ARTIFACT','targets',artifacts,'write_route','SCOPED_BRANCH_ONLY'),
      jsonb_build_object('seq',2,'provider','GITHUB','operation','OPEN_AND_MERGE_SCOPED_PR'),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',4,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
  end,p_plan_code,p_unit_code,p_checkpoint_code),
  'retry_policy',jsonb_build_object(
    'restart_checkpoint',false,
    'retry_same_failed_operation_only',true,
    'max_immediate_retries',1,
    'on_rate_limit','RETRY_SAME_OPERATION_ONLY',
    'on_safety_block','REDUCE_TO_EXACT_SINGLE_OPERATION_OR_STOP'
  ),
  'tool_failure_protocol',jsonb_build_object(
    'record_phase','CONNECTOR_BLOCKED',
    'record_on_next_success_if_provider_unavailable',true,
    'do_not_rebootstrap_before_retry',true
  ),
  'mutation_policy',case when effective_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
  'query_execution_policy',jsonb_build_object('mode','ONE_STATEMENT_PER_CALL','statement_count',jsonb_array_length(verification_queries),'forbidden','CONCATENATE_STATEMENTS_IN_ONE_CALL','reason','CONNECTOR_RETURNS_ONLY_LAST_RESULT'),
  'execution_input',p_execution_input
)
from d;
$function$;

DO $$
DECLARE
  v_boot jsonb;
  v_spec jsonb;
  v_packet jsonb;
  v_migration_packet jsonb;
  v_artifact_packet jsonb;
BEGIN
  v_boot := programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8');
  v_spec := v_boot->'action_spec';
  v_packet := v_boot->'execution_packet';

  IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'RUN_PERSIST' THEN
    RAISE EXCEPTION 'M3.8_CURRENT_CHECKPOINT_DRIFT actual=%',v_boot#>>'{current_checkpoint,checkpoint_code}';
  END IF;
  IF v_spec->>'action_kind' IS DISTINCT FROM 'DECLARED_TEST_PERSISTENCE_EXECUTION' THEN
    RAISE EXCEPTION 'M3.8_TEST_PERSISTENCE_ACTION_KIND_NOT_COMPILED actual=%',v_spec->>'action_kind';
  END IF;
  IF NOT (v_spec#>'{target,declared_objects}' @> jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results')) THEN
    RAISE EXCEPTION 'M3.8_TEST_PERSISTENCE_GRAPH_INCOMPLETE targets=%',v_spec#>'{target,declared_objects}';
  END IF;
  IF v_packet->>'status' IS DISTINCT FROM 'READY' THEN
    RAISE EXCEPTION 'M3.8_TEST_PERSISTENCE_PACKET_NOT_READY packet=%',v_packet;
  END IF;
  IF v_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'EXECUTE_DECLARED_TEST_PERSISTENCE'
     OR v_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'READBACK_DECLARED_TEST_PERSISTENCE_GRAPH'
     OR v_packet#>>'{connector_plan,2,operation}' IS DISTINCT FROM 'CHECKPOINT_TRANSITION' THEN
    RAISE EXCEPTION 'M3.8_TEST_PERSISTENCE_ROUTE_INVALID plan=%',v_packet->'connector_plan';
  END IF;
  IF v_packet#>>'{verification_mode}' IS DISTINCT FROM 'RETURNED_ID_GRAPH_READBACK' THEN
    RAISE EXCEPTION 'M3.8_TEST_PERSISTENCE_VERIFICATION_MODE_INVALID actual=%',v_packet#>>'{verification_mode}';
  END IF;

  v_migration_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','MIGRATION','CP',
    jsonb_build_object(
      'status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE','checkpoint_title','Migración control',
      'requires_material_execution',true,
      'target',jsonb_build_object('declared_objects',jsonb_build_array('public.selftest_target'),'declared_artifacts',jsonb_build_array(jsonb_build_object('path','owner/repo:supabase/migrations/selftest.sql'))),
      'verification_queries',jsonb_build_array('select 1')
    ),'{}'::jsonb
  );
  IF v_migration_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'USE_OR_CREATE_DECLARED_MIGRATION_ARTIFACT'
     OR v_migration_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'OPEN_AND_MERGE_SCOPED_PR'
     OR v_migration_packet#>>'{connector_plan,2,operation}' IS DISTINCT FROM 'APPLY_DECLARED_MIGRATION' THEN
    RAISE EXCEPTION 'MIGRATION_ROUTE_REGRESSION plan=%',v_migration_packet->'connector_plan';
  END IF;

  v_artifact_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','ARTIFACT','CP',
    jsonb_build_object(
      'status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE','checkpoint_title','Crear artefacto fuera de migraciones',
      'requires_material_execution',true,
      'target',jsonb_build_object('declared_objects','[]'::jsonb,'declared_artifacts',jsonb_build_array(jsonb_build_object('path','owner/repo:tests/selftest.json'))),
      'verification_queries',jsonb_build_array('select 1')
    ),'{}'::jsonb
  );
  IF v_artifact_packet#>>'{connector_plan,0,operation}' IS DISTINCT FROM 'USE_OR_CREATE_DECLARED_ARTIFACT'
     OR v_artifact_packet#>>'{connector_plan,0,write_route}' IS DISTINCT FROM 'SCOPED_BRANCH_ONLY'
     OR v_artifact_packet#>>'{connector_plan,1,operation}' IS DISTINCT FROM 'OPEN_AND_MERGE_SCOPED_PR' THEN
    RAISE EXCEPTION 'NON_MIGRATION_ARTIFACT_ROUTE_REGRESSION plan=%',v_artifact_packet->'connector_plan';
  END IF;
END;
$$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES (
  'ENGINEERING-TEST-PERSISTENCE-GRAPH-001','ENGINEERING_GOVERNANCE',
  'LF test persistence requires suite_run -> test_run -> assertion_result graph',
  'A checkpoint that declared lf_test_suite_runs and lf_test_assertion_results omitted lf_test_runs and could be compiled as generic SQL materialization, allowing incomplete or synthetic persistence.',
  'Action-spec compilation treated canonical LF test persistence as an arbitrary DB deliverable and did not encode the mandatory foreign-key graph or real-execution semantics.',
  'suite_run + assertion_result declared without test_run -> generic MATERIALIZE_DECLARED_DB_OBJECTS -> FK contradiction or synthetic evidence risk',
  'Action Spec V3 expands the canonical LF test persistence graph to lf_test_suite_runs, lf_test_runs and lf_test_assertion_results. Execution Packet V1 emits a typed EXECUTE_DECLARED_TEST_PERSISTENCE followed by returned-ID graph readback and forbids synthetic PASS or unrelated run attachment.',
  'PASS when M3.8 RUN_PERSIST compiles READY as DECLARED_TEST_PERSISTENCE_EXECUTION with all three canonical targets, seq1 EXECUTE_DECLARED_TEST_PERSISTENCE, seq2 READBACK_DECLARED_TEST_PERSISTENCE_GRAPH, seq3 CHECKPOINT_TRANSITION; migration and non-migration artifact routes remain unchanged.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT','LF canonical test persistence graph and engineering execution packet compilation',
  'supabase://programacion.fn_engineering_checkpoint_action_spec_v3|supabase://programacion.fn_engineering_execution_packet_from_spec_v1'
)
ON CONFLICT (codigo) DO UPDATE SET
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref;

UPDATE public.lf_error_knowledge
SET prevencion='Bootstrap V3 must expose ENGINEERING_EXECUTION_PACKET_V1. Material work without declared target, verification and executable output artifact/operation is blocked. Canonical LF test persistence is compiled as suite_run -> test_run -> assertion_result with real-execution semantics and returned-ID graph readback; synthetic PASS is forbidden. GitHub writes use scoped branch + PR; retry is same failed operation only and never restarts the checkpoint.',
    validacion='PASS when M3.6 migration/DB-deliverable compatibility remains READY, non-migration artifacts use scoped branch + PR, and M3.8 RUN_PERSIST compiles to the canonical three-layer LF test persistence graph without changing ledger progress.'
WHERE codigo='ENGINEERING-EXECUTION-PACKET-001';
