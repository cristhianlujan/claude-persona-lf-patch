-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M8.0 / PAULO-110
-- Governance-only persistence. No runtime function, trigger, timeout, cache, deploy or production mutation.
-- Canonical source artifact Git blob SHA-1: 959006be6136ec64975de99a24ead7974a50e7e6

begin;

do $m8_0_preflight$
declare
  v_dep_done integer;
  v_m7_complete integer;
  v_q_classes integer;
begin
  select count(*) into v_dep_done
  from programacion.engineering_plan_units u
  join programacion.engineering_work_items w on w.id=u.work_item_id
  where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and u.unit_code in ('T-PERF','M7.0','M7.3')
    and w.status='DONE';
  if v_dep_done <> 3 then
    raise exception 'M8_0_DEPENDENCIES_NOT_DONE:%',v_dep_done;
  end if;

  if (select count(*) from public.lf_capability_current
      where capability_code in ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK')
        and version='1.0.0') <> 2 then
    raise exception 'M8_0_T_PERF_CURRENTNESS_FAILED';
  end if;

  select count(*) into v_m7_complete
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and nullif(metadata->>'q_class','') is not null
    and nullif(metadata->>'dimension','') is not null
    and nullif(metadata->>'property','') is not null
    and nullif(metadata->>'oracle','') is not null
    and nullif(metadata->>'expected','') is not null
    and metadata ? 'evidence'
    and metadata->'evidence' is not null
    and metadata->'evidence'<>'null'::jsonb;
  if v_m7_complete <> 168 then
    raise exception 'M8_0_M7_METADATA_BASELINE_DRIFT:%',v_m7_complete;
  end if;

  select count(distinct metadata->>'q_class') into v_q_classes
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'q_class' between 'Q0' and 'Q8';
  if v_q_classes <> 9 then
    raise exception 'M8_0_Q0_Q8_NOT_COMPLETE:%',v_q_classes;
  end if;

  if exists (select 1 from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1' and archived_at is null) then
    raise exception 'M8_0_CONTRACT_ASSET_ALREADY_EXISTS';
  end if;
  if exists (select 1 from transversal.decision_log where adr='DEC-INPUT-GOV-PERFORMANCE-ASSURANCE-001') then
    raise exception 'M8_0_DECISION_ALREADY_EXISTS';
  end if;
  if exists (select 1 from public.lf_error_knowledge where codigo='IG-M8-PERFORMANCE-ASSURANCE-CONTRACT-001') then
    raise exception 'M8_0_EKB_ALREADY_EXISTS';
  end if;
end
$m8_0_preflight$;

do $m8_0_persist$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M8-0-20261004';
  v_batch uuid := gen_random_uuid();
  v_source_blob constant text := '959006be6136ec64975de99a24ead7974a50e7e6';
  v_source_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/ig_refactor/performance_contract_v1.json#blob=959006be6136ec64975de99a24ead7974a50e7e6';
begin
  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values (
    'DEC-INPUT-GOV-PERFORMANCE-ASSURANCE-001',
    'Contrato de performance de Input Governance preservando assurance',
    'M8.0 / PAULO-110 aprueba INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1. Toda optimizacion requiere performance mejor + p90 <=100s por cada pantalla afectada y agregado afectado + total <=120s por pantalla + assurance M7 aplicable equivalente o superior. Presupuesto: CONNECT 10s, READ 20s, CURATOR 30s, VALIDATOR 45s, ORCHESTRATION 15s; limite Edge 150s con margen 30s/20%. Validator es obligatorio. Q0-Q8 aplicables no pueden omitirse. BLOCKED/UNPROVEN no puede elevarse a PASS sin oracle autorizado. Cache stale/UNKNOWN falla cerrado. TIMEOUT_PHASE_BUDGET_POLICY y PERFORMANCE_EXACT_SOURCE_BENCHMARK T-PERF 1.0.0 son las autoridades unicas; NO_BLIND_TIMEOUT_EXTENSION. Esta decision no cambia runtime ni tuning.',
    'T-PERF registro p90 AS-IS 184.5244698s y 8 pantallas por encima de 150s; M7 tiene 168/168 casos con metadata completa Q0-Q8 y M7.3 91 negativos reconciliados. El contrato separa objetivo de performance de estado AS-IS y prohibe ganar velocidad reduciendo correctness/readiness.',
    'Governance-only. Autoriza el contrato y su consumo por optimizaciones M8.x posteriores, pero no ejecuta ninguna optimizacion, no cambia Edge/roles/session/statement timeouts, funciones, cache runtime, deploy ni produccion.',
    'vigente'
  );

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,linea_codigo,
    estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
    raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    'INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1',
    'INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1',
    'CONTRACT','GOVERNANCE','M8.0_PERFORMANCE_ASSURANCE_CONTRACT','JSON+MARKDOWN',null,
    'M8_0_APPROVED','VIGENTE','READ_ONLY','GOVERNED_CONTRACT','NO_RUNTIME_CHANGE','BLOQUEADO',
    'REGISTER_GOVERNED_CONTRACT','1.0.0','docs/ig_refactor/performance_contract_v1.json',null,'SUPER_ADMIN',v_source_blob,
    'PERFORMANCE_QUALITY_GUARD',
    'GIT:IG_CURATOR_VALIDATOR_REFACTOR_V2','IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.0',1,v_batch,
    jsonb_build_object(
      'status','APPROVED_CONTRACT_ONLY',
      'source_ref',v_source_ref,
      'runtime_change',false,
      'timeout_tuning',false,
      'production_authorized',false,
      'edge_limit_ms',150000,
      'total_screen_budget_ms',120000,
      'p90_target_ms',100000,
      'edge_margin_ms',30000,
      'no_blind_timeout_extension',true
    ),
    jsonb_build_object(
      'schema_version','LF_IG_PERFORMANCE_ASSURANCE_CONTRACT_V1',
      'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M8.0',
      'work_code','PAULO-110',
      'owner','SUPER_ADMIN',
      'authorities',jsonb_build_array('TIMEOUT_PHASE_BUDGET_POLICY@1.0.0','PERFORMANCE_EXACT_SOURCE_BENCHMARK@1.0.0','M7.0/Q_TAXONOMY_V1','M7.3/INPUT_GOVERNANCE_REGRESSION'),
      'phase_budgets_ms',jsonb_build_object('CONNECT',10000,'READ',20000,'CURATOR',30000,'VALIDATOR',45000,'ORCHESTRATION',15000),
      'quality_baseline',jsonb_build_object('suite_cases',168,'m7_3_negative_cases',91,'q_classes',jsonb_build_array('Q0','Q1','Q2','Q3','Q4','Q5','Q6','Q7','Q8')),
      'current_as_is',jsonb_build_object('p90_s',184.5244698,'screens_p90_over_150',8,'contract_target_met',false),
      'owner_approval','CHAT16_SCOPE_AND_M8_0_MERGE_AUTHORIZED'
    ),
    v_execution_id,v_execution_id
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,
    created_by_execution_id,updated_by_execution_id
  ) values
    ('INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1','TIMEOUT_PHASE_BUDGET_POLICY','DEPENDE_DE','T-PERF@1.0.0',v_source_ref,v_batch,v_execution_id,v_execution_id),
    ('INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1','PERFORMANCE_EXACT_SOURCE_BENCHMARK','DEPENDE_DE','T-PERF@1.0.0',v_source_ref,v_batch,v_execution_id,v_execution_id);

  insert into public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) values (
    gen_random_uuid(),
    'IG-M8-PERFORMANCE-ASSURANCE-CONTRACT-001',
    'INPUT_GOVERNANCE',
    'Performance de IG no puede aprobarse degradando assurance',
    'M8.0 congela un contrato unico: mejora de performance solo es valida con p90 y presupuesto cumplidos y con evidencia M7/Validator/currentness equivalente o superior. El promedio no compensa una cola critica ni un FAIL de assurance.',
    'La optimizacion aislada de tiempo puede crear falsos verdes si omite Validator, reutiliza cache stale, sube timeout sin RCA o mide promedio mientras empeora p90.',
    'Performance y assurance deben evaluarse conjuntamente sobre source/cohort exactos; T-PERF mide/presupuesta y M7 decide calidad. Ninguna de las dos dimensiones puede elevar por si sola la otra.',
    'Reusar TIMEOUT_PHASE_BUDGET_POLICY y PERFORMANCE_EXACT_SOURCE_BENCHMARK; exigir Validator y Q0-Q8 aplicables; total <=120s, p90 <=100s, Edge margin 30s; cache stale/UNKNOWN FAIL; NO_BLIND_TIMEOUT_EXTENSION.',
    'Negativos obligatorios: omitir Validator FAIL; timeout sin diagnostico FAIL; cache stale FAIL; promedio mejor/p90 peor FAIL; performance PASS con assurance FAIL => FAIL. Readback: asset/decision/2 relaciones, 5/5 checkpoints DONE y work PAULO-110 DONE.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
    'M8.0 / PAULO-110; T-PERF current 1.0.0; M7 live 168/168 metadata completa Q0-Q8; M7.3 91/91 negativos reconciliados; AS-IS p90 184.5244698s y 8 pantallas >150s. Source blob 959006be6136ec64975de99a24ead7974a50e7e6.',
    now(),now(),'PERFORMANCE_GOVERNANCE',array['INPUT_GOVERNANCE','CURATOR','VALIDATOR','AUDITOR'],
    'UNCLASSIFIED_WITH_REASON','LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2 M8.0 / PAULO-110',v_source_ref
  );

  update public.lf_error_knowledge
  set evidencia=coalesce(evidencia,'') || E'\n[M8_0_20261004_SCHEMA_FIRST_RECURRENCE] Initial checkpoint read attempted nonexistent engineering_work_checkpoints.metadata and returned SQLSTATE 42703. Execution stopped that query, introspected information_schema, then used only verified columns. No mutation had occurred before recovery.',
      ultima_vez=now(),updated_at=now()
  where codigo='DB-001';

  update programacion.engineering_work_checkpoints c
  set status='DONE',
      evidence_ref=case c.checkpoint_code
        when 'PERF_FACTS_ASIS' then 'supabase://programacion.input_readiness_runs#M8.0-ASIS-p90=184.5244698s;8-screens-over-150s'
        when 'POLICY_REUSE_CHECK' then 'supabase://public.lf_capability_current/TIMEOUT_PHASE_BUDGET_POLICY@1.0.0|PERFORMANCE_EXACT_SOURCE_BENCHMARK@1.0.0'
        when 'QUALITY_INVARIANTS' then 'supabase://public.lf_test_suite_cases/INPUT_GOVERNANCE_REGRESSION#168-of-168-Q0-Q8|github://docs/ig_refactor/performance_contract_v1.json#blob=959006be6136ec64975de99a24ead7974a50e7e6'
        when 'BUDGET_TABLE' then 'github://docs/ig_refactor/performance_contract_v1.json#blob=959006be6136ec64975de99a24ead7974a50e7e6#budget-120000-p90-100000-edge-150000'
        when 'APPROVAL_READBACK' then 'supabase://transversal.decision_log/DEC-INPUT-GOV-PERFORMANCE-ASSURANCE-001'
      end,
      completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  from programacion.engineering_work_items w
  where c.work_item_id=w.id and w.work_code='PAULO-110';

  update programacion.engineering_plan_units u
  set unit_metadata=jsonb_set(
        coalesce(u.unit_metadata,'{}'::jsonb),'{m8_0_terminal}',
        jsonb_build_object(
          'status','DONE',
          'contract_code','INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1',
          'decision','DEC-INPUT-GOV-PERFORMANCE-ASSURANCE-001',
          'source_blob_sha1',v_source_blob,
          'edge_limit_ms',150000,
          'total_screen_budget_ms',120000,
          'p90_target_ms',100000,
          'm7_cases',168,
          'm7_3_negatives',91,
          't_perf_versions',jsonb_build_object('TIMEOUT_PHASE_BUDGET_POLICY','1.0.0','PERFORMANCE_EXACT_SOURCE_BENCHMARK','1.0.0'),
          'runtime_changed',false,
          'timeout_tuning_changed',false,
          'production_changed',false,
          'closed_at',clock_timestamp()
        ),true
      )
  from programacion.engineering_work_items w
  where u.work_item_id=w.id and u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code='M8.0' and w.work_code='PAULO-110';

  update programacion.engineering_work_items
  set status='DONE',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  where work_code='PAULO-110';
