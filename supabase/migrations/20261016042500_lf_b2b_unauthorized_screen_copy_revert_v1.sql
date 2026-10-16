-- Compensating PR #2821: the CTA copy was written outside a canonical screen
-- operation and consumer. Restore the exact original element shape and timestamp.
-- Does NOT undo unrelated migration history or modify auth, validators, tokens, profiles.
-- Only through ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train.
BEGIN;
CREATE TEMP TABLE lf_cta_revert_before ON COMMIT DROP AS
SELECT to_jsonb(e) AS before_element,
       (SELECT count(*) FROM lf_ops.pantalla_elementos) AS element_total,
       (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=51) AS rule_count,
       (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=51) AS field_count
FROM lf_ops.pantalla_elementos e WHERE e.element_id=291;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM lf_cta_revert_before)<>1
 THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_BASELINE_MISSING'; END IF;
END $pre$;
SAVEPOINT lf_cta_compensating_probe;

DO $revert$
DECLARE
  v_label_count integer;
BEGIN
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='pantalla_elementos' AND column_name='display_label')<>1
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_COLUMN_CHANGED'; END IF;
  SELECT count(*) INTO v_label_count FROM lf_ops.pantalla_elementos WHERE display_label IS NOT NULL;
  IF v_label_count<>1
    OR NOT EXISTS (SELECT 1 FROM lf_ops.pantalla_elementos e JOIN lf_ops.pantallas p ON p.id=e.pantalla_id
      WHERE e.element_id=291 AND e.element_code='B2B_AUTH001_SUBMIT' AND e.element_role='PRIMARY_CTA'
        AND e.display_label='Acceder' AND p.codigo='B2B-AUTH-001' AND e.status='CANDIDATO'
        AND e.created_at='2026-08-21 06:10:44.995307+00'::timestamptz
        AND e.updated_at='2026-10-16 03:04:46.031872+00'::timestamptz)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_SOURCE_DRIFT'; END IF;
  UPDATE lf_ops.pantalla_elementos e SET updated_at=e.created_at
  WHERE e.element_id=291 AND e.pantalla_id=51 AND e.element_code='B2B_AUTH001_SUBMIT'
    AND e.display_label='Acceder' AND e.status='CANDIDATO';
  ALTER TABLE lf_ops.pantalla_elementos DROP COLUMN display_label RESTRICT;
END $revert$;

DO $assert$
DECLARE
  before_copy jsonb;
  now_copy jsonb;
  v_count bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='lf_ops' AND table_name='pantalla_elementos'
       AND column_name='display_label')
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_COLUMN_REMAINS'; END IF;
  SELECT before_element-'display_label' INTO before_copy FROM lf_cta_revert_before;
  SELECT to_jsonb(e) INTO now_copy FROM lf_ops.pantalla_elementos e WHERE e.element_id=291;
  IF now_copy IS DISTINCT FROM (before_copy||jsonb_build_object('updated_at',before_copy->'created_at'))
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ELEMENT_NONCOPY_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos) <>
     (SELECT element_total FROM lf_cta_revert_before LIMIT 1)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ELEMENT_COUNT_CHANGED'; END IF;
  IF (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=51) <>
     (SELECT rule_count FROM lf_cta_revert_before LIMIT 1)
     OR (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=51) <>
     (SELECT field_count FROM lf_cta_revert_before LIMIT 1)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_RELATION_COUNT_CHANGED'; END IF;
  IF (SELECT estado FROM lf_ops.pantallas WHERE id=51)<>'CANDIDATO'
   OR (SELECT is_active FROM lf_ops.modulos WHERE module_code='B2B_AUTENTICACION') IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_UNEXPECTED_ACTIVATION'; END IF;
END $assert$;
ROLLBACK TO SAVEPOINT lf_cta_compensating_probe;
DO $rollback$
DECLARE b jsonb; a jsonb;
BEGIN
 IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='lf_ops'
    AND table_name='pantalla_elementos' AND column_name='display_label')<>1
 THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ROLLBACK_COLUMN_MISSING'; END IF;
 SELECT before_element INTO b FROM lf_cta_revert_before;
 SELECT to_jsonb(e) INTO a FROM lf_ops.pantalla_elementos e WHERE e.element_id=291;
 IF a IS DISTINCT FROM b
 THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ROLLBACK_ELEMENT_CHANGED'; END IF;
END $rollback$;
RELEASE SAVEPOINT lf_cta_compensating_probe;

DO $revert$
DECLARE
  v_label_count integer;
BEGIN
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='pantalla_elementos' AND column_name='display_label')<>1
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_COLUMN_CHANGED'; END IF;
  SELECT count(*) INTO v_label_count FROM lf_ops.pantalla_elementos WHERE display_label IS NOT NULL;
  IF v_label_count<>1
    OR NOT EXISTS (SELECT 1 FROM lf_ops.pantalla_elementos e JOIN lf_ops.pantallas p ON p.id=e.pantalla_id
      WHERE e.element_id=291 AND e.element_code='B2B_AUTH001_SUBMIT' AND e.element_role='PRIMARY_CTA'
        AND e.display_label='Acceder' AND p.codigo='B2B-AUTH-001' AND e.status='CANDIDATO'
        AND e.created_at='2026-08-21 06:10:44.995307+00'::timestamptz
        AND e.updated_at='2026-10-16 03:04:46.031872+00'::timestamptz)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_SOURCE_DRIFT'; END IF;
  UPDATE lf_ops.pantalla_elementos e SET updated_at=e.created_at
  WHERE e.element_id=291 AND e.pantalla_id=51 AND e.element_code='B2B_AUTH001_SUBMIT'
    AND e.display_label='Acceder' AND e.status='CANDIDATO';
  ALTER TABLE lf_ops.pantalla_elementos DROP COLUMN display_label RESTRICT;
