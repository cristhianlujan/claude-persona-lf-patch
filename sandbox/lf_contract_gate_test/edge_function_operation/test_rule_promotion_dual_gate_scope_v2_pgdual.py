"""LF dual-gate v2 against REAL migrations, PG17.6/18.7 ROLLBACK.
No live Supabase connections, no state mutations, no owner/Step70 claims.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
V1 = ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_rule_promotion_v1_live_defs_20261114.sql"
MIG1 = ROOT / "supabase/migrations/20261114193000_lf_rule_promotion_dual_gate_scope_evidence_v2.sql"
MIG2 = ROOT / "supabase/migrations/20261114193100_lf_rule_scope_wrong_screen_gate_ekb_v1.sql"
EXPECTED_MD5 = "92e8025b70d17e3de7da7206795ed73d"

FIXTURE = r"""
CREATE ROLE service_role;
CREATE ROLE authenticated;
CREATE ROLE anon;
CREATE SCHEMA lf_ops;
CREATE SCHEMA programacion;
CREATE TABLE lf_ops.reglas (
 id integer PRIMARY KEY, codigo text UNIQUE, estado text NOT NULL,
 categoria text,valor_config jsonb,es_transversal boolean,
 razon text,pendiente_decision boolean,pendiente_detalle text);
CREATE TABLE lf_ops.reglas_pantallas (regla_id integer,pantalla_id integer);
CREATE TABLE lf_ops.real_business_table (id int);
CREATE TABLE lf_ops.politicas_seguridad (policy_code text);
INSERT INTO lf_ops.politicas_seguridad VALUES ('SEC-B2B-MFA');
CREATE TABLE public.lf_operation_contracts (
 operation_code text, contract_sha text);
INSERT INTO public.lf_operation_contracts VALUES ('EJECUCION_PERFIL_LF','sha-catalog');
CREATE TABLE public.lf_error_knowledge (
 id uuid,codigo text,categoria text,titulo text,descripcion text,
 causa_raiz text,patron text,prevencion text,validacion text,
 severidad text,frecuencia int,primera_vez timestamptz,
 ultima_vez timestamptz,lote_origen text,pr text,estado text,
 evidencia text,created_at timestamptz,updated_at timestamptz,
 lifecycle_phase text,consumer_role text[],root_cause_family text,
 detectability text,source_context text,source_ref text);
