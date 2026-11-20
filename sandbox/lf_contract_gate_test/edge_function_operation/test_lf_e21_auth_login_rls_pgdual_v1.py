"""E21 Batch 1: REAL DB behavioral probes of tenant load-access and trusted-device RLS.
Behavioral scope: RLS and auth.uid()-bound DB enforcement, not complete Spring Boot/OIDC login.
DO NOT record 40-point PASS for any broad rule from these partial probes.
"""
from pathlib import Path
import subprocess, shutil, time, unittest, uuid

ROOT=Path(__file__).resolve().parents[3]
SOURCE=(Path(__file__).parent/"fixtures/lf_e21_login_rls_live_source_20261116.sql").read_text(encoding="utf-8")
DB=r"""
CREATE SCHEMA auth;
CREATE SCHEMA lf_ops;
CREATE ROLE authenticated NOLOGIN;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $uid$
SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$uid$;
CREATE TABLE lf_ops.empresa_usuarios (
  user_id uuid PRIMARY KEY, auth_user_id uuid, company_id uuid, status text
);
CREATE TABLE lf_ops.empresas (
  company_id uuid PRIMARY KEY, authorization_status text, operational_status text
);
CREATE TABLE lf_ops.b2b_user_company_assignments (
  user_id uuid,company_id uuid,status text
);
CREATE TABLE lf_ops.permisos (
  permission_id bigint PRIMARY KEY, permission_code text,
  resource_type text,action_code text,status text
);
CREATE TABLE lf_ops.b2b_user_company_permissions (
  user_id uuid,company_id uuid,permission_id bigint,status text,access_effect text
);
CREATE TABLE lf_ops.cargas_lotes (
  load_id bigint PRIMARY KEY,company_id uuid NOT NULL
);
CREATE TABLE lf_ops.dispositivos_confiables (
  trusted_device_id uuid PRIMARY KEY, user_id uuid, company_id uuid,
  token_hash text,revoked_at timestamptz
);
GRANT USAGE ON SCHEMA auth,lf_ops TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT SELECT ON lf_ops.cargas_lotes,lf_ops.dispositivos_confiables TO authenticated;
-- Real pg_policies source, not a hand-invented permissive variant.
ALTER TABLE lf_ops.cargas_lotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.dispositivos_confiables ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.cargas_lotes AS PERMISSIVE FOR ALL
  TO public USING (false) WITH CHECK (false);
CREATE POLICY lf_b2b_load_scoped_read_v1 ON lf_ops.cargas_lotes AS PERMISSIVE FOR SELECT
  TO public USING (
    company_id = (SELECT lf_ops.b2b_current_company_id())
    AND lf_ops.fn_b2b_can_read_load_company_v1(company_id)
  );
CREATE POLICY deny_direct_client_access ON lf_ops.dispositivos_confiables AS PERMISSIVE FOR ALL
  TO public USING (false) WITH CHECK (false);
INSERT INTO lf_ops.empresas VALUES
 ('00000000-0000-0000-0000-000000000001','APPROVED','ACTIVE'),
 ('00000000-0000-0000-0000-000000000002','APPROVED','ACTIVE');
INSERT INTO lf_ops.empresa_usuarios VALUES
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000001','ACTIVE'),
 ('00000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000002','ACTIVE');
INSERT INTO lf_ops.b2b_user_company_assignments VALUES
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','VIGENTE');
INSERT INTO lf_ops.permisos VALUES
 (777,'B2B_LOAD_DETAIL_VIEW','LOAD','VIEW_DETAIL','VIGENTE');
INSERT INTO lf_ops.b2b_user_company_permissions VALUES
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001',777,'VIGENTE','ALLOW');
INSERT INTO lf_ops.cargas_lotes VALUES
 (101,'00000000-0000-0000-0000-000000000001'),
 (102,'00000000-0000-0000-0000-000000000002');
INSERT INTO lf_ops.dispositivos_confiables VALUES
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','sha256-test',NULL);
"""
TXN=r"""
BEGIN;
-- User A, bound JWT, can read one A row; cannot read B's row.
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT 'AUTH001_POSITIVE_ALLOW='||count(*) FROM lf_ops.cargas_lotes;
SELECT 'AUTH002_CROSS_TENANT_DENIED='||count(*) FROM lf_ops.cargas_lotes WHERE load_id=102;
-- Existing trusted device is NEVER directly client-readable.
SELECT 'AUTH039_CLIENT_DEVICE_DENIED='||count(*) FROM lf_ops.dispositivos_confiables;
RESET ROLE;
-- Explicit deny overrides an otherwise valid allow.
INSERT INTO lf_ops.b2b_user_company_permissions VALUES
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001',777,'VIGENTE','DENY');
SET LOCAL ROLE authenticated;
SELECT 'AUTH001_DENY_PRECEDENCE='||count(*) FROM lf_ops.cargas_lotes;
RESET ROLE;
DELETE FROM lf_ops.b2b_user_company_permissions WHERE access_effect='DENY';
-- Disabled user does not receive an operational session's load permission.
UPDATE lf_ops.empresa_usuarios SET status='DISABLED' WHERE user_id='00000000-0000-0000-0000-000000000011';
SET LOCAL ROLE authenticated;
SELECT 'AUTH001_DISABLED_DENIED='||count(*) FROM lf_ops.cargas_lotes;
RESET ROLE;
UPDATE lf_ops.empresa_usuarios SET status='ACTIVE' WHERE user_id='00000000-0000-0000-0000-000000000011';
UPDATE lf_ops.empresas SET operational_status='SUSPENDED' WHERE company_id='00000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT 'AUTH002_COMPANY_SUSPENDED_DENIED='||count(*) FROM lf_ops.cargas_lotes;
RESET ROLE;
UPDATE lf_ops.empresas SET operational_status='ACTIVE' WHERE company_id='00000000-0000-0000-0000-000000000001';
UPDATE lf_ops.b2b_user_company_assignments SET status='CANDIDATO' WHERE company_id='00000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT 'AUTH002_ASSIGNMENT_NOT_CURRENT_DENIED='||count(*) FROM lf_ops.cargas_lotes;
RESET ROLE;
UPDATE lf_ops.b2b_user_company_assignments SET status='VIGENTE';
-- No JWT grants no access, even for public/authenticated role.
SET LOCAL request.jwt.claim.sub='';
SET LOCAL ROLE authenticated;
SELECT 'AUTH001_NO_JWT_DENIED='||count(*) FROM lf_ops.cargas_lotes;
RESET ROLE;
ROLLBACK;
SELECT 'E21_ROLLBACK_NO_RESIDUE='||count(*) FROM lf_ops.b2b_user_company_permissions
 WHERE access_effect='DENY';
"""
class LoginBehaviorPGDual(unittest.TestCase):
 def test_live_rls_semantics_negative_positive_pg17_pg18(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertIn("fn_b2b_can_read_load_company_v1",SOURCE)
  for version in ("17.6","18.7"):
   with self.subTest(version=version):
    name="lf-e21-rls-"+uuid.uuid4().hex[:10]
    p=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
       capture_output=True,text=True,timeout=180)
    self.assertEqual(p.returncode,0,p.stderr[-2000:])
    try:
     for _ in range(90):
      status=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if status.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(status.returncode,0,"PG_NOT_READY")
     def query(sql):
      x=subprocess.run(["docker","exec","-i",name,"psql",
         "-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
         input=sql,capture_output=True,text=True,timeout=180)
      self.assertEqual(x.returncode,0,x.stderr[-4200:]+"\n"+x.stdout[-2200:])
      return x.stdout,x.stderr
     setup_prefix,setup_policies=DB.split("-- Real pg_policies source",1)
     query(setup_prefix+"\n"+SOURCE+"\n-- Real pg_policies source"+setup_policies)
     output,_=query(TXN)
     for marker in (
      "AUTH001_POSITIVE_ALLOW=1",
      "AUTH002_CROSS_TENANT_DENIED=0",
      "AUTH039_CLIENT_DEVICE_DENIED=0",
      "AUTH001_DENY_PRECEDENCE=0",
      "AUTH001_DISABLED_DENIED=0",
      "AUTH002_COMPANY_SUSPENDED_DENIED=0",
      "AUTH002_ASSIGNMENT_NOT_CURRENT_DENIED=0",
      "AUTH001_NO_JWT_DENIED=0",
      "E21_ROLLBACK_NO_RESIDUE=0",
     ):
      self.assertIn(marker,output,marker+"\n"+output[-2500:])
     print("PASS_E21_ACTUAL_DB_BEHAVIOR_PG"+version+"_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)

if __name__=="__main__": unittest.main()
