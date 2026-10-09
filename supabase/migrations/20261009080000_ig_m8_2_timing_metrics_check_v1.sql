-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.2 / published-metrics assertion (read-only).
-- Problem: the M8.2 terminal gate returns a structural PASS although 0 IG_PERFORMANCE_TIMING receipts exist.
-- This function computes p50/p95 only from VERIFIED receipts already in the existing provenance sink and returns an explicit
-- SUMMARY status that a terminal gate can assert on. It issues no receipt, writes nothing and touches no semantic hash.
-- SUMMARY.status (fail-closed, evaluated in this order):
--   NOT_PUBLISHED               no VERIFIED timing receipt
--   PARTIAL_FAMILY_COVERAGE     fewer registry families have a FAMILY-phase receipt than the registry declares
--   PARTIAL_NO_RESOLVER_PHASE   family coverage complete but the sink does not accept phase RESOLVER, so the M8.2 exit
--                               criterion "p50/p95 por resolver" cannot be evidenced
--   PUBLISHED                   all registry families covered and the sink accepts RESOLVER receipts that exist
-- Receipts must be issued by the existing EVIDENCE_VERIFIER_V1 channel; this function never creates them.

CREATE OR REPLACE FUNCTION programacion.fn_ig_performance_timing_metrics_v1()
 RETURNS TABLE(scope text, phase text, family_code text, sample_count integer, p50_ms numeric, p95_ms numeric, status text, detail jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
WITH rc AS (
  SELECT r.payload->>'phase' AS phase,
         nullif(r.payload->>'family_code','') AS family_code,
         nullif(r.payload->>'resolver_code','') AS resolver_code,
         (r.payload->>'elapsed_ms')::numeric AS ms
  FROM programacion.provenance_receipts r
  WHERE r.subject_type='IG_PERFORMANCE_TIMING'
    AND r.receipt_kind='EVIDENCE_VERIFICATION'
    AND r.payload->>'verification_status'='VERIFIED'
    AND r.payload->>'elapsed_ms' ~ '^[0-9]{1,12}$'
), reg AS (
  SELECT jsonb_object_keys(c.especificacion->'families') AS fam
  FROM (SELECT especificacion FROM programacion.contratos
        WHERE contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND estado='defined' AND fail_closed
        ORDER BY id DESC LIMIT 1) c
), grp AS (
  SELECT 'GROUP'::text AS scope, rc.phase, coalesce(rc.family_code, rc.resolver_code) AS family_code,
         count(*)::integer AS n,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY rc.ms) AS p50,
         percentile_cont(0.95) WITHIN GROUP (ORDER BY rc.ms) AS p95
  FROM rc GROUP BY rc.phase, coalesce(rc.family_code, rc.resolver_code)
), cov AS (
  SELECT (SELECT count(*) FROM reg) AS fam_total,
         (SELECT count(DISTINCT rc.family_code) FROM rc JOIN reg ON reg.fam=rc.family_code WHERE rc.phase='FAMILY') AS fam_covered,
         (SELECT count(*) FROM rc) AS verified_total,
         (SELECT count(*) FROM rc WHERE rc.phase='RESOLVER') AS resolver_receipts,
         EXISTS (SELECT 1 FROM pg_constraint k
                 WHERE k.conrelid='programacion.provenance_receipts'::regclass
                   AND k.conname='provenance_receipts_ig_performance_timing_sink_v1'
                   AND pg_get_constraintdef(k.oid) LIKE '%''RESOLVER''%') AS sink_accepts_resolver
)
SELECT g.scope, g.phase, g.family_code, g.n, g.p50, g.p95, 'MEASURED'::text, NULL::jsonb FROM grp g
UNION ALL
SELECT 'SUMMARY', NULL, NULL, cov.verified_total::integer, NULL, NULL,
  CASE WHEN cov.verified_total=0 THEN 'NOT_PUBLISHED'
       WHEN cov.fam_total=0 OR cov.fam_covered<cov.fam_total THEN 'PARTIAL_FAMILY_COVERAGE'
       WHEN NOT cov.sink_accepts_resolver OR cov.resolver_receipts=0 THEN 'PARTIAL_NO_RESOLVER_PHASE'
       ELSE 'PUBLISHED' END,
  jsonb_build_object('families_in_registry',cov.fam_total,'families_with_family_phase_receipt',cov.fam_covered,
    'verified_receipts',cov.verified_total,'resolver_receipts',cov.resolver_receipts,
    'sink_accepts_resolver_phase',cov.sink_accepts_resolver,'timings_excluded_from_semantic_sha',true)
FROM cov
$fn$;
