-- D1/D2 metadata-only registered-entrypoint probe (candidate-only).
-- These fixture asset IDs exist solely in the test, NOT in discovery code.
-- An object existing in pg_catalog is not source/read authorization.
WITH fixture(case_code,asset_code) AS (
 VALUES
 ('REGISTERED_ENTRYPOINT','ACT-LF-B2B-LOGIN-CONTRACT-001'),
 ('UNKNOWN_ASSET','__D1D2_NOT_REGISTERED__')
), assets AS (
 SELECT f.case_code,f.asset_code,a.tipo_activo,a.estado_operativo,
        a.metadata#>>'{discoverability,recommended_entrypoint}' AS entrypoint,
        a.metadata#>>'{discoverability,parameterized_entrypoint}' AS rpc_entrypoint
 FROM fixture f LEFT JOIN public.lf_activos a ON a.codigo_activo=f.asset_code AND a.archived_at IS NULL
), catalog AS (
 SELECT a.*,c.oid AS view_oid,c.relkind,c.reloptions,
        EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname=split_part(a.rpc_entrypoint,'.',1)
             AND p.proname=split_part(a.rpc_entrypoint,'.',2)) AS rpc_resolves
 FROM assets a LEFT JOIN pg_class c ON c.oid=to_regclass(a.entrypoint)
)
SELECT case_code,asset_code,
       (tipo_activo IS NOT NULL) AS registered_asset_found,
       (view_oid IS NOT NULL AND relkind='v') AS exact_view_resolves,
       rpc_resolves,
       coalesce(reloptions @> ARRAY['security_invoker=true'],false) AS view_security_invoker,
       CASE WHEN view_oid IS NULL THEN false
            ELSE has_table_privilege('anon',view_oid,'SELECT') END AS anon_select,
       CASE WHEN view_oid IS NULL THEN false
            ELSE has_table_privilege('authenticated',view_oid,'SELECT') END AS authenticated_select,
       false AS admitted_data_read
FROM catalog ORDER BY case_code;
-- Positive fixture expected: asset+view+RPC exist; clients do not have SELECT
-- and view is not security_invoker. DO NOT grant read access based on this.
-- Negative fixture expected: no asset, view or read admission.
