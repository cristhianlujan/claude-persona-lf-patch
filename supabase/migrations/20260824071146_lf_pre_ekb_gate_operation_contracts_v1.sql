WITH target_operations(operation_code, asset_code, asset_name) AS (
  VALUES
    ('ORQUESTACION_PIPELINE_LF','ACT-0058','SKILL_ORQUESTADOR_PIPELINE_LF'),
    ('EXTRACCION_FUENTES_DIGITALES_LF','ACT-0052','SKILL_EXTRACCION_FUENTES_DIGITALES_LF'),
    ('HOMOLOGACION_FUENTES_DIGITALES_LF','ACT-0053','SKILL_HOMOLOGACION_FUENTES_DIGITALES_LF'),
    ('EXTRACCION_NOTICIAS_FINANCIERAS_LF','ACT-0054','SKILL_EXTRACCION_NOTICIAS_FINANCIERAS_LF'),
    ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF','ACT-0055','SKILL_EXTRACCION_DOCUMENTOS_REGULATORIOS_LF'),
    ('ANALISIS_RIESGO_CONTENIDO_LF','ACT-0056','SKILL_ANALISIS_RIESGO_CONTENIDO_LF'),
    ('ESCRITURA_BASE_CONOCIMIENTO_LF','ACT-0057','SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF')
), active_ekb AS (
  SELECT codigo, descripcion, prevencion
  FROM public.lf_error_knowledge
  WHERE estado = 'activo'
    AND codigo IN ('GOV-010','DB-001','DB-EVT-001','CI-MIG-001','CI-E16-001','OPS-002','KB-PROD-001')
)
INSERT INTO public.lf_operation_contracts (
  operation_code, contract_code, contract_path, contract_sha,
  required_before_write, allowed, blocked, required_after_write,
  status, created_by_execution_id, updated_by_execution_id
)
SELECT
  t.operation_code,
  'CONTRACT-PRE-EKB-GATE-LF-v0.1',
  'supabase://public.lf_operation_step_contracts/PRE_EKB_GATE',
  'pending-git-pr',
  jsonb_build_object(
    'pre_ekb_gate_required', true,
    'must_read_before_any_mutation', true,
    'minimum_error_codes', (SELECT jsonb_agg(codigo ORDER BY codigo) FROM active_ekb),
    'task_signature_required', ARRAY['operation_code','asset_code','domain','tables','execution_mode'],
    'evidence_required', ARRAY['ekb_readback','applicable_rules','controls_derived','non_applicable_reason_if_any']
  ),
  jsonb_build_object(
    'may_continue_when', ARRAY['ekb_readback_done','applicable_rules_mapped_to_controls','no_unhandled_high_critical_rule']
  ),
  jsonb_build_object(
    'blocked_when', ARRAY['ekb_not_read','active_applicable_rule_without_control','schema_assumed_without_catalog_read','event_contract_not_verified']
  ),
  jsonb_build_object(
    'required_close_evidence', ARRAY['pre_ekb_gate_result','rules_applied','rules_blocked','event_id_or_batch_partial']
  ),
  'ACTIVE_ENFORCEMENT',
  'CHATGPT_GOV_PRE_EKB_GATE_20260824',
  'CHATGPT_GOV_PRE_EKB_GATE_20260824'
FROM target_operations t
ON CONFLICT (operation_code, contract_code) DO UPDATE SET
  contract_path = EXCLUDED.contract_path,
  contract_sha = EXCLUDED.contract_sha,
  required_before_write = EXCLUDED.required_before_write,
  allowed = EXCLUDED.allowed,
  blocked = EXCLUDED.blocked,
  required_after_write = EXCLUDED.required_after_write,
  status = EXCLUDED.status,
  updated_at = now(),
  updated_by_execution_id = EXCLUDED.updated_by_execution_id;

