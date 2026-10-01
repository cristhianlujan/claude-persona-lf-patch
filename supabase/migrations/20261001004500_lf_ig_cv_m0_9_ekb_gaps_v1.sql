-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M0.9 (PAULO-104)
-- Register the two missing EKB gaps and require the already-existing R16 drift code.
-- EKB-only: no runtime, binding, promotion or production change.

begin;

do $m0_9$
declare
  v_run_reason constant text := 'IG-RUN-SUCCESSOR-REASON-NOT-PERSISTED-001';
  v_validator constant text := 'IG-VALIDATOR-MULTIPATH-CORRELATED-001';
  v_drift constant text := 'DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001';
begin
  if (select count(*) from public.lf_error_knowledge where codigo=v_drift and estado='ACTIVO') <> 1 then
    raise exception 'M0_9_REQUIRED_DRIFT_EKB_CODE_NOT_EXACTLY_ONE:%',v_drift;
  end if;

  if exists (select 1 from public.lf_error_knowledge where codigo in (v_run_reason,v_validator)) then
    raise exception 'M0_9_NEW_EKB_CODE_ALREADY_EXISTS';
  end if;

  insert into public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) values (
    'a1090001-2026-4000-8000-000000000104'::uuid,
    v_run_reason,
    'INPUT_GOVERNANCE',
    'El motivo de creación de un run successor no queda persistido en su lineage',
    'programacion.input_readiness_runs enlaza un run nuevo con supersedes_run_id, pero no persiste un motivo/estrategia tipada que explique por qué nació el successor. blocked_reason e invalidated_reason describen estado o invalidación y no sustituyen el motivo de creación del successor.',
    'El modelo de lineage registra la relación técnica entre runs pero no modela como dato obligatorio el reason/strategy de successor, rebind o recuration.',
    'Un run con supersedes_run_id puede quedar auditable respecto de su padre pero sin evidencia estructurada del motivo que justificó crear esa nueva ejecución.',
    'Todo successor debe persistir un motivo/strategy tipado junto con la referencia al run padre; M6.7 debe cerrar el lineage receipt y bloquear successors sin ese dato.',
    'Criterio de cierre: 0 successors gobernados sin motivo/strategy tipado y parent run/SHA trazable; verificar en la suite de receipts de M6.7.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
    'Schema live de programacion.input_readiness_runs: supersedes_run_id existe, sin columna successor_reason/strategy/motivo; runs 255-266 muestran cadena de sucesión. Plan #19195 M6 declara que el motivo de cada successor no se persiste y M6.7 lo exige.',
    now(),now(),'RUN_LINEAGE',array['INPUT_GOVERNANCE','CURATOR','VALIDATOR','AUDITOR'],
    'UNCLASSIFIED_WITH_REASON','SILENT',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2 M0.9 / M6 lineage gap',
    'supabase://programacion.input_readiness_runs|supabase://public.lf_eventos/19195'
  ),(
    'a1090002-2026-4000-8000-000000000104'::uuid,
    v_validator,
    'INPUT_GOVERNANCE',
    'Validator fragmentado en tres caminos altamente correlacionados con el Curator',
    'El Validator de Input Governance conserva tres caminos funcionales (validator_rebind_v1, validate_v2 y bootstrap_validate_v1) con alta dependencia compartida con Curator, reduciendo independencia real del juicio.',
    'La validación evolucionó por caminos acumulativos que reutilizan gran parte del mismo grafo y, en validate_v2, el mismo clasificador; el rebind no incorpora lógica de clasificación independiente.',
    'La existencia de múltiples caminos puede aparentar diversidad de validación aunque los conteos corregidos en programacion sean rebind 17/17 dependencias compartidas, validate_v2 29/31 y bootstrap_validate_v1 16/17.',
    'Consolidar un único entrypoint de Validator con fases explícitas y oráculos independientes; rebind debe ser estrategia del Validator, no un validator paralelo. No aceptar PASS basado únicamente en reproducibilidad del mismo clasificador.',
    'Criterio de cierre: un solo entrypoint activo de Validator y evidencia de oráculo/contradicción independiente; ninguna ruta de PASS debe depender sólo del mismo clasificador que Curator.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','#1274','ACTIVO',
    'Eventos #19381 y corrección #19388. Conteos programacion corregidos: validator_rebind_v1 17/17 compartidas, validate_v2 29/31, bootstrap_validate_v1 16/17; conclusiones de correlación sin cambio.',
    now(),now(),'VALIDATOR_ARCHITECTURE',array['INPUT_GOVERNANCE','VALIDATOR','CURATOR','AUDITOR'],
    'UNCLASSIFIED_WITH_REASON','PROCESS_DEPENDENT',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2 M0.9; evidence produced by M4.1 PAULO-100',
    'supabase://public.lf_eventos/19381|supabase://public.lf_eventos/19388|github://cristhianlujan/claude-persona-lf-patch/pull/1274'
  );

  if (select count(*) from public.lf_error_knowledge where codigo=v_run_reason and estado='ACTIVO') <> 1 then
    raise exception 'M0_9_RUN_REASON_EKB_POSTCONDITION_FAILED';
  end if;
  if (select count(*) from public.lf_error_knowledge where codigo=v_validator and estado='ACTIVO') <> 1 then
    raise exception 'M0_9_VALIDATOR_EKB_POSTCONDITION_FAILED';
  end if;
  if (select count(*) from public.lf_error_knowledge where codigo in (v_run_reason,v_validator,v_drift) and estado='ACTIVO') <> 3 then
    raise exception 'M0_9_THREE_REQUIRED_GAPS_NOT_AVAILABLE';
  end if;
end
$m0_9$;

commit;
