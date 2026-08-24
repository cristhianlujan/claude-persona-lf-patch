-- LF KB production hardening v5 — 2026-08-24
-- Corrige v1-v4: evento operacional completo y EKB con enums permitidos.

CREATE OR REPLACE FUNCTION public.fn_auto_consumer_ready()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_gate_ok boolean := false;
BEGIN
  IF NEW.decision_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.lf_content_decisions d
      WHERE d.decision_id = NEW.decision_id
        AND d.decision = 'ALLOW_PROD_GATE'
        AND d.consumer_gate_passed IS TRUE
        AND COALESCE(d.hitl_required, FALSE) IS FALSE
        AND d.grounding_status = 'GROUNDED'
    ) INTO v_gate_ok;
  END IF;

  IF NEW.quality_score >= 0.70
     AND NEW.grounding_status = 'GROUNDED'
     AND NEW.kb_enriched IS NOT NULL
     AND NEW.kb_enriched <> '{}'::jsonb
     AND NEW.decision_upstream = 'ALLOW_PROD_GATE'
     AND v_gate_ok
  THEN
    NEW.consumer_ready := TRUE;
    NEW.reviewed_by := COALESCE(NEW.reviewed_by, 'AUTO_QUALITY_GATE');
    NEW.reviewed_at := COALESCE(NEW.reviewed_at, NOW());
  ELSE
    NEW.consumer_ready := FALSE;
    IF NEW.reviewed_by = 'AUTO_QUALITY_GATE' THEN
      NEW.reviewed_by := NULL;
      NEW.reviewed_at := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

