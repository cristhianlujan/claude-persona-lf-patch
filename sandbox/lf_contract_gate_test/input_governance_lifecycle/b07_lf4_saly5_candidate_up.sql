-- LF B07 / DESIGN CANDIDATE ONLY / UNSIGNED. NOT a Supabase migration.
-- Proposes 4 LF and 5 SALY fields; all 9 INFERRED, nullable, default NULL.
-- Only for isolated PG17.6/18.7 tests pending owner sign-off.
-- Do not write to Supabase, modify RUNs, or normalize saly.reglas.estado.
BEGIN;
DO $b07_up_preflight$
BEGIN
 IF to_regclass('lf_ops.reglas') IS NULL OR to_regclass('saly.reglas') IS NULL
 THEN RAISE EXCEPTION 'B07_UP_SOURCE_TABLE_MISSING'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='lf_ops.reglas'::regclass
   AND attname='estado' AND NOT attisdropped)
 OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='saly.reglas'::regclass
   AND attname='estado' AND NOT attisdropped)
 THEN RAISE EXCEPTION 'B07_UP_SOURCE_ESTADO_MISSING'; END IF;
 IF EXISTS (SELECT 1 FROM pg_attribute WHERE
       attrelid IN ('lf_ops.reglas'::regclass,'saly.reglas'::regclass)
       AND attname IN ('lifecycle_state','lifecycle_source_sha256',
         'lifecycle_decision_ref','lifecycle_changed_at','lifecycle_origin_estado')
       AND attnum>0 AND NOT attisdropped)
 THEN RAISE EXCEPTION 'B07_UP_FIELD_ALREADY_EXISTS'; END IF;
END $b07_up_preflight$;

ALTER TABLE lf_ops.reglas
 ADD COLUMN lifecycle_state text,
 ADD COLUMN lifecycle_source_sha256 text,
 ADD COLUMN lifecycle_decision_ref text,
 ADD COLUMN lifecycle_changed_at timestamptz;
ALTER TABLE saly.reglas
 ADD COLUMN lifecycle_state text,
 ADD COLUMN lifecycle_source_sha256 text,
 ADD COLUMN lifecycle_decision_ref text,
 ADD COLUMN lifecycle_changed_at timestamptz,
 ADD COLUMN lifecycle_origin_estado text;

-- SHA shape only: content-bound validation is left to an official writer.
-- Require a complete audit bundle for any nonnull lifecycle_state.
ALTER TABLE lf_ops.reglas
 ADD CONSTRAINT lf_b07_lifecycle_bundle_v1 CHECK (
   lifecycle_state IS NULL OR
   (length(btrim(lifecycle_state))>0 AND
    lifecycle_source_sha256 IS NOT NULL AND
    nullif(btrim(lifecycle_decision_ref),'') IS NOT NULL AND
    lifecycle_changed_at IS NOT NULL)),
 ADD CONSTRAINT lf_b07_lifecycle_sha_v1 CHECK (
   lifecycle_source_sha256 IS NULL OR lifecycle_source_sha256 ~ '^[0-9a-f]{64}$');
ALTER TABLE saly.reglas
 ADD CONSTRAINT saly_b07_lifecycle_bundle_v1 CHECK (
   lifecycle_state IS NULL OR
   (length(btrim(lifecycle_state))>0 AND
    lifecycle_source_sha256 IS NOT NULL AND
    nullif(btrim(lifecycle_decision_ref),'') IS NOT NULL AND
    lifecycle_changed_at IS NOT NULL AND
    lifecycle_origin_estado IS NOT NULL)),
 ADD CONSTRAINT saly_b07_lifecycle_sha_v1 CHECK (
   lifecycle_source_sha256 IS NULL OR lifecycle_source_sha256 ~ '^[0-9a-f]{64}$'),
 ADD CONSTRAINT saly_b07_lifecycle_origin_v1 CHECK (
   lifecycle_origin_estado IS NULL OR lifecycle_origin_estado=estado);

DO $b07_up_readback$
BEGIN
 IF (SELECT count(*) FROM information_schema.columns
   WHERE table_schema='lf_ops' AND table_name='reglas' AND
   column_name IN ('lifecycle_state','lifecycle_source_sha256',
      'lifecycle_decision_ref','lifecycle_changed_at'))<>4
 OR (SELECT count(*) FROM information_schema.columns
   WHERE table_schema='saly' AND table_name='reglas' AND
   column_name IN ('lifecycle_state','lifecycle_source_sha256',
      'lifecycle_decision_ref','lifecycle_changed_at','lifecycle_origin_estado'))<>5
 OR EXISTS (SELECT 1 FROM lf_ops.reglas
   WHERE lifecycle_state IS NOT NULL OR lifecycle_source_sha256 IS NOT NULL
      OR lifecycle_decision_ref IS NOT NULL OR lifecycle_changed_at IS NOT NULL)
 OR EXISTS (SELECT 1 FROM saly.reglas
   WHERE lifecycle_state IS NOT NULL OR lifecycle_source_sha256 IS NOT NULL
      OR lifecycle_decision_ref IS NOT NULL OR lifecycle_changed_at IS NOT NULL
      OR lifecycle_origin_estado IS NOT NULL)
 THEN RAISE EXCEPTION 'B07_UP_READBACK_FAILURE'; END IF;
END $b07_up_readback$;
COMMIT;
