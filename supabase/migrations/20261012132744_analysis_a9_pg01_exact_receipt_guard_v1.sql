-- A9 -> PG-01 candidate: fail-closed identity guard. No runtime activation.
-- The caller must supply expected receipt values from the governed A9 handoff,
-- never derive them from the resolver output itself.
CREATE OR REPLACE FUNCTION programacion.fn_analysis_pg01_exact_receipt_guard_v1(
  p_resolution jsonb, p_expected_context_id text,
  p_expected_context_sha256 text, p_expected_schema_version text
) RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER
SET search_path = pg_catalog AS $function$
  SELECT coalesce(
    p_resolution->>'state' = 'RESOLVED'
    AND nullif(btrim(p_expected_context_id),'') IS NOT NULL
    AND nullif(btrim(p_expected_context_sha256),'') IS NOT NULL
    AND nullif(btrim(p_expected_schema_version),'') IS NOT NULL
    AND p_resolution->>'context_id' = p_expected_context_id
    AND p_resolution->>'context_sha256' = p_expected_context_sha256
    AND p_resolution#>>'{context,schema_version}' = p_expected_schema_version,
    false
  );
$function$;
-- PG-01 must call this guard before accepting a resolved A9 context.
-- Migration requires governed apply and readback; this file alone does not wire PG-01.
