-- Synthetic RLS contract test: execute as one transaction after the
-- candidate migration. All fixtures are rolled back. Never a real user/JWT.
-- UUIDs and business codes reserved for synthetic security tests only.
INSERT INTO lf_ops.empresas(
 company_id,company_code,company_number,legal_name,trade_name,tax_id,
 authorization_status,operational_status,contact_name,contact_email)
VALUES
 ('a0000000-0000-4000-8000-000000000101','RLS_FIXTURE_COMPANY_A',990000101,
  'RLS Fixture A','RLS Fixture A','20999999001','APPROVED','ACTIVE',
  'RLS Synthetic Contact','rls-a@example.invalid'),
 ('a0000000-0000-4000-8000-000000000102','RLS_FIXTURE_COMPANY_B',990000102,
  'RLS Fixture B','RLS Fixture B','20999999002','APPROVED','ACTIVE',
  'RLS Synthetic Contact','rls-b@example.invalid');

INSERT INTO lf_ops.empresa_usuarios(
 user_id,auth_user_id,company_id,user_code,user_number,
 full_name,email,status,invitation_status)
VALUES(
 'a0000000-0000-4000-8000-000000000201',
 'a0000000-0000-4000-8000-000000000299',
 'a0000000-0000-4000-8000-000000000101',
 'RLS_FIXTURE_USER_A',990000201,
 'RLS Synthetic User','rls-user@example.invalid','ACTIVE','ACCEPTED');

INSERT INTO lf_ops.b2b_user_company_assignments(user_id,company_id,status)
VALUES(
 'a0000000-0000-4000-8000-000000000201',
 'a0000000-0000-4000-8000-000000000101','VIGENTE');

-- Test-only provisional promotion, rolled back with the entire transaction.
UPDATE lf_ops.permisos SET status='VIGENTE'
WHERE permission_code='B2B_LOAD_DETAIL_VIEW' AND status='CANDIDATO';

INSERT INTO lf_ops.b2b_user_company_permissions(
 user_id,company_id,permission_id,access_effect,status)
SELECT 'a0000000-0000-4000-8000-000000000201',
 'a0000000-0000-4000-8000-000000000101',p.permission_id,'ALLOW','VIGENTE'
FROM lf_ops.permisos p WHERE p.permission_code='B2B_LOAD_DETAIL_VIEW';

INSERT INTO lf_ops.cargas_lotes(
 load_id,company_id,load_code,load_number,state_id,
 load_name,load_type,template_version,status,approval_mode,idempotency_key)
VALUES(
 'a0000000-0000-4000-8000-000000000301',
 'a0000000-0000-4000-8000-000000000101',
 'RLS_FIXTURE_LOAD_A',990000301,1,'RLS Synthetic Load A','PAGO_UNICO',
 'V1','UPLOADED','SIN_APROBACION','rls-fixture-idempotency-A'),
(
 'a0000000-0000-4000-8000-000000000302',
 'a0000000-0000-4000-8000-000000000102',
 'RLS_FIXTURE_LOAD_B',990000302,1,'RLS Synthetic Load B','PAGO_UNICO',
 'V1','UPLOADED','SIN_APROBACION','rls-fixture-idempotency-B');

INSERT INTO lf_ops.cargas_archivos(
 file_id,load_id,file_code,file_number,file_role,file_name,
 mime_type,size_bytes,checksum_sha256,storage_object_path
) VALUES(
 'a0000000-0000-4000-8000-000000000401',
 'a0000000-0000-4000-8000-000000000301',
 'RLS_FIXTURE_FILE_A',990000401,'ORIGINAL','fixture-a.csv',
 'text/csv',10,repeat('a',64),'rls-fixture-a.csv'),
(
 'a0000000-0000-4000-8000-000000000402',
 'a0000000-0000-4000-8000-000000000302',
 'RLS_FIXTURE_FILE_B',990000402,'ORIGINAL','fixture-b.csv',
 'text/csv',10,repeat('b',64),'rls-fixture-b.csv');

-- One *synthetic* JWT subject, never proof of a signed session.
SELECT set_config('request.jwt.claim.sub',
 'a0000000-0000-4000-8000-000000000299',true);
SET LOCAL ROLE authenticated;
DO $check_allow$
BEGIN
 IF lf_ops.fn_b2b_can_read_load_company_v1('a0000000-0000-4000-8000-000000000101') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'SECURITY_TEST_ALLOW_HELPER_EXPECTED'; END IF;
 IF lf_ops.fn_b2b_can_read_load_company_v1('a0000000-0000-4000-8000-000000000102') IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'SECURITY_TEST_CROSS_COMPANY_HELPER_DENY_EXPECTED'; END IF;
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>1
 THEN RAISE EXCEPTION 'SECURITY_TEST_ROW_RLS_LOADS_EXPECTED_ONE'; END IF;
 IF (SELECT count(*) FROM lf_ops.cargas_archivos)<>1
 THEN RAISE EXCEPTION 'SECURITY_TEST_ROW_RLS_FILES_EXPECTED_ONE'; END IF;
 IF (SELECT load_code FROM lf_ops.cargas_lotes LIMIT 1)<>'RLS_FIXTURE_LOAD_A'
 THEN RAISE EXCEPTION 'SECURITY_TEST_WRONG_LOAD_VISIBLE'; END IF;
 IF pg_catalog.has_column_privilege('authenticated','lf_ops.cargas_archivos','storage_object_path','SELECT')
 THEN RAISE EXCEPTION 'SECURITY_TEST_STORAGE_PATH_EXPOSED'; END IF;
 IF pg_catalog.has_column_privilege('authenticated','lf_ops.cargas_lotes','policy_snapshot','SELECT')
 THEN RAISE EXCEPTION 'SECURITY_TEST_POLICY_SNAPSHOT_EXPOSED'; END IF;
 IF pg_catalog.has_table_privilege('authenticated','lf_ops.cargas_lotes','INSERT')
   OR pg_catalog.has_table_privilege('authenticated','lf_ops.cargas_lotes','UPDATE')
   OR pg_catalog.has_table_privilege('authenticated','lf_ops.cargas_lotes','DELETE')
 THEN RAISE EXCEPTION 'SECURITY_TEST_WRITE_PRIVILEGE_LEAK'; END IF;