END $revert$;

DO $assert$
DECLARE
  before_copy jsonb;
  now_copy jsonb;
  v_count bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='lf_ops' AND table_name='pantalla_elementos'
       AND column_name='display_label')
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_COLUMN_REMAINS'; END IF;
  SELECT before_element-'display_label' INTO before_copy FROM lf_cta_revert_before;
  SELECT to_jsonb(e) INTO now_copy FROM lf_ops.pantalla_elementos e WHERE e.element_id=291;
  IF now_copy IS DISTINCT FROM (before_copy||jsonb_build_object('updated_at',before_copy->'created_at'))
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ELEMENT_NONCOPY_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos) <>
     (SELECT element_total FROM lf_cta_revert_before LIMIT 1)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_ELEMENT_COUNT_CHANGED'; END IF;
  IF (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=51) <>
     (SELECT rule_count FROM lf_cta_revert_before LIMIT 1)
     OR (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=51) <>
     (SELECT field_count FROM lf_cta_revert_before LIMIT 1)
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_RELATION_COUNT_CHANGED'; END IF;
  IF (SELECT estado FROM lf_ops.pantallas WHERE id=51)<>'CANDIDATO'
   OR (SELECT is_active FROM lf_ops.modulos WHERE module_code='B2B_AUTENTICACION') IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_UNEXPECTED_ACTIVATION'; END IF;
END $assert$;
-- Two separately actionable lessons. Registration does not authorize a change.
INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,lote_origen,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context,evidencia)
SELECT v.codigo,v.categoria,v.titulo,v.descripcion,v.causa_raiz,v.patron,v.prevencion,v.validacion,v.severidad,v.lote_origen,v.estado,v.source_ref,v.lifecycle_phase,v.root_cause_family,v.detectability,v.source_context,v.evidencia
FROM (VALUES
('LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003','ROUTER_GOVERNANCE',
 'Detección temprana de pantalla interrumpió descubrimiento y selección de perfil/skill',
 'PR 2781 incluyó bloque IF de pantalla con RETURN anterior a v_lf_fuente_operativa_busqueda; interceptó solicitudes explícitas de perfil/skill que también decían pantalla.',
 'Se trató un objeto de trabajo (screen subject) como sustituto del activo ejecutor y se devolvió sin pasar por operación, contratos, policies, adapters ni Input Governance.',
 'SCREEN_SUBJECT_EARLY_RETURN_BYPASS','Separar sujeto del trabajo de perfil/skill/capacidad ejecutora. Prohibir cualquier RETURN de clasificación especializada anterior al discovery salvo bloqueos de seguridad explícitos que no reclasifiquen el ejecutor.',
 'PR 2822 debe restablecer la huella exacta de función anterior segura, demostrar rutas PERFIL/SKILL con texto pantalla y conservar el guard de escritura negativa B2B.','High','ACT0001-ROLLBACK-20261016','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2781|github://cristhianlujan/claude-persona-lf-patch/pull/2822',
 'router_discovery','R2_NO_VE','SILENT','ACT-0001 / PR2781 / SCREEN_SHORTCIRCUIT',
 'Read-only pruebas: ejecutar/inspeccionar perfil UI Architect y skill ACT-0045 con texto pantalla dio PANTALLA/BLOCKED en el atajo. PR2822 propone restauración por Merge Train.'),
('LF-SCREEN-CTA-COPY-BYPASS-20261016-004','OPERATION_GOVERNANCE',
 'Etiqueta candidata Acceder persistida por DB sin operación de pantalla ni consumidor',
 'PR 2821 creó lf_ops.pantalla_elementos.display_label y modificó B2B_AUTH001_SUBMIT aun cuando ACT-0001 no resolvía una operación de pantalla.',
 'Se confirió a una migración técnica capacidad de modificar la especificación de producto sin resolver el flujo de edición por operación/contrato/consumidor.',
 'DB_MIGRATION_USED_AS_SCREEN_OPERATION_SUBSTITUTE','Antes de cambios de pantalla: operación registrada y alcance semántico ligado a solicitud SHA; consumir desde contrato gobernado, comprobar publicación real. Migration solo transporte técnico gobernado.',
 'PR de compensación elimina columna y restaura timestamp exacto del elemento; validar cero diferencia en reglas/elementos, y no atribuir despliegue.','High','ACT0001-ROLLBACK-20261016','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2821',
 'screen_operation','R5_EROSION_PROCESO','SILENT','LF/B2B-AUTH-001/B2B_AUTH001_SUBMIT/PR2821',
 'PR2821 migración aplicada y Train PASS, pero ACT-0001 siguió BLOCK_OPERATION_NOT_REGISTERED; etiqueta sólo en especificación candidata, no en frontend real.')
) AS v(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,lote_origen,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context,evidencia)
WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge k WHERE k.codigo=v.codigo);
DO $ekb$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
   ('LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003','LF-SCREEN-CTA-COPY-BYPASS-20261016-004'))<>2
 THEN RAISE EXCEPTION 'LF_CTA_COMPENSATE_EKB_NOT_RECORDED'; END IF;
END $ekb$;
COMMIT;
