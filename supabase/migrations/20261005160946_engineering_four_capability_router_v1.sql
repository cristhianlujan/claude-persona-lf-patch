DO $$
DECLARE v_packet_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_packet_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  IF v_packet_md5 IS DISTINCT FROM 'f98be6360b2fcc2a7828d2a0e047bc59' THEN
    RAISE EXCEPTION 'EXECUTION_PACKET_V1_FINGERPRINT_DRIFT expected=% actual=%','f98be6360b2fcc2a7828d2a0e047bc59',v_packet_md5;
  END IF;
END;
$$;

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
    coalesce(p_action_spec->>'recipe_mode','') recipe_mode,
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
      'DECLARED_TEST_PERSISTENCE_EXECUTION','DECISION_GATE','CONCURRENCY_EXECUTION',
      'REPRODUCIBILITY_EXECUTION','OBSERVE_ONCE','TERMINAL_RECONCILE','MUTATION_EXECUTION'
    ) inherent_operation,
    exists(
      select 1 from jsonb_array_elements(artifacts) a
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
), c as materialized (
  select d.*,
    case
      when (action_kind='VERIFY_QUERY_ONCE' and not has_verification and has_predecessor)
        or (
          recipe_mode<>'EXECUTE_CANONICAL_CLOSURE_EVENT'
          and action_kind in (
            'ROLLBACK_DRILL','FAULT_INJECTION','FAULT_INJECTION_TIMEOUT','DECLARED_TEST_EXECUTION',
            'DECLARED_TEST_PERSISTENCE_EXECUTION','CONCURRENCY_EXECUTION','REPRODUCIBILITY_EXECUTION','MUTATION_EXECUTION'
          )
        ) then 'RUN_TEST'
      when action_kind in ('OBSERVE_ONCE','READBACK_ONCE','VERIFY_QUERY_ONCE','TERMINAL_RECONCILE','DECISION_GATE')
        or not effective_material then 'READ'
      when has_artifact then 'WRITE_GIT'
      else 'WRITE_DB'
    end execution_capability,
    case
      when action_kind='VERIFY_QUERY_ONCE' and not has_verification and has_predecessor then 'AUTHORED_NEGATIVE'
      when recipe_mode='EXECUTE_CANONICAL_CLOSURE_EVENT' then 'CANONICAL_CLOSURE_EVENT'
      when has_artifact and has_migration_artifact then 'MIGRATION'
      when has_artifact then 'ARTIFACT'
      else action_kind
    end capability_mode
  from d
)
select jsonb_build_object(
  'schema_version','ENGINEERING_EXECUTION_PACKET_V2',
  'status',packet_status,
  'plan_code',p_plan_code,
  'unit_code',p_unit_code,
  'checkpoint_code',p_checkpoint_code,
  'execution_capability',execution_capability,
  'capability_mode',capability_mode,
  'requires_material_execution',effective_material,
  'effective_action_kind',case when read_only_reclass then 'READBACK_ONCE' else action_kind end,
  'verification_mode',case
    when execution_capability='RUN_TEST' then 'CAPABILITY_OWNED'
    when execution_capability='WRITE_DB' then 'CAPABILITY_OWNED'
    when execution_capability='WRITE_GIT' then 'CAPABILITY_OWNED'
    when has_verification then 'DECLARED_QUERY_READBACK'
    else 'NOT_REQUIRED'
  end,
  'block_reasons',
      (case when effective_material and not has_target then jsonb_build_array('MISSING_DECLARED_TARGET') else '[]'::jsonb end)
    || (case when effective_material and expects_migration and not has_migration_artifact then jsonb_build_array('MISSING_OUTPUT_MIGRATION_ARTIFACT') else '[]'::jsonb end)
    || (case when action_kind<>'DECLARED_TEST_PERSISTENCE_EXECUTION' and ((effective_material and not has_migration_artifact) or (action_kind='VERIFY_QUERY_ONCE' and not effective_material and not has_predecessor)) and not has_verification then jsonb_build_array('MISSING_VERIFICATION') else '[]'::jsonb end)
    || (case when effective_material and has_target and (has_verification or has_migration_artifact or action_kind='DECLARED_TEST_PERSISTENCE_EXECUTION') and not inherent_operation and not has_artifact and not has_db_deliverable then jsonb_build_array('MISSING_EXECUTABLE_ARTIFACT_OR_OPERATION') else '[]'::jsonb end),
  'capability_contract',jsonb_build_object(
    'router_surface','READ|WRITE_DB|WRITE_GIT|RUN_TEST',
    'mode_owner','CAPABILITY_EXECUTOR',
    'checkpoint_scope','CURRENT_CHECKPOINT_ONLY',
    'no_new_router_branch_for_mode',true,
    'transition_owner','programacion.fn_engineering_checkpoint_transition_v1'
  ),
  'connector_plan',programacion.fn_engineering_plan_add_transition_args_v1(case
    when packet_status<>'READY' then '[]'::jsonb
    when execution_capability='READ' then jsonb_build_array(
      jsonb_build_object(
        'seq',1,'provider','SUPABASE','operation','READ','capability','READ','mode',capability_mode,
        'queries',verification_queries,'targets',objects,
        'executor_contract',jsonb_build_object(
          'query_mode','ONE_STATEMENT_PER_CALL',
          'use_execution_input_when_queries_empty',true,
          'domain_mutation','FORBIDDEN'
        )
      ),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when execution_capability='WRITE_DB' then jsonb_build_array(
      jsonb_build_object(
        'seq',1,'provider','SUPABASE','operation','WRITE_DB','capability','WRITE_DB','mode',capability_mode,
        'targets',objects,'queries',verification_queries,
        'executor_contract',jsonb_build_object(
          'own_mutation_and_verification',true,
          'touch_only_declared_targets',true,
          'dry_run_when_authoring_sql',true,
          'idempotent_or_guarded',true,
          'return_evidence_for_transition',true
        )
      ),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when execution_capability='WRITE_GIT' then
      jsonb_build_array(
        jsonb_build_object(
          'seq',1,'provider','GITHUB','operation','WRITE_GIT','capability','WRITE_GIT','mode',capability_mode,
          'targets',artifacts,'write_route','SCOPED_BRANCH_PR_MERGE',
          'executor_contract',jsonb_build_object(
            'direct_default_branch_write','FORBIDDEN',
            'branch_required',true,'pr_required',true,'merge_required',true
          )
        )
      )
      || case when has_migration_artifact then jsonb_build_array(
        jsonb_build_object(
          'seq',2,'provider','SUPABASE','operation','WRITE_DB','capability','WRITE_DB','mode','APPLY_MERGED_MIGRATION',
          'targets',objects,'artifacts',artifacts,'queries',verification_queries,
          'executor_contract',jsonb_build_object('apply_exact_merged_migration',true,'own_post_apply_readback',true)
        ),
        jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
      ) else jsonb_build_array(
        jsonb_build_object(
          'seq',2,'provider','SUPABASE','operation','READ','capability','READ','mode','POST_WRITE_GIT_READBACK',
          'queries',verification_queries,'targets',objects,
          'executor_contract',jsonb_build_object('query_mode','ONE_STATEMENT_PER_CALL','domain_mutation','FORBIDDEN')
        ),
        jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
      ) end
    when execution_capability='RUN_TEST' then jsonb_build_array(
      jsonb_build_object(
        'seq',1,'provider','SUPABASE','operation','RUN_TEST','capability','RUN_TEST','mode',capability_mode,
        'targets',objects,'queries',verification_queries,
        'test_scope',jsonb_build_object('plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
        'executor_contract',jsonb_build_object(
          'case_authority','public.lf_test_suite_cases',
          'persistence_owner','RUN_TEST_EXECUTOR',
          'canonical_persistence_graph',jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'),
          'persist_graph_when_required_by_checkpoint',true,
          'synthetic_pass','FORBIDDEN',
          'full_suite_rerun','FORBIDDEN_UNLESS_EXPLICIT_SCOPE',
          'missing_scope','MISSING_CANONICAL_TEST_EXECUTOR',
          'return_evidence_for_transition',true
        )
      ),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    else '[]'::jsonb
  end,p_plan_code,p_unit_code,p_checkpoint_code),
  'retry_policy',jsonb_build_object(
    'restart_checkpoint',false,'retry_same_failed_operation_only',true,'max_immediate_retries',1,
    'on_rate_limit','RETRY_SAME_OPERATION_ONLY','on_safety_block','REDUCE_TO_EXACT_SINGLE_OPERATION_OR_STOP'
  ),
  'tool_failure_protocol',jsonb_build_object(
    'record_phase','CONNECTOR_BLOCKED','record_on_next_success_if_provider_unavailable',true,'do_not_rebootstrap_before_retry',true
  ),
  'mutation_policy',case when execution_capability='READ' then 'NO_DOMAIN_MUTATION' else 'ONLY_DECLARED_TARGETS' end,
  'query_execution_policy',jsonb_build_object(
    'mode','ONE_STATEMENT_PER_CALL','statement_count',jsonb_array_length(verification_queries),
    'forbidden','CONCATENATE_STATEMENTS_IN_ONE_CALL','reason','CONNECTOR_RETURNS_ONLY_LAST_RESULT'
  ),
  'execution_input',p_execution_input
)
from c;
$function$;

DO $$
DECLARE
  v_read jsonb;
  v_db jsonb;
  v_git jsonb;
  v_migration jsonb;
  v_m38 jsonb;
  v_bad_count bigint;
BEGIN
  v_read:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','READ','CP',
    jsonb_build_object('status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT','checkpoint_title','Readback control','requires_material_execution',false,'target',jsonb_build_object('declared_objects',jsonb_build_array('public.selftest'),'declared_artifacts','[]'::jsonb),'verification_queries',jsonb_build_array('select 1')),
    '{}'::jsonb
  );
  IF v_read->>'execution_capability'<>'READ' OR v_read#>>'{connector_plan,0,operation}'<>'READ' THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_READ_SELFTEST_FAIL packet=%',v_read;
  END IF;

  v_db:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','WRITE_DB','CP',
    jsonb_build_object('status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE','recipe_mode','EXECUTE_DECLARED_DELIVERABLE','checkpoint_title','Crear objeto control','requires_material_execution',true,'target',jsonb_build_object('declared_objects',jsonb_build_array('public.selftest'),'declared_artifacts','[]'::jsonb),'verification_queries',jsonb_build_array('select 1')),
    '{}'::jsonb
  );
  IF v_db->>'execution_capability'<>'WRITE_DB' OR v_db#>>'{connector_plan,0,operation}'<>'WRITE_DB' THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_WRITE_DB_SELFTEST_FAIL packet=%',v_db;
  END IF;

  v_git:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','WRITE_GIT','CP',
    jsonb_build_object('status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE','recipe_mode','EXECUTE_DECLARED_DELIVERABLE','checkpoint_title','Crear artefacto fuera de migraciones','requires_material_execution',true,'target',jsonb_build_object('declared_objects','[]'::jsonb,'declared_artifacts',jsonb_build_array(jsonb_build_object('path','owner/repo:tests/selftest.json'))),'verification_queries',jsonb_build_array('select 1')),
    '{}'::jsonb
  );
  IF v_git->>'execution_capability'<>'WRITE_GIT' OR v_git->>'capability_mode'<>'ARTIFACT' OR v_git#>>'{connector_plan,0,operation}'<>'WRITE_GIT' THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_WRITE_GIT_SELFTEST_FAIL packet=%',v_git;
  END IF;

  v_migration:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'SELFTEST','MIGRATION','CP',
    jsonb_build_object('status','READY','action_kind','MATERIALIZE_DECLARED_DELIVERABLE','recipe_mode','EXECUTE_DECLARED_DELIVERABLE','checkpoint_title','Migración control','requires_material_execution',true,'target',jsonb_build_object('declared_objects',jsonb_build_array('public.selftest'),'declared_artifacts',jsonb_build_array(jsonb_build_object('path','owner/repo:supabase/migrations/selftest.sql'))),'verification_queries',jsonb_build_array('select 1')),
    '{}'::jsonb
  );
  IF v_migration->>'execution_capability'<>'WRITE_GIT' OR v_migration->>'capability_mode'<>'MIGRATION' OR v_migration#>>'{connector_plan,1,operation}'<>'WRITE_DB' OR v_migration#>>'{connector_plan,1,mode}'<>'APPLY_MERGED_MIGRATION' THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_MIGRATION_SELFTEST_FAIL packet=%',v_migration;
  END IF;

  v_m38:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8');
  IF v_m38#>>'{execution_packet,execution_capability}'<>'RUN_TEST' OR v_m38#>>'{execution_packet,connector_plan,0,operation}'<>'RUN_TEST' THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_M38_SELFTEST_FAIL packet=%',v_m38->'execution_packet';
  END IF;

  with pending as (
    select pu.plan_code,pu.unit_code,c.checkpoint_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.disposition<>'FUSED' and c.status not in ('DONE','NOT_APPLICABLE')
  ), packets as (
    select programacion.fn_engineering_execution_packet_from_spec_v1(
      p.plan_code,p.unit_code,p.checkpoint_code,
      programacion.fn_engineering_checkpoint_action_spec_v3(p.plan_code,p.unit_code,p.checkpoint_code),
      '{}'::jsonb
    ) packet
    from pending p
  )
  select count(*) into v_bad_count
  from packets
  where coalesce(packet->>'execution_capability','') not in ('READ','WRITE_DB','WRITE_GIT','RUN_TEST');

  IF v_bad_count<>0 THEN
    RAISE EXCEPTION 'FOUR_CAPABILITY_PENDING_SURFACE_HAS_UNKNOWN_CAPABILITY count=%',v_bad_count;
  END IF;