WITH normalized_decisions AS (
  UPDATE public.lf_content_decisions
  SET decision = 'ALLOW_PROD_GATE',
      updated_at = NOW()
  WHERE decision IN ('ALLOW', 'APROBAR', 'APROBADO', 'INCLUIR')
    AND consumer_gate_passed IS TRUE
    AND COALESCE(hitl_required, FALSE) IS FALSE
    AND grounding_status = 'GROUNDED'
  RETURNING decision_id
), synced_grounding AS (
  UPDATE public.lf_knowledge_base kb
  SET grounding_status = d.grounding_status,
      updated_at = NOW()
  FROM public.lf_content_decisions d
  WHERE kb.decision_id = d.decision_id
    AND kb.grounding_status IS DISTINCT FROM d.grounding_status
    AND d.grounding_status = 'GROUNDED'
  RETURNING kb.kb_id
), recalculated_kb AS (
  UPDATE public.lf_knowledge_base
  SET updated_at = NOW()
  RETURNING kb_id, consumer_ready
), ekb_update AS (
  UPDATE public.lf_error_knowledge
  SET frecuencia = COALESCE(frecuencia, 0) + 1,
      ultima_vez = NOW(),
      updated_at = NOW(),
      estado = 'activo',
      evidencia = 'Hardening aplicado: fn_auto_consumer_ready exige decision_id, decision=ALLOW_PROD_GATE, consumer_gate_passed=true, hitl_required=false, grounding=GROUNDED y decision_upstream=ALLOW_PROD_GATE.'
  WHERE codigo = 'KB-PROD-001'
  RETURNING id
), ekb_insert AS (
  INSERT INTO public.lf_error_knowledge (
    id, codigo, categoria, titulo, descripcion, causa_raiz, patron,
    prevencion, validacion, severidad, frecuencia, primera_vez, ultima_vez,
    lote_origen, pr, estado, evidencia, created_at, updated_at,
    lifecycle_phase, root_cause_family, detectability, source_context, source_ref
  )
  SELECT gen_random_uuid(), 'KB-PROD-001', 'Governance/KB',
         'consumer_ready podía activarse sin gate upstream completo',
         'El trigger anterior promovía consumer_ready con score, grounding y kb_enriched, pero no exigía decision_id, decision canónica ni consumer_gate_passed=true.',
         'Gate físico incompleto en fn_auto_consumer_ready.',
         'Registros KB con consumer_ready=true podían quedar sin decisión persistida o con gate upstream no aprobado.',
         'Antes de promover KB a consumo, validar cadena capture -> decision -> gate -> KB y recalcular consumer_ready con trigger endurecido.',
         'Readback debe mostrar 0 registros consumer_ready=true sin decision_id, sin decision=ALLOW_PROD_GATE, sin consumer_gate_passed=true o sin grounding GROUNDED.',
         'High', 1, NOW(), NOW(), 'SESSION_55_KB_PROD_HARDENING', NULL, 'activo',
         'Migración session_55_kb_production_hardening_v5 aplicada.', NOW(), NOW(),
         'production_hardening', 'UNCLASSIFIED_WITH_REASON', 'LOUD_EARLY', 'LF KB production readiness', 'ACT-0057/ACT-0058'
  WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'KB-PROD-001')
  RETURNING id
), evt_error_update AS (
  UPDATE public.lf_error_knowledge
  SET frecuencia = COALESCE(frecuencia, 0) + 1,
      ultima_vez = NOW(),
      updated_at = NOW(),
      estado = 'activo',
      evidencia = 'Intentos v1-v4 bloqueados por contrato de eventos y enums EKB; v5 usa operational-event/v2 completo y enums permitidos.'
  WHERE codigo = 'DB-EVT-001'
  RETURNING id
), evt_error_insert AS (
  INSERT INTO public.lf_error_knowledge (
    id, codigo, categoria, titulo, descripcion, causa_raiz, patron,
    prevencion, validacion, severidad, frecuencia, primera_vez, ultima_vez,
    lote_origen, pr, estado, evidencia, created_at, updated_at,
    lifecycle_phase, root_cause_family, detectability, source_context, source_ref
  )
  SELECT gen_random_uuid(), 'DB-EVT-001', 'Governance/EventContract',
         'Evento operativo rechazado por contrato de evidencia',
         'Intentos de cierre fallaron porque lf_eventos exige evento_tipo registrado, evidence_schema_version permitido y envelope operacional completo; además EKB usa enums cerrados.',
         'No se validó evento_tipo, evidence_schema_version, campos operational-event/v2 y enums EKB antes de insertar.',
         'DML de cierre falla si el contrato de evento o constraints EKB son default-deny.',
         'Antes de insertar en lf_eventos o EKB, consultar contratos y constraints; usar evidence_schema_version y enums detectability/root_cause_family permitidos.',
         'Readback de evento debe devolver fila y no error de contrato ni constraint.',
         'Medium', 1, NOW(), NOW(), 'SESSION_55_KB_PROD_HARDENING', NULL, 'activo',
         'v1-v4 bloqueados; v5 corrige contrato de evento y enums EKB.', NOW(), NOW(),
         'production_hardening', 'UNCLASSIFIED_WITH_REASON', 'LOUD_EARLY', 'LF event contract and EKB enum', 'lf_eventos/lf_error_knowledge'
  WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'DB-EVT-001')
  RETURNING id
), pr_insert AS (
  INSERT INTO public.lf_prevention_rules (
    id, regla_codigo, error_codigo, regla, justificacion, prioridad, activa, created_at,
    categoria, lifecycle_phase, consumer_role
  )
  SELECT gen_random_uuid(), 'KB-PROD-R001', 'KB-PROD-001',
         'Ningún registro de lf_knowledge_base puede quedar consumer_ready=true si no tiene decision_id, decision=ALLOW_PROD_GATE, consumer_gate_passed=true, hitl_required=false, grounding_status=GROUNDED y decision_upstream=ALLOW_PROD_GATE.',
         'Evita publicar conocimiento sin trazabilidad completa capture-decision-gate-KB.',
         1, TRUE, NOW(), 'Governance/KB', 'production_hardening', ARRAY['governance','auditor','operator']::text[]
  WHERE NOT EXISTS (SELECT 1 FROM public.lf_prevention_rules WHERE regla_codigo = 'KB-PROD-R001')
  RETURNING id
)
INSERT INTO public.lf_eventos (
  evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, payload, origen, created_by_execution_id
)
SELECT 'REMEDIACION_GOBERNANZA', 'PIPELINE_KB', 'ACT-0057_ACT-0058',
       'Hardening producción KB aplicado: trigger consumer_ready endurecido, decisiones aprobatorias legadas normalizadas, grounding sincronizado desde decisiones y KB recalculada. EKB y prevención registrados.',
       'INFO',
       jsonb_build_object(
         'evidence_schema_version','operational-event/v2',
         'execution_id','CHATGPT_GOV_SESSION_55',
         'producer','ChatGPT',
         'purpose','Registrar hardening operativo de KB LF sin declarar aceptación final',
         'acceptance_declared', false,
         'occurred_at', NOW()::text,
         'operation','session_55_kb_production_hardening_v5',
         'controls', jsonb_build_array('decision_id','ALLOW_PROD_GATE','consumer_gate_passed','hitl_required_false','GROUNDED','decision_upstream')
       ),
       'CHATGPT_GOV_SESSION_55',
       'CHATGPT_GOV_SESSION_55';