END $check_allow$;

RESET ROLE;
UPDATE lf_ops.b2b_user_company_permissions
SET access_effect='DENY'
WHERE user_id='a0000000-0000-4000-8000-000000000201';
SET LOCAL ROLE authenticated;
DO $check_deny$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
  OR (SELECT count(*) FROM lf_ops.cargas_archivos)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_EXPLICIT_DENY_NOT_EFFECTIVE'; END IF;
END $check_deny$;

RESET ROLE;
UPDATE lf_ops.b2b_user_company_permissions
SET access_effect='ALLOW' WHERE user_id='a0000000-0000-4000-8000-000000000201';
UPDATE lf_ops.b2b_user_company_assignments
SET status='INACTIVO' WHERE user_id='a0000000-0000-4000-8000-000000000201';
SET LOCAL ROLE authenticated;
DO $check_assignment$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_INACTIVE_ASSIGNMENT_NOT_EFFECTIVE'; END IF;
END $check_assignment$;

RESET ROLE;
UPDATE lf_ops.b2b_user_company_assignments SET status='VIGENTE'
WHERE user_id='a0000000-0000-4000-8000-000000000201';
UPDATE lf_ops.permisos SET status='CANDIDATO'
WHERE permission_code='B2B_LOAD_DETAIL_VIEW';
SET LOCAL ROLE authenticated;
DO $check_permission$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_CANDIDATE_PERMISSION_NOT_EFFECTIVE'; END IF;
END $check_permission$;
RESET ROLE;

-- Additional reversible denial cases: suspended company, disabled user, missing JWT.
UPDATE lf_ops.permisos SET status='VIGENTE'
WHERE permission_code='B2B_LOAD_DETAIL_VIEW';
UPDATE lf_ops.empresas SET operational_status='SUSPENDED'
WHERE company_id='a0000000-0000-4000-8000-000000000101';
SET LOCAL ROLE authenticated;
DO $check_suspended$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_SUSPENDED_COMPANY_NOT_DENIED'; END IF;
END $check_suspended$;
RESET ROLE;
UPDATE lf_ops.empresas SET operational_status='ACTIVE'
WHERE company_id='a0000000-0000-4000-8000-000000000101';
UPDATE lf_ops.empresa_usuarios SET status='DISABLED'
WHERE user_id='a0000000-0000-4000-8000-000000000201';
SET LOCAL ROLE authenticated;
DO $check_disabled$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_DISABLED_USER_NOT_DENIED'; END IF;
END $check_disabled$;
RESET ROLE;
UPDATE lf_ops.empresa_usuarios SET status='ACTIVE'
WHERE user_id='a0000000-0000-4000-8000-000000000201';
SELECT set_config('request.jwt.claim.sub','',true);
SET LOCAL ROLE authenticated;
DO $check_no_jwt$
BEGIN
 IF (SELECT count(*) FROM lf_ops.cargas_lotes)<>0
 THEN RAISE EXCEPTION 'SECURITY_TEST_NO_JWT_NOT_DENIED'; END IF;
END $check_no_jwt$;
RESET ROLE;
DO $check_anonymous$
BEGIN
 IF pg_catalog.has_table_privilege('anon','lf_ops.cargas_lotes','SELECT')
 OR pg_catalog.has_column_privilege('anon','lf_ops.cargas_lotes','load_id','SELECT')
 OR pg_catalog.has_column_privilege('anon','lf_ops.cargas_archivos','file_name','SELECT')
 THEN RAISE EXCEPTION 'SECURITY_TEST_ANON_ACCESS_NOT_DENIED'; END IF;
 IF (SELECT count(*) FROM pg_catalog.pg_class
      WHERE oid IN ('lf_ops.cargas_lotes'::regclass,
                    'lf_ops.cargas_archivos'::regclass)
        AND relrowsecurity AND relforcerowsecurity)<>2
 THEN RAISE EXCEPTION 'SECURITY_TEST_FORCE_RLS_LOST'; END IF;
END $check_anonymous$;

-- test security result is the successful execution of all preceding assertions
SELECT 'PASS' AS structural_rls_contract,
  'positive, cross-company, DENY, inactive assignment, candidate permission, suspended company, disabled user, absent JWT, anon, column and DML checks' AS coverage,
  (SELECT count(*) FROM lf_ops.empresas WHERE company_code LIKE 'RLS_FIXTURE_%') AS fixtures_within_transaction;
