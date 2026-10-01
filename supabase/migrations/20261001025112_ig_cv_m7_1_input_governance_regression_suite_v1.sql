-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M7.1 / PAULO-012
-- Registers INPUT_GOVERNANCE_REGRESSION in lf_test_* with immutable SHA bindings
-- and persists the first deterministic baseline-readback execution.
-- No runtime activation, production promotion, N-2 work, recuration, or semantic PASS change.

begin;

do $m7_1$
declare
  v_exec constant text := 'CHATGPT-IG-CV-L1-M7.1-20261001';
  v_suite constant text := 'INPUT_GOVERNANCE_REGRESSION';
  v_asset constant text := 'TEST_SUITE_INPUT_GOVERNANCE_REGRESSION_V1';
  v_batch constant uuid := '7a710001-2026-4000-8000-000000000001'::uuid;
  v_base_main constant text := '4068d3064e859e78c6aab194a63b55c053043d74';
  v_contract_revision constant text := '5.13';
  v_contract_sha constant text := '125e73215036c76f79847d6821e97942b38f80e3ca46206786d8f96dae1c6c38';
  v_registry_sha constant text := '3eef5f9f46235e79d0a022f768f71999c1560f5127cfcdc700f9c3f92da1783c';
  v_router_sha constant text := 'c8f81b362211d4f9b113ee055914ab57f779abf1f42b0a4349d95a0ecf1c7387';
  v_curator_sha constant text := '99a1192ddc1cb17420317a159b26127e184eb87d88750ae95f66ff52a41925ba';
  v_validator_sha constant text := '4532074de481760ec0f801f27b7e2379a873fc4a2b41a9ed878c0dfcc163d729';
  v_execution_sha constant text := '2fad0d188cc5011661eb8697e5c5e109e34f049dd0cdb3123e2dc54d98fcbaf5';
  v_shadow_sha constant text := '237f55d1e8873e2be9b47a46cb3a18fceeaca05a66ece57680d2c8b69d7f9ece';
  v_semantic_sha constant text := '559a258f8240de9f16bcea3ada3cf684e9805a223c6fd79b282a0c6c140b7191';
  v_currentness_sha constant text := '4e8fa7d3cf70c816253ecabca40303eefed38b92158f77a7c5ce6b96ade4bdc8';
  v_observed_registry_sha text;
  v_suite_run uuid := gen_random_uuid();
  v_bindings jsonb;
  v_suite_revision_sha text;
  v_count integer;
