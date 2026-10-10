-- READONLY D1/D2 source-preflight contract probes.
-- No operational data rows are read. These are fixed regression probes, NOT
-- case-specific routes used by the discovery runtime.
-- Requires source-resolution policy already registered in Supabase.
WITH active_policy AS (
  SELECT count(*)::integer AS active_count, max(policy_sha) AS policy_sha
  FROM public.lf_policy_versions
  WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
), fixtures(fixture_code,source_ref,expected_sha) AS (
  VALUES
    ('CURRENT_SOURCE_AND_POLICY',
       'supabase://catalog/lf_ops/cargas_lotes',
       (SELECT policy_sha FROM active_policy)),
    ('MISSING_SOURCE',
       'supabase://catalog/lf_ops/__does_not_exist_d1_d2__',
       (SELECT policy_sha FROM active_policy)),
    ('STALE_POLICY',
       'supabase://catalog/lf_ops/cargas_lotes',
       '__stale_policy_hash__')
), verified AS (
  SELECT f.fixture_code,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='lf_ops'
        AND c.relkind IN ('r','p','v')
        AND ('supabase://catalog/'||n.nspname||'/'||c.relname)=f.source_ref
    ) AS catalog_match,
    p.active_count=1 AND p.policy_sha=f.expected_sha AS current_policy
  FROM fixtures f CROSS JOIN active_policy p
)
SELECT fixture_code,catalog_match,current_policy,
  CASE
    WHEN NOT catalog_match THEN 'BLOCK_SOURCE_NOT_IN_METADATA_SCOPE'
    WHEN NOT current_policy THEN 'BLOCK_POLICY_VERSION_MISMATCH'
    WHEN auth.uid() IS NULL THEN 'BLOCK_ACTOR_NOT_AUTHENTICATED'
    ELSE 'BLOCK_CANONICAL_SOURCE_READ_BINDING_REQUIRED'
  END AS preflight_decision,
  false AS business_data_read_authorized
FROM verified
ORDER BY fixture_code;

-- Expected on an administrative sandbox diagnostic connection:
-- CURRENT_SOURCE_AND_POLICY: catalog_match=true, current_policy=true,
--   BLOCK_ACTOR_NOT_AUTHENTICATED
-- MISSING_SOURCE: catalog_match=false, BLOCK_SOURCE_NOT_IN_METADATA_SCOPE
-- STALE_POLICY: current_policy=false, BLOCK_POLICY_VERSION_MISMATCH
-- This query never grants access; successful source-policy validation is not
-- successful data admission. Do not run fixtures against client production data.
