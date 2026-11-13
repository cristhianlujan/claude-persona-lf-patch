-- LF B07 / DESIGN CANDIDATE ONLY / UNSIGNED.
-- Fail-closed DOWN: never discard any committed lifecycle evidence.
-- A data-bearing row MUST be handled by a separately approved restoration plan.
BEGIN;
DO $b07_down_preflight$
BEGIN
 IF to_regclass('lf_ops.reglas') IS NULL OR to_regclass('saly.reglas') IS NULL
 THEN RAISE EXCEPTION 'B07_DOWN_SOURCE_TABLE_MISSING'; END IF;
 IF (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='lf_ops' AND table_name='reglas'
      AND column_name IN ('lifecycle_state','lifecycle_source_sha256',
                         'lifecycle_decision_ref','lifecycle_changed_at'))<>4
 OR (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='saly' AND table_name='reglas'
      AND column_name IN ('lifecycle_state','lifecycle_source_sha256',
                         'lifecycle_decision_ref','lifecycle_changed_at',
                         'lifecycle_origin_estado'))<>5
 THEN RAISE EXCEPTION 'B07_DOWN_EXACT_SHAPE_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM lf_ops.reglas
   WHERE lifecycle_state IS NOT NULL OR lifecycle_source_sha256 IS NOT NULL
     OR lifecycle_decision_ref IS NOT NULL OR lifecycle_changed_at IS NOT NULL)
 OR EXISTS (SELECT 1 FROM saly.reglas
   WHERE lifecycle_state IS NOT NULL OR lifecycle_source_sha256 IS NOT NULL
     OR lifecycle_decision_ref IS NOT NULL OR lifecycle_changed_at IS NOT NULL
     OR lifecycle_origin_estado IS NOT NULL)
 THEN RAISE EXCEPTION 'B07_DOWN_NONEMPTY_EVIDENCE_BLOCKED'; END IF;
END $b07_down_preflight$;
-- RESTRICT blocks unmanaged dependencies; never use CASCADE.
ALTER TABLE lf_ops.reglas
 DROP CONSTRAINT lf_b07_lifecycle_bundle_v1,
 DROP CONSTRAINT lf_b07_lifecycle_sha_v1;
ALTER TABLE saly.reglas
 DROP CONSTRAINT saly_b07_lifecycle_bundle_v1,
 DROP CONSTRAINT saly_b07_lifecycle_sha_v1,
 DROP CONSTRAINT saly_b07_lifecycle_origin_v1;
ALTER TABLE lf_ops.reglas
 DROP COLUMN lifecycle_state RESTRICT,
 DROP COLUMN lifecycle_source_sha256 RESTRICT,
 DROP COLUMN lifecycle_decision_ref RESTRICT,
 DROP COLUMN lifecycle_changed_at RESTRICT;
ALTER TABLE saly.reglas
 DROP COLUMN lifecycle_state RESTRICT,
 DROP COLUMN lifecycle_source_sha256 RESTRICT,
 DROP COLUMN lifecycle_decision_ref RESTRICT,
 DROP COLUMN lifecycle_changed_at RESTRICT,
 DROP COLUMN lifecycle_origin_estado RESTRICT;
DO $b07_down_readback$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_attribute
    WHERE attrelid IN ('lf_ops.reglas'::regclass,'saly.reglas'::regclass)
      AND attname IN ('lifecycle_state','lifecycle_source_sha256',
        'lifecycle_decision_ref','lifecycle_changed_at','lifecycle_origin_estado')
      AND attnum>0 AND NOT attisdropped)
 THEN RAISE EXCEPTION 'B07_DOWN_FIELDS_REMAIN'; END IF;
END $b07_down_readback$;
COMMIT;
