-- LF D1/D2: B2B tenant-bound SOURCE-READ PREFLIGHT.
-- Read-only contract candidate, not an admission receipt nor deployed RPC.
-- Values are supplied by a trusted *verified-session* server adapter, never
-- generated as SQL/authority flags by GPT. Fails closed if ACL SELECT denied.
-- This contract has no hardcoded business table route or permission.
--
-- %(source_ref)s ::text (canonical discovery ref)
-- %(company_id)s ::uuid (explicit context, verified against JWT actor)
-- %(policy_sha)s ::text (expected CURRENT from Supabase, never model supplied)
WITH input AS (
 SELECT %(source_ref)s::text AS source_ref,
        %(company_id)s::uuid AS company_id,
        %(policy_sha)s::text AS expected_policy_sha
), source_catalog AS (
 SELECT count(*)::int AS object_count,
        max(encode(extensions.digest(convert_to(
           n.nspname||'.'||c.relname||'|'||coalesce(cols.structure,''),
           'UTF8'),'sha256'),'hex')) AS current_fingerprint
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN input i
 LEFT JOIN LATERAL (
    SELECT string_agg(att.attname||':'||att.atttypid::regtype::text||':'||
                      att.attnotnull::text,'|' ORDER BY att.attnum) AS structure
    FROM pg_catalog.pg_attribute att
    WHERE att.attrelid=c.oid AND att.attnum>0 AND NOT att.attisdropped
 ) cols ON TRUE
 WHERE ('supabase://catalog/'||n.nspname||'/'||c.relname)=i.source_ref
   AND c.relkind IN ('r','p','v') AND NOT c.relispartition
), governing_policy AS (
 SELECT count(*)::int AS current_count,max(policy_sha) AS current_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
), binding_matches AS (
 SELECT a.codigo_activo,a.metadata,
        a.metadata->>'required_permission_code' AS permission_code
 FROM public.lf_activos a CROSS JOIN input i
 WHERE a.archived_at IS NULL
   AND a.metadata->>'canonical_source_ref'=i.source_ref
   AND a.metadata->>'admission_status'='VIGENTE'
), binding_count AS (
 SELECT count(*)::int AS n, max(permission_code) AS permission_code,
        max(metadata->>'policy_sha') AS binding_policy_sha,
        max(metadata->>'read_facade_ref') AS read_facade_ref,
        max(metadata->>'tenant_scope_rule_ref') AS tenant_rule_ref,
        max(metadata->>'source_schema_fingerprint') AS schema_fingerprint
 FROM binding_matches
), caller AS (
 SELECT auth.uid() AS jwt_auth_user_id,
        current_user::text AS db_role,
        session_user::text AS session_role
), chosen_user AS (
 SELECT count(*)::int AS n,max(u.user_id::text)::uuid AS user_id
 FROM lf_ops.empresa_usuarios u CROSS JOIN caller c CROSS JOIN input i
 WHERE c.jwt_auth_user_id IS NOT NULL
   AND u.auth_user_id=c.jwt_auth_user_id
   AND u.company_id=i.company_id
   AND u.status='ACTIVE'
), scoped_assignment AS (
 SELECT count(*)::int AS n
 FROM lf_ops.b2b_user_company_assignments x CROSS JOIN chosen_user u CROSS JOIN input i
 WHERE x.user_id=u.user_id AND x.company_id=i.company_id AND x.status='VIGENTE'
), eligible_permission AS (
 SELECT count(*)::int AS n,max(permission_id) AS permission_id
 FROM lf_ops.permisos p CROSS JOIN binding_count b
 WHERE p.permission_code=b.permission_code AND p.status='VIGENTE'
), explicit_permission AS (
 SELECT
 count(*) FILTER(WHERE x.status='VIGENTE' AND x.access_effect='ALLOW')::int AS allow_count,
 count(*) FILTER(WHERE x.status='VIGENTE' AND x.access_effect='DENY')::int AS deny_count
 FROM lf_ops.b2b_user_company_permissions x
 CROSS JOIN chosen_user u CROSS JOIN input i CROSS JOIN eligible_permission p
 WHERE x.user_id=u.user_id AND x.company_id=i.company_id AND x.permission_id=p.permission_id
), decisions AS (
 SELECT CASE
  WHEN g.current_count<>1 OR g.current_sha IS DISTINCT FROM i.expected_policy_sha
    THEN 'BLOCK_POLICY_DRIFT'
  WHEN i.source_ref IS NULL OR i.company_id IS NULL
    THEN 'BLOCK_SOURCE_OR_EXPLICIT_COMPANY_MISSING'
  WHEN sc.object_count<>1 THEN 'BLOCK_SOURCE_OBJECT_NOT_FOUND_IN_CATALOG'
  WHEN b.n<>1 THEN 'BLOCK_SOURCE_BINDING_NOT_VIGENTE_OR_AMBIGUOUS'
  WHEN b.binding_policy_sha IS DISTINCT FROM g.current_sha
    OR nullif(b.read_facade_ref,'') IS NULL
    OR nullif(b.tenant_rule_ref,'') IS NULL
    OR nullif(b.schema_fingerprint,'') IS NULL
    OR b.schema_fingerprint IS DISTINCT FROM sc.current_fingerprint
    OR nullif(b.permission_code,'') IS NULL
    THEN 'BLOCK_SOURCE_CONTRACT_INCOMPLETE'
  WHEN c.jwt_auth_user_id IS NULL
    THEN 'BLOCK_AUTHENTICATED_ACTOR_REQUIRED'
  WHEN c.db_role IN ('postgres','service_role') OR c.session_role IN ('postgres','service_role')
    THEN 'BLOCK_PRIVILEGED_RUNTIME_IDENTITY'
  WHEN u.n<>1 THEN 'BLOCK_EXACT_USER_COMPANY_CONTEXT'
  WHEN a.n<>1 THEN 'BLOCK_COMPANY_ASSIGNMENT_NOT_VIGENTE'
  WHEN p.n<>1 THEN 'BLOCK_PERMISSION_NOT_VIGENTE'
  WHEN e.deny_count>0 THEN 'BLOCK_EXPLICIT_PERMISSION_DENY'
  WHEN e.allow_count<>1 THEN 'BLOCK_EXPLICIT_COMPANY_ALLOW_MISSING'
  ELSE 'PRECONDITIONS_MATCHED_NOT_READ_AUTHORIZED'
 END AS preflight_decision,
 sc.object_count AS source_object_count,
 b.schema_fingerprint IS NOT DISTINCT FROM sc.current_fingerprint AND
 nullif(b.schema_fingerprint,'') IS NOT NULL AS schema_fingerprint_verified,
 b.n AS binding_count,g.current_count=1 AND g.current_sha=i.expected_policy_sha AS policy_current,
 c.jwt_auth_user_id IS NOT NULL AS actor_present,
 u.n AS exact_user_company_count,
 a.n AS current_assignment_count,
 p.n AS vigente_permission_count,
 e.allow_count,e.deny_count
 FROM input i CROSS JOIN source_catalog sc CROSS JOIN governing_policy g CROSS JOIN binding_count b
 CROSS JOIN caller c CROSS JOIN chosen_user u CROSS JOIN scoped_assignment a
 CROSS JOIN eligible_permission p CROSS JOIN explicit_permission e
)
SELECT jsonb_build_object(
 'schema_version','LF_D1D2_B2B_SOURCE_PREFLIGHT_V1',
 'decision',preflight_decision,
 'policy_current',policy_current,
 'binding_count',binding_count,
 'source_object_count',source_object_count,
 'schema_fingerprint_verified',schema_fingerprint_verified,
 'actor_present',actor_present,
 'exact_user_company_count',exact_user_company_count,
 'assignment_count',current_assignment_count,
 'permission_count',vigente_permission_count,
 'allow_count',allow_count,
 'deny_count',deny_count,
 'read_authorized',false,
 'row_access_performed',false,
 'requires_separate_facade_readback',true,
 'effects_executed',false
) AS preflight
FROM decisions;

-- This query never grants read access. A separate authorized facade must
-- verify column fingerprint, filters, tenant, limits and execute as the
-- correct principal without bypassing RLS. Missing B2B ACL grants -> ERROR
-- is a DENY, not a reason to escalate database privileges.
