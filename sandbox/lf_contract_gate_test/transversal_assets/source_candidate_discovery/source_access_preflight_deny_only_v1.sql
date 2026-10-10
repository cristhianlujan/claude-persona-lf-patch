-- D1/D2 SOURCE ACCESS PREFLIGHT (read-only / DENY-ONLY).
-- Candidate documentation only; not an admission endpoint and not deployed.
-- The caller MUST be a trusted server-side adapter with genuine JWT identity
-- propagation. Never derive actor / company / allowed_schemas / expected policy
-- from an LLM response or spreadsheet.
--
-- Input parameters:
--   requested_source_ref:  %(requested_source_ref)s::text
--   allowed_schemas:       %(allowed_schemas)s::text[]
--   expected_policy_sha:   %(expected_policy_sha)s::text
-- No row from an LF operational data table is read.
-- Privileged postgres/service_role connections MUST NOT be treated as a
-- business actor, and their ability to read tables grants no agent rights.

WITH parameters AS (
  SELECT
    %(requested_source_ref)s::text AS requested_source_ref,
    %(allowed_schemas)s::text[] AS allowed_schemas,
    %(expected_policy_sha)s::text AS expected_policy_sha
), scoped_source AS (
  SELECT c.oid, n.nspname, c.relname
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN parameters p
  WHERE n.nspname = ANY(p.allowed_schemas)
    AND c.relkind IN ('r','p','v')
    AND 'supabase://catalog/'||n.nspname||'/'||c.relname = p.requested_source_ref
), active_policy AS (
  SELECT count(*)::integer AS active_count, max(policy_sha) AS active_sha
  FROM public.lf_policy_versions
  WHERE policy_code = 'POL-LF-SOURCE-RESOLUTION'
    AND status = 'ACTIVE'
), trust_context AS (
  SELECT
    (SELECT count(*) FROM scoped_source) AS source_count,
    (SELECT active_count FROM active_policy) AS policy_count,
    (SELECT active_sha FROM active_policy) AS active_sha,
    (SELECT expected_policy_sha FROM parameters) AS expected_sha,
    auth.uid() IS NOT NULL AS verified_jwt_actor,
    lf_ops.b2b_current_user_id() IS NOT NULL AS verified_business_user,
    lf_ops.b2b_current_company_id() IS NOT NULL AS verified_business_company
)
SELECT
  CASE
    WHEN source_count <> 1 THEN 'BLOCK_SOURCE_NOT_IN_METADATA_SCOPE'
    WHEN policy_count <> 1 OR active_sha IS DISTINCT FROM expected_sha
         THEN 'BLOCK_POLICY_VERSION_MISMATCH'
    WHEN NOT verified_jwt_actor THEN 'BLOCK_ACTOR_NOT_AUTHENTICATED'
    WHEN NOT verified_business_user THEN 'BLOCK_USER_NOT_BOUND'
    WHEN NOT verified_business_company THEN 'BLOCK_COMPANY_NOT_BOUND'
    ELSE 'BLOCK_CANONICAL_SOURCE_READ_BINDING_REQUIRED'
  END AS decision,
  source_count = 1 AS metadata_candidate_found,
  false AS business_data_read_authorized,
  'METADATA_DISCOVERY_ONLY'::text AS allowed_effect,
  policy_count = 1 AND active_sha = expected_sha AS active_policy_verified
FROM trust_context;

-- Even a passing identity + policy check MUST NOT authorize data reading:
-- an independent canonical source binding, resource/action permission, tenant
-- constraint, bounded query, approved route, evidence receipt and RLS boundary
-- are still necessary. This query always returns false for business data access.