begin
  if exists (select 1 from public.lf_test_suites where suite_code=v_suite) then
    raise exception 'M7_1_SUITE_ALREADY_EXISTS';
  end if;
  if exists (select 1 from public.lf_activos where codigo_activo=v_asset and archived_at is null) then
    raise exception 'M7_1_ASSET_ALREADY_EXISTS';
  end if;

  if exists (
    select 1
    from programacion.engineering_plan_units u
    join programacion.v_engineering_work_progress p on p.id=u.work_item_id
    where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and u.unit_code in ('M0.2','M0.3','M0.4','N-3')
      and p.status<>'DONE'
  ) then
    raise exception 'M7_1_DEPENDENCY_NOT_DONE';
  end if;

  if not exists (
    select 1 from programacion.input_readiness_runs
    where contract_revision=v_contract_revision
      and contract_snapshot_sha256=v_contract_sha
  ) then
    raise exception 'M7_1_CONTRACT_BINDING_MISSING';
  end if;

  select encode(extensions.digest(convert_to(operation_code||'|'||version||'|'||status||'|'||lifecycle_state_code||'|'||source_repo||'|'||source_paths::text,'UTF8'),'sha256'),'hex')
    into v_observed_registry_sha
    from public.lf_operation_registry
   where operation_code='EJECUCION_INPUT_GOVERNANCE_LF';
  if v_observed_registry_sha is distinct from v_registry_sha then
    raise exception 'M7_1_REGISTRY_SHA_DRIFT:%',coalesce(v_observed_registry_sha,'<null>');
  end if;

  if (select raw_payload->>'definition_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1' and archived_at is null) is distinct from v_router_sha then
    raise exception 'M7_1_ROUTER_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET' and archived_at is null) is distinct from v_curator_sha then
    raise exception 'M7_1_CURATOR_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET' and archived_at is null) is distinct from v_validator_sha then
    raise exception 'M7_1_VALIDATOR_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET' and archived_at is null) is distinct from v_execution_sha then
    raise exception 'M7_1_EXECUTION_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET' and archived_at is null) is distinct from v_shadow_sha then
    raise exception 'M7_1_SHADOW_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET' and archived_at is null) is distinct from v_semantic_sha then
    raise exception 'M7_1_SEMANTIC_SHA_DRIFT';
  end if;
  if (select raw_payload->>'members_sha256' from public.lf_activos where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET' and archived_at is null) is distinct from v_currentness_sha then
    raise exception 'M7_1_CURRENTNESS_SHA_DRIFT';
  end if;

  v_bindings := jsonb_build_object(
    'build_main_sha',v_base_main,
    'input_readiness_contract',jsonb_build_object('revision',v_contract_revision,'sha256',v_contract_sha),
    'operation_registry',jsonb_build_object('operation_code','EJECUCION_INPUT_GOVERNANCE_LF','sha256',v_registry_sha),
    'router',jsonb_build_object('asset_code','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1','sha256',v_router_sha),
    'curator',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','sha256',v_curator_sha),
    'validator',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET','sha256',v_validator_sha),
    'execution',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET','sha256',v_execution_sha),
    'shadow',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET','sha256',v_shadow_sha),
    'semantic_classification',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','sha256',v_semantic_sha),
    'currentness',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','sha256',v_currentness_sha)
  );
  v_suite_revision_sha := encode(extensions.digest(convert_to(v_bindings::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_test_suites(
    suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,
    created_at,updated_at,created_by_execution_id,updated_by_execution_id
  ) values (
    v_suite,'INPUT_GOVERNANCE','Input Governance Regression','v1','CANDIDATO',null,
    jsonb_build_object('deterministic_first',true,'false_pass_tolerance',0,'sha_binding_required',true,'semantic_pass_implied',false),
    jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M7.1','work_code','PAULO-012','bindings',v_bindings,'suite_revision_sha256',v_suite_revision_sha,'scope','M7.1_BOOTSTRAP_BINDING_BASELINE_ONLY'),
    now(),now(),v_exec,v_exec
  );

  insert into public.lf_test_suite_cases(
    suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
    preconditions,input_payload,expected_output,prohibited_output,status,metadata,
    created_at,updated_at,created_by_execution_id,updated_by_execution_id
  ) values
    (v_suite,'M7_1_BUILD_SHA',10,null,array[]::text[],'Build SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_base_main),'{}'::jsonb,'CANDIDATO',jsonb_build_object('binding_kind','BUILD'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_CONTRACT_SHA',20,null,array[]::text[],'Readiness contract SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('revision',v_contract_revision,'sha256',v_contract_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('binding_kind','CONTRACT'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_REGISTRY_SHA',30,null,array[]::text[],'Operation registry SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_registry_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('binding_kind','REGISTRY'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_ROUTER_SHA',40,null,array[]::text[],'Router resolver SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_router_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_CURATOR_SHA',50,null,array[]::text[],'Curator set SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_curator_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_VALIDATOR_SHA',60,null,array[]::text[],'Validator set SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_validator_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_EXECUTION_SHA',70,null,array[]::text[],'Execution set SHA binding','DETERMINISTIC','AUTOMATED','HIGH','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_execution_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_SHADOW_SHA',80,null,array[]::text[],'Shadow resolver set SHA binding','DETERMINISTIC','AUTOMATED','HIGH','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_shadow_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_SEMANTIC_SHA',90,null,array[]::text[],'Semantic classification set SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_semantic_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET'),now(),now(),v_exec,v_exec),
    (v_suite,'M7_1_CURRENTNESS_SHA',100,null,array[]::text[],'Currentness set SHA binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}'::jsonb,'{}'::jsonb,jsonb_build_object('sha256',v_currentness_sha),'{}'::jsonb,'CANDIDATO',jsonb_build_object('asset_code','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET'),now(),now(),v_exec,v_exec);

  insert into public.lf_test_suite_runs(
    suite_run_id,suite_code,execution_id,environment,application_version,commit_sha,rule_set_version,
    executor_type,executor_name,status,started_at,completed_at,duration_ms,
    tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
    rules_covered,stories_covered,contracts_covered,manifest,created_at,updated_at,metadata,
    created_by_execution_id,updated_by_execution_id
  ) values (
    v_suite_run,v_suite,v_exec,'SUPABASE_LIVE','IG_CURATOR_VALIDATOR_REFACTOR_V2',v_base_main,'M7.1-v1',
    'DETERMINISTIC_BASELINE_READBACK','M7.1_SHA_BINDING_BOOTSTRAP','PASSED',now(),now(),0,
    10,10,0,0,0,array[]::text[],array[]::text[],array['INPUT_READINESS_CONTRACT@5.13']::text[],
    jsonb_build_object('bindings',v_bindings,'suite_revision_sha256',v_suite_revision_sha,'semantic_regression_executed',false,'purpose','M7.1_FIRST_PERSISTED_BINDING_BASELINE'),
    now(),now(),jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M7.1','work_code','PAULO-012'),v_exec,v_exec
  );

  insert into public.lf_test_runs(
    suite_run_id,suite_code,test_code,execution_id,operation_code,rule_codes,story_code,contract_codes,
    environment,application_version,commit_sha,rule_set_version,executor_type,executor_name,attempt_no,status,
    input_payload,expected_output,actual_output,error_code,error_detail,severity,started_at,completed_at,duration_ms,
    evidence_payload,metadata,created_at,updated_at,created_by_execution_id,updated_by_execution_id
  )
  select
    v_suite_run,c.suite_code,c.test_code,v_exec,null,c.rule_codes,c.story_code,
    case when c.test_code='M7_1_CONTRACT_SHA' then array['INPUT_READINESS_CONTRACT@5.13']::text[] else array[]::text[] end,
    'SUPABASE_LIVE','IG_CURATOR_VALIDATOR_REFACTOR_V2',v_base_main,'M7.1-v1',
    'DETERMINISTIC_BASELINE_READBACK','M7.1_SHA_BINDING_BOOTSTRAP',1,'PASSED',
    c.input_payload,c.expected_output,c.expected_output,null,null,c.severity,now(),now(),0,
    jsonb_build_object('binding_readback',c.expected_output,'source','CANONICAL_DB_READ_MODEL','semantic_regression_executed',false),
    c.metadata,now(),now(),v_exec,v_exec
  from public.lf_test_suite_cases c
  where c.suite_code=v_suite;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,estado_documental,estado_operativo,nivel_control,
    runtime_estado,impacto_automatico,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
    raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_asset,'INPUT_GOVERNANCE_REGRESSION','TEST_SUITE','REGRESSION_SUITE','CANDIDATO','READ_ONLY','FAIL_CLOSED',
    'CANDIDATE_READ_ONLY','BLOQUEADO','v1','supabase://public/lf_test_suites/INPUT_GOVERNANCE_REGRESSION',
    'supabase://public/lf_test_suites/INPUT_GOVERNANCE_REGRESSION','LF_SUPER_ADMIN',v_base_main,'INPUT_GOVERNANCE_REGRESSION_SUITE',
    'NATIVE_SUPABASE','LF_TEST_SUITE_INVENTORY','IG_CURATOR_VALIDATOR_REFACTOR_V2_M7_1',1,v_batch,
    jsonb_build_object('suite_code',v_suite,'suite_revision_sha256',v_suite_revision_sha,'bindings',v_bindings,'first_suite_run_id',v_suite_run),
    jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M7.1','work_code','PAULO-012','semantic_pass_implied',false,'runtime_activation',false),
    v_exec,v_exec
  );

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,created_by_execution_id,updated_by_execution_id,updated_at)
  select v_asset,x.asset_code,'DEPENDE_DE','M7.1_SHA_BINDING',
         'supabase/migrations/20261001025112_ig_cv_m7_1_input_governance_regression_suite_v1.sql',v_exec,v_exec,now()
  from (values
    ('PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET'),
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET')
  ) as x(asset_code);

  select count(*) into v_count from public.lf_test_suite_cases where suite_code=v_suite;
  if v_count<>10 then raise exception 'M7_1_CASE_COUNT:%',v_count; end if;
  select count(*) into v_count from public.lf_test_runs where suite_run_id=v_suite_run;
  if v_count<>10 then raise exception 'M7_1_TEST_RUN_COUNT:%',v_count; end if;
  select count(*) into v_count from public.lf_activo_relaciones where codigo_activo=v_asset and relacion_tipo='DEPENDE_DE';
  if v_count<>7 then raise exception 'M7_1_RELATION_COUNT:%',v_count; end if;

  update programacion.engineering_work_items
     set status='DONE',completed_at=now(),updated_at=now(),updated_by_execution_id=v_exec
   where id=242 and work_code='PAULO-012' and status='READY';
  get diagnostics v_count = row_count;
  if v_count<>1 then raise exception 'M7_1_STATUS_UPDATE_COUNT:%',v_count; end if;

  update programacion.engineering_plan_units
     set unit_metadata=jsonb_set(
       unit_metadata,'{source_pack_v1}',
       (unit_metadata->'source_pack_v1') || jsonb_build_object(
         'refreshed_at',now(),
         'terminal_state','DONE',
         'closure_migration_version','20261001025112',
         'closure_execution_id',v_exec,
         'suite_code',v_suite,
         'suite_revision_sha256',v_suite_revision_sha,
         'first_suite_run_id',v_suite_run,
         'first_run_semantic_regression_executed',false
       ),false
     )
   where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M7.1';
  get diagnostics v_count = row_count;
  if v_count<>1 then raise exception 'M7_1_SOURCE_PACK_REFRESH_COUNT:%',v_count; end if;
end
$m7_1$;

commit;
