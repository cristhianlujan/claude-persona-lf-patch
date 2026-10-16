-- LF B2B screen canonical candidate-only copy; no published frontend claim.
-- ACT-0001 literal request: only PRIMARY_CTA display label becomes 'Acceder'.
-- Source: lf_ops.pantallas + lf_ops.pantalla_elementos (no messages/token rewrite).
-- Route: ACTUALIZACION_DB_LF / Migration Merge Train.
BEGIN;
DO $pre$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='lf_ops' AND table_name='pantalla_elementos'
      AND column_name='display_label'
  ) THEN
    RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_COLUMN_EXISTS_RECONCILE';
  END IF;
  IF (SELECT count(*) FROM lf_ops.pantallas
      WHERE codigo='B2B-AUTH-001' AND id=51 AND activa AND estado='CANDIDATO')<>1
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_IDENTITY_OR_STATUS_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos e
      JOIN lf_ops.pantallas p ON p.id=e.pantalla_id
      WHERE p.codigo='B2B-AUTH-001' AND e.element_code='B2B_AUTH001_SUBMIT'
        AND e.element_role='PRIMARY_CTA' AND e.semantic_binding_status='RESOLVED_ID'
        AND e.element_id=291 AND e.status='CANDIDATO')<>1
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_CTA_NOT_UNIQUE_CURRENT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE pantalla_id=51 AND element_role='PRIMARY_CTA')<>1
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_PRIMARY_CTA_AMBIGUOUS'; END IF;
END $pre$;

CREATE TEMP TABLE lf_screen_label_baseline ON COMMIT DROP AS
SELECT e.element_id,to_jsonb(e) AS before_element,
       (SELECT count(*) FROM lf_ops.pantalla_elementos) AS total_elements,
       (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=51) AS linked_rules,
       (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=51) AS linked_fields
FROM lf_ops.pantalla_elementos e WHERE e.element_id=291;

SAVEPOINT lf_screen_label_probe;
ALTER TABLE lf_ops.pantalla_elementos ADD COLUMN display_label text;
COMMENT ON COLUMN lf_ops.pantalla_elementos.display_label IS
 'Optional screen element display copy. It is not a component style token, message action, business rule, authentication handler or runtime activation.';
UPDATE lf_ops.pantalla_elementos
   SET display_label='Acceder', updated_at=clock_timestamp()
 WHERE element_id=291 AND pantalla_id=51 AND element_code='B2B_AUTH001_SUBMIT'
   AND element_role='PRIMARY_CTA' AND semantic_binding_status='RESOLVED_ID'
   AND status='CANDIDATO';

DO $positive$
DECLARE b jsonb; a jsonb;
BEGIN
  SELECT before_element INTO b FROM lf_screen_label_baseline WHERE element_id=291;
  SELECT to_jsonb(e) INTO a FROM lf_ops.pantalla_elementos e WHERE element_id=291;
  IF a->>'display_label'<>'Acceder' OR
     (a-'display_label'-'updated_at') IS DISTINCT FROM (b-'updated_at')
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_NONCOPY_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE display_label IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_CROSS_SCREEN_WRITE'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos) <>
     (SELECT total_elements FROM lf_screen_label_baseline LIMIT 1)
  OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=51) <>
     (SELECT linked_rules FROM lf_screen_label_baseline LIMIT 1)
  OR (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=51) <>
     (SELECT linked_fields FROM lf_screen_label_baseline LIMIT 1)
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_RELATION_COUNT_DRIFT'; END IF;
  IF (SELECT estado FROM lf_ops.pantallas WHERE id=51)<>'CANDIDATO'
     OR (SELECT is_active FROM lf_ops.modulos WHERE module_code='B2B_AUTENTICACION')
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_UNAUTHORIZED_PROMOTION'; END IF;
END $positive$;

ROLLBACK TO SAVEPOINT lf_screen_label_probe;
DO $negative$
DECLARE b jsonb; a jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='lf_ops' AND table_name='pantalla_elementos' AND column_name='display_label')
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_ROLLBACK_COLUMN_RESIDUE'; END IF;
  SELECT before_element INTO b FROM lf_screen_label_baseline WHERE element_id=291;
  SELECT to_jsonb(e) INTO a FROM lf_ops.pantalla_elementos e WHERE element_id=291;
  IF a IS DISTINCT FROM b
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_ROLLBACK_ROW_RESIDUE'; END IF;
END $negative$;
RELEASE SAVEPOINT lf_screen_label_probe;

ALTER TABLE lf_ops.pantalla_elementos ADD COLUMN display_label text;
COMMENT ON COLUMN lf_ops.pantalla_elementos.display_label IS
 'Optional screen element display copy. It is not a component style token, message action, business rule, authentication handler or runtime activation.';
UPDATE lf_ops.pantalla_elementos
   SET display_label='Acceder', updated_at=clock_timestamp()
 WHERE element_id=291 AND pantalla_id=51 AND element_code='B2B_AUTH001_SUBMIT'
   AND element_role='PRIMARY_CTA' AND semantic_binding_status='RESOLVED_ID'
   AND status='CANDIDATO';
DO $durable$
DECLARE b jsonb; a jsonb;
BEGIN
  SELECT before_element INTO b FROM lf_screen_label_baseline WHERE element_id=291;
  SELECT to_jsonb(e) INTO a FROM lf_ops.pantalla_elementos e WHERE element_id=291;
  IF a->>'display_label'<>'Acceder' OR (a-'display_label'-'updated_at') IS DISTINCT FROM (b-'updated_at')
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_DURABLE_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE display_label IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'LF_SCREEN_DISPLAY_LABEL_DURABLE_SCOPE_FAIL'; END IF;
END $durable$;
COMMIT;