CREATE FUNCTION public.lf_rule_promotion_request_v1(text,text,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION public.sample_real_backend_handler()
 RETURNS boolean LANGUAGE sql STABLE AS $$SELECT true$$;
INSERT INTO lf_ops.reglas VALUES
 (101,'BACKEND_TABLE','CANDIDATO','INTEGRITY',
   '{"tabla_afectada":"lf_ops.real_business_table"}',false,'backend table',false,NULL),
 (102,'BACKEND_UNKNOWN','CANDIDATO','SECURITY',
   '{"scope_hint":"BACKEND"}',false,'not bound yet',false,NULL),
 (103,'ONE_SCREEN','CANDIDATO','UX',
   '{"k":"one"}',false,'screen link',false,NULL),
 (104,'TRANSVERSAL','CANDIDATO','GOVERNANCE',
   '{"alcance":"all governed LF workflows"}',true,'transversal scope',false,NULL),
 (105,'PENDING_OWNER','CANDIDATO','SECURITY',
   '{"k":"pending_owner"}',false,'requires owner',true,'owner decision'),
 (106,'FIVE_SCREENS','CANDIDATO','UX',
   '{"k":"five"}',false,'5+ screen',false,NULL),
 (107,'BACKEND_FUNCTION','CANDIDATO','SECURITY',
   '{"scope_evidence_v2":{"object_type":"FUNCTION","object_ref":"public.sample_real_backend_handler","evidence_ref":"supabase://pg_proc/sample_real_backend_handler"}}',
   false,'function bound',false,NULL),
 (108,'BACKEND_PROCESS','CANDIDATO','GOVERNANCE',
   '{"scope_evidence_v2":{"object_type":"PROCESS","object_ref":"EJECUCION_PERFIL_LF","evidence_ref":"supabase://lf_operation_contracts/EJECUCION_PERFIL_LF"}}',
   false,'process bound',false,NULL),
 (109,'BACKEND_POLICY','CANDIDATO','SECURITY',
   '{"scope_evidence_v2":{"object_type":"POLICY","object_ref":"SEC-B2B-MFA","evidence_ref":"supabase://lf_ops.politicas_seguridad/SEC-B2B-MFA"}}',
   false,'policy bound',false,NULL),
 (110,'BACKEND_EDGE_UNVERIFIED','CANDIDATO','SECURITY',
   '{"scope_evidence_v2":{"object_type":"EDGE_FUNCTION","object_ref":"fake-edge","evidence_ref":"some-freeform-text"}}',
   false,'edge not independently verified',false,NULL),
 (111,'PENDING_MARKER','CANDIDATO','SECURITY',
   '{"binding":"PENDING_CANONICAL_IDP"}',false,'pending metadata',false,NULL),
 (112,'BACKEND_REF_NOT_REAL','CANDIDATO','SECURITY',
   '{"scope_evidence_v2":{"object_type":"TABLE","object_ref":"public.not_real","evidence_ref":"supabase://public.not_real"}}',
   false,'nonexistent object',false,NULL),
 (113,'LEGACY_VIGENTE','VIGENTE','GOVERNANCE',
   '{"k":"legacy"}',false,'legacy source',false,NULL);
INSERT INTO lf_ops.reglas_pantallas VALUES
 (103,1),
 (105,1),(105,2),(105,3),(105,4),(105,5),
 (106,1),(106,2),(106,3),(106,4),(106,5),
 (111,1);
"""

def inside_transaction(sql: str) -> str:
    assert "\nBEGIN;\n" in sql and "\nCOMMIT;" in sql
    return sql.split("\nBEGIN;\n", 1)[1].rsplit("\nCOMMIT;", 1)[0]

class DualGatePgDual(unittest.TestCase):
    def test_pg17_pg18_rollback_and_semantics(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        src1, src2 = MIG1.read_text("utf-8"), MIG2.read_text("utf-8")
        legacy = V1.read_text("utf-8")
        self.assertIn("USED_BY_ENOUGH_SCREENS", legacy)
        self.assertNotIn("UPDATE lf_ops.reglas", src1+src2)
        self.assertNotIn("INSERT INTO lf_ops.reglas_pantallas", src1+src2)
        self.assertNotIn("UPDATE lf_ops.politicas_seguridad", src1+src2)
        for version in ("17.6","18.7"):
            with self.subTest(pg=version):
                name = "lf-dual-gate-" + uuid.uuid4().hex[:10]
                start = subprocess.run(
                    ["docker","run","-d","--rm","--name",name,
                     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(start.returncode,0,start.stderr)
                try:
                    ready = None
                    for _ in range(100):
                        ready = subprocess.run(["docker","exec",name,"pg_isready",
                           "-U","postgres"],capture_output=True,timeout=8)
                        logs = subprocess.run(["docker","logs",name],
                           capture_output=True,text=True,timeout=8)
                        if ready.returncode==0 and (
                         "PostgreSQL init process complete; ready for start up."
                          in (logs.stdout+logs.stderr)): break
                        time.sleep(.7)
                    self.assertEqual(ready.returncode,0)
                    def psql(query: str):
                        return subprocess.run(
                           ["docker","exec","-i",name,"psql","-X","-A","-t",
                            "-U","postgres","-d","postgres",
                            "-v","ON_ERROR_STOP=1"],
                           input=query,capture_output=True,text=True,timeout=120)
                    setup = psql(FIXTURE+"\n"+legacy+"\n")
                    self.assertEqual(setup.returncode,0,setup.stderr[-4000:])
                    baseline = psql(
                        "SELECT md5(pg_get_functiondef("
                        "'programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)'::regprocedure));")
                    self.assertEqual(baseline.returncode,0,baseline.stderr)
                    self.assertIn(EXPECTED_MD5,baseline.stdout)
                    checks = r"""
SELECT 'V2='||codigo||':'||vigente_verdict||':'||scope_route
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2() v
 JOIN lf_ops.reglas r ON r.id=v.regla_id ORDER BY regla_id;
SELECT 'ONE_SCREEN_POLICY='||policy_verdict
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(103);
SELECT 'TRANSVERSAL_POLICY='||policy_verdict
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(104);
SELECT 'PENDING_OWNER='||vigente_verdict||':'||
 (criteria->>'NO_PENDING_DECISION')
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(105);
SELECT 'FIVE_FAST='||fast_track::text||':STEP70='||
 step70_independent_required::text
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(106);
SELECT 'EDGE_CONTINUE='||continuation_allowed::text
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(110);
SELECT 'EKB='||count(*) FROM public.lf_error_knowledge
 WHERE codigo='LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001';
SELECT 'V1_STILL='||md5(pg_get_functiondef(
 'programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)'::regprocedure));
SELECT 'SERVICE_EXECUTE='||
 has_function_privilege('service_role','public.lf_rule_promotion_verdicts_readonly_v2(bigint)','EXECUTE')::text;
SELECT 'ANON_DENIED='||
 (NOT has_function_privilege('anon','public.lf_rule_promotion_verdicts_readonly_v2(bigint)','EXECUTE'))::text;
"""
                    query = ("BEGIN;\n"+inside_transaction(src1)+"\n"+
                             inside_transaction(src2)+"\n"+checks+
                             "\nROLLBACK;\n"
                             "SELECT 'V2_ROLLED_BACK='||("
                             "to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)') IS NULL)::text;\n"
                             "SELECT 'EKB_AFTER='||count(*) FROM public.lf_error_knowledge;\n"
                             "SELECT 'RULES_AFTER='||count(*) FROM lf_ops.reglas;\n")
                    result=psql(query)
                    self.assertEqual(result.returncode,0,result.stderr[-5000:])
                    for val in (
                      "V2=BACKEND_TABLE:PASS:BACKEND_OBJECT_VERIFIED",
                      "V2=BACKEND_UNKNOWN:REVIEW_SCOPE:SCOPE_REVIEW",
                      "V2=ONE_SCREEN:PASS:SCREEN_LINK",
                      "V2=TRANSVERSAL:PASS:TRANSVERSAL_DECLARED",
                      "V2=PENDING_OWNER:HOLD_CONTENT_FINDINGS:FAST_5_PLUS",
                      "V2=FIVE_SCREENS:PASS:FAST_5_PLUS",
                      "V2=BACKEND_FUNCTION:PASS:BACKEND_OBJECT_VERIFIED",
                      "V2=BACKEND_PROCESS:PASS:BACKEND_OBJECT_VERIFIED",
                      "V2=BACKEND_POLICY:PASS:BACKEND_OBJECT_VERIFIED",
                      "V2=BACKEND_EDGE_UNVERIFIED:REVIEW_SCOPE:SCOPE_REVIEW",
                      "V2=PENDING_MARKER:HOLD_CONTENT_FINDINGS:SCREEN_LINK",
                      "V2=BACKEND_REF_NOT_REAL:REVIEW_SCOPE:SCOPE_REVIEW",
                      "ONE_SCREEN_POLICY=REVIEW_POLICY_BREADTH",
                      "TRANSVERSAL_POLICY=PASS_BREADTH",
                      "PENDING_OWNER=HOLD_CONTENT_FINDINGS:false",
                      "FIVE_FAST=true:STEP70=true",
                      "EDGE_CONTINUE=true",
                      "EKB=1","V1_STILL="+EXPECTED_MD5,
                      "SERVICE_EXECUTE=true","ANON_DENIED=true",
                      "V2_ROLLED_BACK=true","EKB_AFTER=0","RULES_AFTER=13"):
                        self.assertIn(val,result.stdout,val+"\n"+result.stdout[-5000:])
                    print("PASS_DUAL_GATE_SCOPE_V2_PG"+version+
                          "_BACKEND_SCREEN_TRANSVERSAL_PENDING_FAST_POLICY_ROLLBACK")
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,timeout=30)
