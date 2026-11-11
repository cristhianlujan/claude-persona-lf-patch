-- LF #3779 / lote 7: post-cut SELECT-only evidence per real IG RUN.
-- Example (authorized read-only session): psql -v ig_run_id=<REAL_RUN_ID> -f this_file.sql
-- Run separately per IG candidate returned by lf_rule_admin_bulk_atomic_v1.
-- This is NOT an executor, a writer, a new RUN, a recuration route or a GO receipt.
-- Never interpret COMPLETED as CURRENT. Any error or missing evidence => NO-GO.
\set ON_ERROR_STOP on
\if :{?ig_run_id}
\else
  \echo 'BLOCK_IG_POSTCUT_RUN_ID_REQUIRED'
  \quit 3
\endif

BEGIN TRANSACTION READ ONLY;
WITH requested AS (
 SELECT :'ig_run_id'::bigint AS run_id
), target AS (
 SELECT req.run_id,r.pantalla_id,r.status,r.invalidated_at,
        r.source_manifest,
        EXISTS(SELECT 1 FROM programacion.input_readiness_runs successor
          WHERE successor.supersedes_run_id=r.id AND successor.status='COMPLETED')
          AS terminal_successor,
        (SELECT p.codigo FROM lf_ops.pantallas p WHERE p.id=r.pantalla_id)
          AS screen_code
 FROM requested req
 LEFT JOIN programacion.input_readiness_runs r ON r.id=req.run_id
), scoped AS (
 SELECT t.*,
   (SELECT count(*) FROM lf_ops.reglas) AS canonical_rule_count,
   (SELECT count(*) FROM lf_ops.reglas
    WHERE to_jsonb(lf_ops.reglas)->>'owner_name'='SUPER_ADMIN' AND created_by='ChatGPT')
     AS canonical_updated_count,
   EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_schema='lf_ops' AND table_name='reglas'
      AND column_name='owner_name') AS owner_column_exists,
   (SELECT count(*) FROM jsonb_array_elements(
     CASE WHEN jsonb_typeof(t.source_manifest)='array'
       THEN t.source_manifest ELSE '[]'::jsonb END) x(value)
    WHERE x.value->'ref'->>'kind'='RULE') AS direct_rule_pin_count,
   (SELECT count(*) FROM jsonb_array_elements(
     CASE WHEN jsonb_typeof(t.source_manifest)='array'
       THEN t.source_manifest ELSE '[]'::jsonb END) x(value)
    WHERE x.value->'ref'->>'kind'='SCREEN_RULE_SET') AS rule_set_pin_count,
   (SELECT count(*) FROM jsonb_array_elements(
     CASE WHEN jsonb_typeof(t.source_manifest)='array'
       THEN t.source_manifest ELSE '[]'::jsonb END) x(value)
    WHERE x.value->'ref'->>'kind'='SCREEN_CANONICAL_GRAPH') AS graph_pin_count
 FROM target t
), authority AS (
 SELECT s.*,
 CASE WHEN s.status='COMPLETED'
        AND s.invalidated_at IS NULL
        AND NOT coalesce(s.terminal_successor,true)
        AND s.canonical_rule_count=578
        AND s.canonical_updated_count=578
        AND s.owner_column_exists
      THEN programacion.fn_input_run_source_currentness_v1(s.run_id)
      ELSE NULL::jsonb END AS source_currentness_receipt
 FROM scoped s
)
SELECT 'LF_RULE_BULK_IG_POSTCUT_READBACK_V1' AS evidence_contract,
  run_id,screen_code,canonical_rule_count,canonical_updated_count,
  direct_rule_pin_count,rule_set_pin_count,graph_pin_count,
  source_currentness_receipt,
  CASE
   WHEN status IS NULL THEN 'BLOCK_IG_RUN_NOT_FOUND'
   WHEN status<>'COMPLETED' OR invalidated_at IS NOT NULL
     OR coalesce(terminal_successor,false) THEN 'BLOCK_IG_RUN_SUPERSEDED_OR_TERMINAL_INVALID'
   WHEN NOT owner_column_exists OR canonical_rule_count<>578 OR canonical_updated_count<>578
     THEN 'BLOCK_CUT_NOT_VERIFIED'
   WHEN source_currentness_receipt IS NULL
     OR source_currentness_receipt->>'source_current' NOT IN ('true','false')
     THEN 'BLOCK_CURRENTNESS_AUTHORITY_UNAVAILABLE'
   WHEN source_currentness_receipt->>'source_current'='true'
     AND (direct_rule_pin_count>0 OR rule_set_pin_count>0)
     THEN 'BLOCK_FULL_ROW_PIN_CONTRADICTION_VERIFY_DELTA'
   WHEN source_currentness_receipt->>'source_current'='true'
     THEN 'REUSE_CURRENT_NO_RECURATION'
   WHEN source_currentness_receipt->>'source_current'='false'
     THEN 'FRESHNESS_DELTA_EVIDENCE_REQUIRED'
   ELSE 'BLOCK_CURRENTNESS_UNRESOLVED'
  END AS decision,
  false AS production_release_authorized
FROM authority;
COMMIT;

-- For FRESHNESS_DELTA_EVIDENCE_REQUIRED only, use the already deployed
-- programacion.fn_input_freshness_delta(<SAME_RUN_ID>) via read-only session.
-- Resolve material source change and affected families before triggering
-- existing governed Input Curator -> Validator. Do not UPDATE IG terminal runs.
-- A SOURCE_CURRENTNESS receipt is not semantic-depth or independent-validator proof.
