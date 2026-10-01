-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · R16
-- Git-first database governance + EKB codification of D-V2.3.
-- Append-only plan amendment; no promotion/runtime activation.

begin;

do $r16$
declare
  v_exec constant text := 'CHATGPT-IG-CV-R16-GIT-FIRST-20260930';
  v_error_id constant uuid := '2e829384-b55d-4d12-8b69-16dba51f6001'::uuid;
  v_rule_id constant uuid := '0e1fcf7e-203a-4bb2-b2ce-16dba51f6002'::uuid;
begin
  if exists(
    select 1 from public.lf_eventos
    where entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2_R16'
  ) then
    raise exception 'R16_PLAN_RULE_ALREADY_REGISTERED';
  end if;

  if exists(
    select 1 from public.lf_error_knowledge
    where codigo='DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001'
  ) then
    raise exception 'R16_EKB_ERROR_ALREADY_REGISTERED';
  end if;

  if exists(
    select 1 from public.lf_prevention_rules
    where regla_codigo='PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001'
  ) then
    raise exception 'R16_EKB_RULE_ALREADY_REGISTERED';
  end if;

  insert into public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) values (
    v_error_id,
    'DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001',
    'DATABASE_GOVERNANCE',
    'Objeto persistente de BD creado o modificado fuera de una migración versionada en Git',
    'Un objeto persistente puede existir live sin fuente versionada, review ni ledger reproducible, rompiendo Git=runtime y contaminando inventarios, grafos y readbacks dependientes.',
    'Cambio persistente ejecutado directamente contra la BD sin materializar primero una migración revisable en Git.',
    'CREATE/ALTER/REPLACE/seed persistente live sin migration source equivalente en el repositorio; el drift puede descubrirse después por parity/readback.',
    'Aplicar R16: bloquear el trabajo dependiente, clasificar el objeto como DRIFT y reconciliarlo mediante PR/change-set propio; luego merge, apply/ledger y readback Git=ledger=BD antes de continuar.',
    'La reconciliación exige migration source en Git, head aprobado, ledger exacto y readback del objeto/datos afectados. Pruebas transitorias con ROLLBACK no cuentan como cambios persistentes.',
    'HIGH',
    2,
    '2026-09-30 20:53:26+00'::timestamptz,
    now(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    '#1314,#1315',
    'ACTIVO',
    'Incidentes programacion.input_source_inventory_l1 e inventory.*; decisión #19529; reconciliación #1314/#1315.',
    now(),
    now(),
    'DATABASE_CHANGE_GOVERNANCE',
    array['Architect','Builder','DevOps','Auditor','Super Admin']::text[],
    'R5_EROSION_PROCESO',
    'LOUD_LATE',
    'IG refactor L1 drift incidents and Git-first remediation',
    'supabase://public.lf_eventos/19529|github://cristhianlujan/claude-persona-lf-patch/pull/1314|github://cristhianlujan/claude-persona-lf-patch/pull/1315'
  );

  insert into public.lf_prevention_rules(
    id,regla_codigo,error_codigo,regla,justificacion,prioridad,activa,created_at,
    categoria,lifecycle_phase,consumer_role
  ) values (
    v_rule_id,
    'PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001',
    'DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001',
    'R16 — Ningún objeto persistente de base de datos se crea o modifica como cambio canónico sin migración versionada en Git. Si aparece live sin respaldo Git, clasificarlo como DRIFT, bloquear el trabajo dependiente y reconciliarlo en un PR/change-set propio antes de continuar. Secuencia obligatoria: Git migration -> review/merge -> apply/ledger -> readback Git=ledger=BD. Excepción única: pruebas transitorias o acotadas por ROLLBACK que no persisten cambios.',
    'Evita runtime/schema/data que no puedan reproducirse ni auditarse y previene que inventarios, grafos o pruebas congelen estado fuera del control de versiones.',
    1,
    true,
    now(),
    'DATABASE_GOVERNANCE',
    'PRE_WRITE_CHANGE_GOVERNANCE',
    array['Architect','Builder','DevOps','Auditor','Super Admin']::text[]
  );

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) values (
    'DECISION_ESTRATEGICA',
    'PROGRAM_PLAN',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_R16',
    'R16 agregada al plan v2: todo cambio persistente de base de datos es Git-first; objeto live sin migración Git se considera drift, bloquea trabajo dependiente y exige reconciliación por PR propio antes de continuar.',
    'INFO',
    jsonb_build_object(
      'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'plan_version',2,
      'purpose','Codificar D-V2.3 como R16 del plan v2 y enlazar la prevención EKB Git-first.',
      'rule_code','R16',
      'extends_plan_event_id',19275,
      'codifies_decision_event_id',19529,
      'rule_title','Git-first database changes; drift blocks dependent work',
      'rule','Ningún objeto persistente de base de datos se crea o modifica como cambio canónico sin migración versionada en Git. Si ocurre live sin Git, se clasifica DRIFT y se reconcilia mediante PR/change-set propio antes de continuar.',
      'mandatory_sequence',jsonb_build_array(
        'MIGRATION_IN_GIT',
        'REVIEW_AND_MERGE',
        'APPLY_AND_LEDGER',
        'READBACK_GIT_EQUALS_LEDGER_EQUALS_DB'
      ),
      'dependent_work_behavior','BLOCK_AND_RECONCILE',
      'exception','TRANSIENT_OR_ROLLBACK_SCOPED_NONPERSISTENT_TESTS_ONLY',
      'ekb_error_code','DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001',
      'ekb_prevention_rule_code','PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001',
      'producer','chatgpt (sesion owner)',
      'directed_by','PAULO',
      'directed_by_role','Owner del plan',
      'occurred_at',now(),
      'execution_id',v_exec,
      'acceptance_declared',false,
      'promotion_authorized',false,
      'production_authorized',false,
      'evidence_schema_version','operational-event/v2'
    ),
    'CHATGPT:IG_CV_R16_GIT_FIRST',
    v_exec
  );

  if (select count(*) from public.lf_error_knowledge where id=v_error_id)<>1
     or (select count(*) from public.lf_prevention_rules where id=v_rule_id and activa)<>1
     or (select count(*) from public.lf_eventos where entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2_R16')<>1
  then
    raise exception 'R16_POSTCHECK_FAILED';
  end if;
end
$r16$;

commit;
