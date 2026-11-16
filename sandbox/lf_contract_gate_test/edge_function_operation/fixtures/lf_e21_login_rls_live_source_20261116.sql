-- Exact live PostgreSQL function bodies extracted from Supabase on 2026-11-16.
-- AUTH-001/002 PG17/18 fixture; no synthetic implementation of tenant auth logic.
CREATE OR REPLACE FUNCTION lf_ops.b2b_current_company_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select u.company_id
  from lf_ops.empresa_usuarios u
  where u.auth_user_id = auth.uid()
    and u.status = 'ACTIVE'
  limit 1
$function$;

CREATE OR REPLACE FUNCTION lf_ops.b2b_current_user_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select u.user_id
  from lf_ops.empresa_usuarios u
  where u.auth_user_id = auth.uid()
    and u.status = 'ACTIVE'
  limit 1
$function$;

CREATE OR REPLACE FUNCTION lf_ops.fn_b2b_can_read_load_company_v1(p_company_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
SELECT
  p_company_id IS NOT NULL
  AND auth.uid() IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM lf_ops.empresa_usuarios u
    JOIN lf_ops.empresas c ON c.company_id = u.company_id
    JOIN lf_ops.b2b_user_company_assignments a
      ON a.user_id=u.user_id AND a.company_id=c.company_id
      AND a.status='VIGENTE'
    JOIN lf_ops.permisos p
      ON p.permission_code='B2B_LOAD_DETAIL_VIEW'
      AND p.resource_type='LOAD'
      AND p.action_code='VIEW_DETAIL'
      AND p.status='VIGENTE'
    JOIN lf_ops.b2b_user_company_permissions allow_p
      ON allow_p.user_id=u.user_id
      AND allow_p.company_id=c.company_id
      AND allow_p.permission_id=p.permission_id
      AND allow_p.status='VIGENTE' AND allow_p.access_effect='ALLOW'
    WHERE u.auth_user_id=auth.uid()
      AND u.status='ACTIVE'
      AND u.company_id=p_company_id
      AND c.authorization_status='APPROVED'
      AND c.operational_status='ACTIVE'
      AND NOT EXISTS (
         SELECT 1
         FROM lf_ops.b2b_user_company_permissions deny_p
         WHERE deny_p.user_id=u.user_id
           AND deny_p.company_id=c.company_id
           AND deny_p.permission_id=p.permission_id
           AND deny_p.status='VIGENTE' AND deny_p.access_effect='DENY'
      )
  );
$function$;
