-- Analysis A9 -> PG-01: correct existing exact-receipt guard, no new engine.
-- Replaces only programacion.fn_analysis_pg01_exact_receipt_guard_v1.
-- Expected receipt identity/hash/schema MUST originate from governed A9 handoff,
-- independently of the resolved context. Does not activate PG-01 runtime.
-- Regression: 8/8 positive/negative cases PASS in BEGIN/ROLLBACK against live A9.
CREATE OR REPLACE FUNCTION programacion.fn_analysis_pg01_exact_receipt_guard_v1(
  p_resolution jsonb,
  p_expected_context_id text,
  p_expected_context_sha256 text,
  p_expected_schema_version text
) RETURNS boolean
LANGUAGE sql IMMUTABLE SECURITY INVOKER
SET search_path = pg_catalog
AS $guard$
  SELECT coalesce(
    p_resolution->>'state' = 'RESOLVED'
    AND p_resolution->>'resolution_basis' = 'IMMUTABLE_RECORDED_CONTEXT'
    AND p_resolution->>'latest_reinterpreted' = 'false'
    AND nullif(btrim(p_expected_context_id),'') IS NOT NULL
    AND nullif(btrim(p_expected_context_sha256),'') IS NOT NULL
    AND nullif(btrim(p_expected_schema_version),'') IS NOT NULL
    AND p_resolution->>'context_id' = p_expected_context_id
    AND p_resolution->>'context_sha256' = p_expected_context_sha256
    AND jsonb_typeof(p_resolution->'context') = 'object'
    AND p_resolution#>>'{context,schema_version}' = 'LF_DECISION_CONTEXT_ASOF_INPUT_V1'
    AND p_resolution#>>'{context,extensions,programming_context_snapshot,schema_version}' = p_expected_schema_version
    AND p_resolution->>'context_sha256' =
      encode(extensions.digest(convert_to((p_resolution->'context')::text,'UTF8'),'sha256'),'hex'),
    false
  );
$guard$;
-- PG-01 consumer wiring, schema digest parity, material-path validation and
-- independent currentness admission remain separate mandatory boundaries.