WITH target_operations(operation_code, asset_code, asset_name) AS (
  VALUES
    ('ORQUESTACION_PIPELINE_LF','ACT-0058','SKILL_ORQUESTADOR_PIPELINE_LF'),
    ('EXTRACCION_FUENTES_DIGITALES_LF','ACT-0052','SKILL_EXTRACCION_FUENTES_DIGITALES_LF'),
    ('HOMOLOGACION_FUENTES_DIGITALES_LF','ACT-0053','SKILL_HOMOLOGACION_FUENTES_DIGITALES_LF'),
    ('EXTRACCION_NOTICIAS_FINANCIERAS_LF','ACT-0054','SKILL_EXTRACCION_NOTICIAS_FINANCIERAS_LF'),
    ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF','ACT-0055','SKILL_EXTRACCION_DOCUMENTOS_REGULATORIOS_LF'),
    ('ANALISIS_RIESGO_CONTENIDO_LF','ACT-0056','SKILL_ANALISIS_RIESGO_CONTENIDO_LF'),
    ('ESCRITURA_BASE_CONOCIMIENTO_LF','ACT-0057','SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF')
)
INSERT INTO public.lf_operation_step_contracts (
  operation_code, step_id, step_order, execution_order, contract_code,
  purpose, input_required, resolver_ref, output_payload, pass_condition,
  block_condition, blocking_code, mini_judge_code, required_evidence_keys,
  next_if_pass, next_if_blocked, status, notes, execution_sql,
  fail_condition, created_by_execution_id, updated_by_execution_id
)
SELECT
  t.operation_code,
  'PRE_EKB_GATE',
  -10,
  -10,
  'CONTRACT-PRE-EKB-GATE-LF-v0.1',
  'Leer EKB activa antes de cualquier ejecución, captura, análisis, escritura, corrección o cierre; convertir reglas aplicables en controles de preflight y bloquear si una regla High/Critical aplicable no tiene control asociado.',
  jsonb_build_array('operation_code','asset_code','task_signature','execution_mode','affected_tables'),
  'public.lf_error_knowledge + public.v_lf_fuente_operativa',
  jsonb_build_object(
    'ekb_readback_required', true,
    'applicable_rules_required', true,
    'controls_derived_required', true,
    'event_or_batch_partial_required', true
  ),
  jsonb_build_array('ekb_read=true','applicable_rules_mapped=true','unhandled_high_critical_rules=0'),
  jsonb_build_array('EKB_NOT_READ','APPLICABLE_EKB_RULE_WITHOUT_CONTROL','SCHEMA_ASSUMED_WITHOUT_CATALOG_READ','EVENT_CONTRACT_NOT_VERIFIED'),
  'PRE_EKB_GATE_BLOCKED',
  'MINI_JUDGE_PRE_EKB_GATE_LF_V0_1',
  jsonb_build_array('ekb_query','active_rules_considered','controls_applied','non_applicable_rules','blocking_codes'),
  'NEXT_LOWEST_STEP_ORDER',
  'STOP_AND_REGISTER_BLOCKED_OR_BATCH_PARTIAL',
  'ACTIVO',
  'Mitiga GOV-010: la EKB deja de ser memoria posterior y pasa a precondición contractual obligatoria antes de ejecutar. No reemplaza Router ACT-0001; ocurre después de identificar la operación y antes de cualquier mutación.',
  'SELECT codigo, descripcion, prevencion FROM public.lf_error_knowledge WHERE estado = ''activo'' AND (codigo IN (''GOV-010'',''DB-001'',''DB-EVT-001'',''CI-MIG-001'',''CI-E16-001'',''OPS-002'',''KB-PROD-001'') OR descripcion ILIKE ''%'' || $1 || ''%'' OR prevencion ILIKE ''%'' || $1 || ''%'') ORDER BY ultima_vez DESC;',
  jsonb_build_array('ekb_query_failed','no_controls_for_applicable_rule','critical_rule_unhandled'),
  'CHATGPT_GOV_PRE_EKB_GATE_20260824',
  'CHATGPT_GOV_PRE_EKB_GATE_20260824'
FROM target_operations t
ON CONFLICT (operation_code, step_id) DO UPDATE SET
  step_order = EXCLUDED.step_order,
  execution_order = EXCLUDED.execution_order,
  contract_code = EXCLUDED.contract_code,
  purpose = EXCLUDED.purpose,
  input_required = EXCLUDED.input_required,
  resolver_ref = EXCLUDED.resolver_ref,
  output_payload = EXCLUDED.output_payload,
  pass_condition = EXCLUDED.pass_condition,
  block_condition = EXCLUDED.block_condition,
  blocking_code = EXCLUDED.blocking_code,
  mini_judge_code = EXCLUDED.mini_judge_code,
  required_evidence_keys = EXCLUDED.required_evidence_keys,
  next_if_pass = EXCLUDED.next_if_pass,
  next_if_blocked = EXCLUDED.next_if_blocked,
  status = EXCLUDED.status,
  notes = EXCLUDED.notes,
  execution_sql = EXCLUDED.execution_sql,
  fail_condition = EXCLUDED.fail_condition,
  updated_at = now(),
  updated_by_execution_id = EXCLUDED.updated_by_execution_id;

UPDATE public.lf_error_knowledge
SET evidencia = concat_ws(E'\n\n', evidencia, '2026-08-24 PRE_EKB_GATE agregado como contrato obligatorio en lf_operation_step_contracts para ACT-0052..ACT-0058. Verificar step_id=PRE_EKB_GATE con step_order=-10 antes de ejecutar.'),
    updated_at = now()
WHERE codigo = 'GOV-010';

INSERT INTO public.lf_eventos (
  evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen, created_by_execution_id
)
VALUES (
  'REMEDIACION_GOBERNANZA',
  'OPERATION_CONTRACTS',
  'PRE_EKB_GATE_ACT_0052_0058',
  'PRE_EKB_GATE agregado a contratos operativos ACT-0052..ACT-0058 para leer EKB antes de ejecución y reducir recurrencia de errores.',
  'INFO',
  jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id','CHATGPT_GOV_PRE_EKB_GATE_20260824',
    'producer','ChatGPT',
    'purpose','Mitigar GOV-010 incorporando lectura EKB como precondición contractual',
    'occurred_at', now(),
    'acceptance_declared', false,
    'operation_codes', jsonb_build_array(
      'ORQUESTACION_PIPELINE_LF',
      'EXTRACCION_FUENTES_DIGITALES_LF',
      'HOMOLOGACION_FUENTES_DIGITALES_LF',
      'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
      'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
      'ANALISIS_RIESGO_CONTENIDO_LF',
      'ESCRITURA_BASE_CONOCIMIENTO_LF'
    )
  ),
  'CHATGPT_GOV_PRE_EKB_GATE_20260824',
  'CHATGPT_GOV_PRE_EKB_GATE_20260824'
);