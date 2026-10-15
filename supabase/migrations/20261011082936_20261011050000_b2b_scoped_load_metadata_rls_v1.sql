-- LF B2B / D2: strictly scoped SELECT on loads and their metadata files.
-- Changes only listed objects; existing all-operations false policies and FORCE RLS remain.
-- Any approved read requires verified Auth JWT, active B2B user, approved company,
-- VIGENTE exact assignment, VIGENTE VIEW_DETAIL permission, VIGENTE user ALLOW,
-- and no VIGENTE user DENY (DENY wins). Missing references fail closed.
-- This SECURITY DEFINER helper may inspect only the existing *authorization
-- catalogs*, which deny direct client SELECT. It never selects business rows.
CREATE OR REPLACE FUNCTION lf_ops.fn_b2b_can_read_load_company_v1(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn$
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
$fn$;
-- No other function may grant access by calling with an arbitrary company.
-- Its output alone is not a business-read receipt.
REVOKE ALL ON FUNCTION lf_ops.fn_b2b_can_read_load_company_v1(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION lf_ops.fn_b2b_can_read_load_company_v1(uuid)
  TO authenticated;

-- No broad GRANT SELECT(*): omit original policy snapshot, object path,
-- checksum, idempotency tokens, company user identifiers and other internals.
GRANT SELECT(
  load_id, company_id, source_file_id, load_code, load_name, load_type,
  template_version, status, approval_mode, total_records, valid_count,
  observed_count, rejected_count, duplicate_count, processed_count,
  not_processed_count, last_error_category, created_at, updated_at
) ON lf_ops.cargas_lotes TO authenticated;

GRANT SELECT(
  file_id, load_id, file_code, file_role, file_name, mime_type,
  size_bytes, template_version_detected, malware_scan_status, uploaded_at
) ON lf_ops.cargas_archivos TO authenticated;

-- New permissive SELECT policy joins the old PERMISSIVE false guard by OR;
-- operations other than SELECT remain denied, with no DML grants.
CREATE POLICY lf_b2b_load_scoped_read_v1 ON lf_ops.cargas_lotes
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    company_id = (SELECT lf_ops.b2b_current_company_id())
    AND lf_ops.fn_b2b_can_read_load_company_v1(company_id)
  );

-- File metadata is visible ONLY if the parent load is visible through the
-- existing RLS-protected loads table; no bypass business-read helper.
CREATE POLICY lf_b2b_load_file_scoped_read_v1 ON lf_ops.cargas_archivos
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM lf_ops.cargas_lotes l
      WHERE l.load_id = cargas_archivos.load_id
    )
  );
-- Intentionally retain FORCE ROW LEVEL SECURITY on both business tables.
COMMENT ON FUNCTION lf_ops.fn_b2b_can_read_load_company_v1(uuid)
IS 'Only authenticated B2B actor/company/active permission gate; no business row read or evidence attestation; policy must additionally enforce current-company matching.';
