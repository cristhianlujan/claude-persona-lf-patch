-- D1/D2: read-only diagnostic against CURRENT Supabase governance, NOT data.
-- The source and permission below are probe fixtures to validate denials, NOT
-- runtime routing rules. Generic runtime uses canonical source binding refs.
WITH fixture AS (
  SELECT 'supabase://catalog/lf_ops/cargas_lotes'::text AS source_ref,
         'B2B_LOAD_DETAIL_VIEW'::text AS permission_code
), observations AS (
  SELECT
    EXISTS(
      SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      CROSS JOIN fixture f
      WHERE c.relkind IN ('r','p','v')
        AND 'supabase://catalog/'||n.nspname||'/'||c.relname=f.source_ref
    ) AS metadata_source_exists,
    EXISTS(
      SELECT 1 FROM public.lf_activos a CROSS JOIN fixture f
      WHERE a.archived_at IS NULL AND a.tipo_activo IN ('DB_TABLE','TABLE')
        AND a.metadata->>'canonical_source_ref'=f.source_ref
        AND a.metadata->>'admission_status'='VIGENTE'
    ) AS canonical_read_binding_vigente,
    EXISTS(
      SELECT 1 FROM lf_ops.permisos p CROSS JOIN fixture f
      WHERE p.permission_code=f.permission_code AND p.status='VIGENTE'
    ) AS related_permission_vigente,
    auth.uid() IS NOT NULL AS authenticated_business_actor,
    lf_ops.b2b_current_user_id() IS NOT NULL AS business_user_bound,
    lf_ops.b2b_current_company_id() IS NOT NULL AS business_company_bound
)
SELECT metadata_source_exists,canonical_read_binding_vigente,
       related_permission_vigente,authenticated_business_actor,
       business_user_bound,business_company_bound,
       (metadata_source_exists AND canonical_read_binding_vigente
         AND related_permission_vigente AND authenticated_business_actor
         AND business_user_bound AND business_company_bound) AS necessary_conditions_satisfied,
       false AS business_data_read_authorized,
       CASE WHEN NOT metadata_source_exists THEN 'BLOCK_SOURCE_NOT_DISCOVERED'
            WHEN NOT canonical_read_binding_vigente THEN 'BLOCK_CANONICAL_READ_BINDING_ABSENT'
            WHEN NOT related_permission_vigente THEN 'BLOCK_PERMISSION_NOT_VIGENTE'
            WHEN NOT authenticated_business_actor THEN 'BLOCK_ACTOR_NOT_AUTHENTICATED'
            WHEN NOT business_user_bound OR NOT business_company_bound THEN 'BLOCK_B2B_CONTEXT_MISSING'
            ELSE 'BLOCK_FURTHER_AUTHORIZATION_AND_FACADE_PROOF_REQUIRED'
       END AS diagnostic
FROM observations;
-- The query is deny-only. Even satisfying necessary conditions would not
-- admit read access: role/tenant/explicit-deny/valid facade must be verified.
