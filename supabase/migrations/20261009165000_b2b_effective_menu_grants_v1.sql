-- B2B S08 candidate authority resolver. No user-provided company/group ID.
-- AUTH-001: USER_DENY > USER_ALLOW > PROFILE_ALLOW > DEFAULT_DENY.
-- SCOPE-002/003: present SINGLE-company membership only; multi-company
-- scope must be separately materialized and certified before scope switching.
-- All grant sources (including shell/screen) must be VIGENTE, never CANDIDATO.
-- This is a proposal: do not connect to operational runtime until PG-01 admission.
CREATE OR REPLACE FUNCTION lf_ops.b2b_effective_menu_grants_v1()
RETURNS TABLE(permission_code text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $b2b_grants$
WITH subject AS (
 SELECT u.user_id
 FROM lf_ops.empresa_usuarios AS u
 JOIN lf_ops.empresas AS e ON e.company_id=u.company_id
 WHERE u.auth_user_id=auth.uid()
   AND u.status='ACTIVE'
   AND e.authorization_status='APPROVED'
   AND e.operational_status='ACTIVE'
   AND (u.mfa_required IS NOT TRUE OR auth.jwt()->>'aal'='aal2')
   AND EXISTS (
     SELECT 1 FROM lf_ops.app_shells a
     WHERE a.app_shell_code='B2B_APP_SHELL' AND a.status='VIGENTE'
   )
), bound_menu AS (
 SELECT DISTINCT mp.permission_code
 FROM lf_ops.menu_items_permisos mp
 JOIN lf_ops.menu_items mi ON mi.menu_item_code=mp.menu_item_code
 JOIN lf_ops.rutas r ON r.menu_item_code=mi.menu_item_code
 JOIN lf_ops.pantallas sc ON sc.id=r.pantalla_id
 JOIN lf_ops.pantallas_permisos sp
   ON sp.pantalla_id=sc.id AND sp.permission_code=mp.permission_code
 JOIN lf_ops.permisos perm ON perm.permission_code=mp.permission_code
 WHERE mi.menu_item_code LIKE 'B2B\_MENU\_%' ESCAPE '\'
   AND mi.menu_item_code NOT LIKE 'B2B\_MENU\_ADMIN\_%' ESCAPE '\'
   AND mi.status='VIGENTE'
   AND mi.is_visible IS TRUE AND mi.is_enabled IS TRUE
   AND mp.status='VIGENTE' AND mp.access_effect='ALLOW'
   AND r.status='VIGENTE' AND r.authentication_required IS TRUE
   AND sc.estado='VIGENTE' AND sc.activa IS TRUE
   AND sp.status='VIGENTE' AND sp.access_effect='ALLOW'
   AND perm.status='VIGENTE'
)
SELECT DISTINCT bm.permission_code
FROM subject sub CROSS JOIN bound_menu bm
WHERE NOT EXISTS (
 SELECT 1 FROM lf_ops.empresa_usuarios_permisos up
 WHERE up.user_id=sub.user_id AND up.permission_code=bm.permission_code
   AND up.status='VIGENTE' AND up.access_effect='DENY'
)
AND (
 EXISTS (
   SELECT 1 FROM lf_ops.empresa_usuarios_permisos up
   WHERE up.user_id=sub.user_id AND up.permission_code=bm.permission_code
     AND up.status='VIGENTE' AND up.access_effect='ALLOW'
 ) OR EXISTS (
   SELECT 1 FROM lf_ops.empresa_usuarios_perfiles upl
   JOIN lf_ops.perfiles pf ON pf.profile_code=upl.profile_code
   JOIN lf_ops.perfiles_permisos pp ON pp.profile_code=pf.profile_code
   WHERE upl.user_id=sub.user_id AND upl.status='VIGENTE'
     AND pf.status='VIGENTE' AND pf.is_active IS TRUE
     AND pp.status='VIGENTE' AND pp.access_effect='ALLOW'
     AND pp.permission_code=bm.permission_code
 )
)
ORDER BY bm.permission_code
$b2b_grants$;
REVOKE ALL ON FUNCTION lf_ops.b2b_effective_menu_grants_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lf_ops.b2b_effective_menu_grants_v1() TO authenticated;