END;
$$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES (
  'ENGINEERING-FOUR-CAPABILITY-ROUTER-001','ENGINEERING_GOVERNANCE',
  'Engineering router must expose only four execution capabilities',
  'Per-checkpoint action variants were leaking into orchestration and forcing a new router branch for each casuistic.',
  'The execution packet used action_kind-specific connector routing instead of delegating variants to stable capability executors.',
  'new action_kind -> new orchestration branch -> repeated transversal patches and growing operational complexity',
  'The execution packet routes only READ, WRITE_DB, WRITE_GIT or RUN_TEST. action_kind remains a capability mode owned by the executor. A new mode must not create a fifth router capability.',
  'PASS when every pending IG checkpoint compiles to exactly one of READ|WRITE_DB|WRITE_GIT|RUN_TEST; M3.8 RUN_PERSIST compiles RUN_TEST; migrations and artifacts compile WRITE_GIT; DB materialization compiles WRITE_DB; readbacks compile READ.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT','Engineering orchestration complexity and action-mode fanout',
  'supabase://programacion.fn_engineering_execution_packet_from_spec_v1'
)
ON CONFLICT (codigo) DO UPDATE SET
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref;

UPDATE public.lf_error_knowledge
SET prevencion='Bootstrap execution packets route only READ, WRITE_DB, WRITE_GIT or RUN_TEST. Connector and test variants are capability modes and must be handled inside the capability executor; no new router branch per casuistic. Git writes remain scoped branch + PR; retries remain same-operation only.',
    validacion='PASS when all pending IG checkpoints expose one of the four capabilities only, with migration/artifact behavior owned by WRITE_GIT and test persistence behavior owned by RUN_TEST.'
WHERE codigo='ENGINEERING-EXECUTION-PACKET-001';

UPDATE public.lf_error_knowledge
SET prevencion='RUN_TEST owns the canonical suite_run -> test_run -> assertion_result graph when persistence is required. The orchestration router must not branch on assertion/FK details.',
    validacion='PASS when test-persistence checkpoints route as RUN_TEST and graph details remain executor-owned rather than creating new orchestration branches.'
WHERE codigo='ENGINEERING-TEST-PERSISTENCE-GRAPH-001';
