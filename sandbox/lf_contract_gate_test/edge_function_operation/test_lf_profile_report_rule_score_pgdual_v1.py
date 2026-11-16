"""Step80 rule-score report: PG17/18, hard blocks, routing, negative drift, rollback."""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = list((ROOT / "supabase/migrations").glob("*_lf_profile_report_rule_score_remediation_v1.sql"))
BASE = r"""
CREATE SCHEMA lf_ops;
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE lf_ops.pantallas (id integer PRIMARY KEY,codigo text NOT NULL);
CREATE TABLE lf_ops.reglas (
 id integer PRIMARY KEY,codigo text NOT NULL,estado text NOT NULL,
 categoria text NOT NULL,pendiente_decision boolean NOT NULL,
 pendiente_detalle text
);
CREATE TABLE lf_ops.reglas_pantallas (regla_id integer,pantalla_id integer);
CREATE TABLE lf_ops.regla_behavior_tests (
 regla_codigo text,pg17 text,pg18 text,ci_run text
);
CREATE OR REPLACE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
RETURNS jsonb LANGUAGE sql AS $$SELECT '[]'::jsonb$$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1(p_execution_id text,p_rule_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
 r record;
 hard_block boolean;
 points integer;
 blocked_categories CONSTANT text[]:=ARRAY['LEGAL','APPROVAL','OFERTAS_CUOTAS','AUTH','PRIVACY','PAGOS'];
BEGIN
 SELECT codigo,categoria,pendiente_decision INTO r FROM lf_ops.reglas WHERE codigo=p_rule_code;
 hard_block:=coalesce(r.pendiente_decision,true) OR r.categoria=ANY(blocked_categories)
    OR p_rule_code LIKE '%INSTALLMENT%';
 points:=CASE WHEN p_rule_code='B2B-RULE-AUTH-047' THEN 0
              WHEN p_rule_code='B2B-RULE-AUTH-022' THEN 95 ELSE 20 END;
 RETURN jsonb_build_object('score',points,
  'A',CASE WHEN points=95 THEN 40 ELSE 0 END,
  'B',CASE WHEN points=95 THEN 30 ELSE 0 END,
  'C',CASE WHEN points=0 THEN 0 ELSE 20 END,
  'D',CASE WHEN points=95 THEN 5 ELSE 0 END,
  'hard_block',hard_block,
  'decision',CASE WHEN points>=85 AND hard_block THEN 'MANUAL'
                  WHEN points>=85 THEN 'AUTO' ELSE 'BLOCKED' END);
END $f$;
"""
BAD_REPORT=r"""
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(
 p_execution_id text,p_evidence_ref text,p_actor_execution_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
"""
GOOD_REPORT=r"""
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(
 p_execution_id text,p_evidence_ref text,p_actor_execution_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
BEGIN
 RETURN jsonb_build_object(
   'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),
   'execution_id',p_execution_id);
END $f$;
"""
RUN = r"""
BEGIN;
INSERT INTO public.lf_operation_execution_steps VALUES
 ('EXEC-TEST','input_validate','STEP_PASS_WITH_EVIDENCE',
  '{"resolved_scope":{"resolved_screen_code":"B2B-AUTH-001"}}');
INSERT INTO lf_ops.pantallas VALUES(51,'B2B-AUTH-001');
INSERT INTO lf_ops.reglas VALUES
 (1,'B2B-RULE-AUTH-001','CANDIDATO','SECURITY',false,NULL),
 (2,'B2B-RULE-AUTH-002','CANDIDATO','SECURITY',false,NULL),
 (3,'B2B-RULE-AUTH-047','CANDIDATO','UX',true,'Falta contador canónico de intentos'),
 (4,'B2B-RULE-A11Y-001','VIGENTE','ACCESSIBILITY',false,NULL),
 (5,'B2B-RULE-AUTH-022','CANDIDATO','SECURITY',false,NULL);
INSERT INTO lf_ops.reglas_pantallas VALUES(1,51),(2,51),(3,51),(4,51),(5,51);
INSERT INTO lf_ops.regla_behavior_tests VALUES ('B2B-RULE-AUTH-002',null,null,null);
SELECT 'REPORT_COUNT='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,count}');
SELECT 'DEST_REPAIR='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,0,destino}');
SELECT 'DEST_T_REMED='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,1,destino}');
SELECT 'DEST_HUMAN='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,3,destino}');
SELECT 'AUTH_HARD_BLOCK='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,0,hard_block}');
SELECT 'AUTH_CATEGORY='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,0,hard_block_categoria}');
SELECT 'HARD_BLOCK='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,3,hard_block}');
SELECT 'A_MAX='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,0,A,maximo}');
SELECT 'C_OBTAINED='||(public.lf_profile_native_bridge_record_report_v1(
 'EXEC-TEST','evidence',null)#>>'{rule_score_report,rule_reports,3,C,obtenidos}');
SELECT 'NO_OUT_OF_SCOPE='||(
  SELECT count(*) FROM jsonb_array_elements(
   public.lf_profile_native_bridge_record_report_v1('EXEC-TEST','evidence',null)
     #>'{rule_score_report,rule_reports}') a
  WHERE a->>'regla'='B2B-RULE-A11Y-001');
SELECT 'AUTH_MANUAL_INCLUDED='||(
  SELECT count(*) FROM jsonb_array_elements(
   public.lf_profile_native_bridge_record_report_v1('EXEC-TEST','evidence',null)
     #>'{rule_score_report,rule_reports}') a
  WHERE a->>'regla'='B2B-RULE-AUTH-022' AND a->>'hard_block'='true' AND a->>'destino'='DECISION_HUMANA');
SELECT 'NO_MUTATION='||count(*) FROM lf_ops.reglas WHERE estado='VIGENTE';
ROLLBACK;
SELECT 'NO_RESIDUE='||count(*) FROM lf_ops.reglas;
"""
class ProfileRuleScoreReportPGDual(unittest.TestCase):
 def test_step80_score_report_pg17_pg18(self):
  self.assertTrue(shutil.which("docker"), "DOCKER_REQUIRED")
  self.assertEqual(len(MIGRATIONS),1,"ONE_MIGRATION_REQUIRED")
  migration=MIGRATIONS[0].read_text(encoding="utf-8")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-step80-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-2000:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       log=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (log.stdout+log.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(q,negative=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=q,capture_output=True,text=True,timeout=180)
      if negative:self.assertNotEqual(p.returncode,0,"EXPECTED_DRIFT_FAIL")
      else:self.assertEqual(p.returncode,0,p.stderr[-3500:]+"\n"+p.stdout[-2500:])
      return p.stdout,p.stderr
     sql(BASE+BAD_REPORT)
     _,err=sql(migration,negative=True)
     self.assertIn("LF_RULE_SCORE_REPORT_PATCH_NOT_APPLIED",err)
     sql(GOOD_REPORT)
     sql(migration)
     out,_=sql(RUN)
     for marker in (
       "REPORT_COUNT=4","DEST_REPAIR=REPARAR_REGLA",
       "DEST_T_REMED=T_REMED","DEST_HUMAN=DECISION_HUMANA",
       "HARD_BLOCK=true","AUTH_HARD_BLOCK=true","AUTH_CATEGORY=AUTH","A_MAX=40","C_OBTAINED=0",
       "NO_OUT_OF_SCOPE=0","AUTH_MANUAL_INCLUDED=1",
       "NO_MUTATION=1","NO_RESIDUE=0"):
      self.assertIn(marker,out,marker+"\n"+out[-3000:])
     print("PASS_LF_STEP80_RULE_SCORE_PG"+pg+"_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