end
$m8_0_persist$;

do $m8_0_readback$
declare
  v_done_checkpoints integer;
  v_m7_complete integer;
begin
  if (select count(*) from transversal.decision_log where adr='DEC-INPUT-GOV-PERFORMANCE-ASSURANCE-001' and estado='vigente') <> 1 then
    raise exception 'M8_0_DECISION_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1' and estado_documental='VIGENTE' and estado_operativo='READ_ONLY' and runtime_estado='NO_RUNTIME_CHANGE' and ultima_revision='959006be6136ec64975de99a24ead7974a50e7e6' and archived_at is null) <> 1 then
    raise exception 'M8_0_ASSET_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_activo_relaciones where codigo_activo='INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1' and relacionado_codigo in ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK') and relacion_tipo='DEPENDE_DE') <> 2 then
    raise exception 'M8_0_T_PERF_RELATIONS_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_error_knowledge where codigo='IG-M8-PERFORMANCE-ASSURANCE-CONTRACT-001' and estado='ACTIVO') <> 1 then
    raise exception 'M8_0_EKB_POST_FAILED';
  end if;

  select count(*) into v_done_checkpoints
  from programacion.engineering_work_checkpoints c
  join programacion.engineering_work_items w on w.id=c.work_item_id
  where w.work_code='PAULO-110' and c.required and c.status='DONE' and nullif(c.evidence_ref,'') is not null;
  if v_done_checkpoints <> 5 then
    raise exception 'M8_0_CHECKPOINT_READBACK_FAILED:%',v_done_checkpoints;
  end if;

  if not exists (select 1 from programacion.engineering_work_items where work_code='PAULO-110' and status='DONE' and completed_at is not null) then
    raise exception 'M8_0_WORK_ITEM_NOT_DONE';
  end if;

  select count(*) into v_m7_complete
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and nullif(metadata->>'q_class','') is not null
    and nullif(metadata->>'dimension','') is not null
    and nullif(metadata->>'property','') is not null
    and nullif(metadata->>'oracle','') is not null
    and nullif(metadata->>'expected','') is not null
    and metadata ? 'evidence' and metadata->'evidence' is not null and metadata->'evidence'<>'null'::jsonb;
  if v_m7_complete <> 168 then
    raise exception 'M8_0_M7_POST_WRITE_DRIFT:%',v_m7_complete;
  end if;

  if (select count(*) from public.lf_capability_current where capability_code in ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK') and version='1.0.0') <> 2 then
    raise exception 'M8_0_T_PERF_POST_WRITE_DRIFT';
  end if;
end
$m8_0_readback$;

commit;
