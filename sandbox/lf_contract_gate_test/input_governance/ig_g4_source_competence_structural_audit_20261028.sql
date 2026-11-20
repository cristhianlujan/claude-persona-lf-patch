-- LF IG G4 source-of-competence precheck, SELECT ONLY, PG17.6
-- MATERIALIZED applies to reused canonical snapshots only. 
-- All counts are structural; never interpret origin/category/owner_name as authorization.
WITH rules AS MATERIALIZED (
 SELECT id,codigo,categoria,origen,
        valor_config->'applicability_v1' AS selector
 FROM lf_ops.reglas
),
assets AS MATERIALIZED (
 SELECT codigo_activo,owner_name
 FROM public.lf_activos
),
policies AS MATERIALIZED (
 SELECT policy_code,status,source_ref,business_scope,channel_scope,
        capabilities_any,action_families_any,asset_types_any
 FROM private.lf_reusable_policy_registry_v1
),
counts AS MATERIALIZED (
 SELECT (SELECT count(*) FROM rules) rules_total,
 (SELECT count(*) FROM assets) assets_total,
 (SELECT count(*) FROM policies) reusable_policies,
 (SELECT count(*) FROM rules r JOIN assets a ON a.codigo_activo=r.codigo) exact_code_matches,
 (SELECT count(*) FROM rules WHERE selector->>'status'='ACTIVE') active_selectors,
 (SELECT count(*) FROM policies WHERE status='VIGENTE') vigente_reusable_policies
)
SELECT * FROM counts;