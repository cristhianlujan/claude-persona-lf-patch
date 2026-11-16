"""Owner 21:15: generic 2-rule scoring, no-row/LEGAL cases, auto_apply and stale-run abandonment.
Only disposable PG17.6/18.7 Docker; all migration and mutation effects BEGIN/ROLLBACK.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from test_rule_promotion_independent_step70_pgdual_v1 import SCHEMA, SOURCE
from test_owner_auto_score_completed_wizard_pgdual_v1 import segment, literal

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql"
PRIOR=ROOT/"supabase/migrations/20261116010000_lf_owner_auto_score_apply_wizard_v1.sql"
RULES=("R-OK-1","R-OK-2","R-NOTEST","R-LEGAL")

class GenericRulePGDual(unittest.TestCase):
    def test_generic_2_rule_auto_legal_hardblock_and_abandon_rollback(self):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
        migration=MIG.read_text(encoding="utf-8")
        prior=PRIOR.read_text(encoding="utf-8")
        scorer=migration.split("CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1",1)[1].split(
             "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_auto_apply_v1",1)[0]
        self.assertNotIn("wizard_test",scorer)
        self.assertNotIn("wizard_run",scorer)
        self.assertNotIn("tests:=p50.",scorer)
        self.assertIn("lf_ops.regla_behavior_tests bt",scorer)
        self.assertIn("A from lf_ops.regla_behavior_tests",scorer)
        self.assertIn("IF is_bound AND EXISTS",scorer)
        self.assertIn("e.updated_at<now()-interval '24 hours'",migration)
        self.assertIn("s.observed_at>now()-interval '24 hours'",migration)
        self.assertTrue(migration.startswith("BEGIN;\n"))
        self.assertTrue(migration.rstrip().endswith("COMMIT;"))
        migration_body=migration[len("BEGIN;\n"):].rsplit("COMMIT;",1)[0]
        decide=segment(prior,"DECIDE_BEGIN","DECIDE_END")
        request=segment(prior,"REQUEST_BEGIN","REQUEST_END")
        refs=json.dumps([{"source_ref":"supabase://lf_ops.reglas/"+x} for x in RULES],separators=(",",":"))
        # Deliberately fabricate Step50 PASS for R-NOTEST. It must NOT award A without registry row.
        fixture_tests=json.dumps([{"rule_code":"R-NOTEST","test_ref":"fixture.json",
            "pg17":"PASS","pg18":"PASS","ci_run":"actions://fake"}],separators=(",",":"))
        initialization=SCHEMA+"\n"+SOURCE.read_text(encoding="utf-8")+"""
ALTER TABLE lf_ops.reglas ADD COLUMN categoria text NOT NULL DEFAULT 'WORKFLOW';
ALTER TABLE lf_ops.reglas ADD COLUMN pendiente_decision boolean NOT NULL DEFAULT false;
ALTER TABLE lf_ops.reglas ADD COLUMN updated_at timestamptz NOT NULL DEFAULT '2026-01-01T00:00:00Z';
ALTER TABLE public.lf_operation_execution_steps ADD COLUMN observed_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.lf_operation_execution
 ADD COLUMN manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
 ADD COLUMN completed_at timestamptz;
CREATE TRIGGER lf_rule_promotion_guard BEFORE UPDATE ON lf_ops.reglas
 FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();
INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision)
VALUES ('B2B-RULE-LOAD-WIZARD-001','CANDIDATO','WORKFLOW',false);
"""+"\n".join(f"INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision) VALUES ({literal(r)},'CANDIDATO',{literal('LEGAL' if r=='R-LEGAL' else 'WORKFLOW')},false);" for r in RULES)
        setup=f"""
UPDATE public.lf_operation_execution SET status='COMPLETED' WHERE execution_id='PARENT-1';
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{profile_output,deliverable_created,product_decision,source_refs}}',{literal(refs)}::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{profile_output,deliverable_created,behavior_tests}}',{literal(fixture_tests)}::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{semantic_judge_result,judge_v3_evidence}}','{{"unsupported_claims":[]}}'::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=70;
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload)
 SELECT 'PARENT-1',v.step_order,v.step_id,'STEP_PASS_WITH_EVIDENCE',v.payload::jsonb
 FROM (VALUES (0,'init_execution','{{}}'),(10,'router','{{}}'),
 (20,'profile_resolve','{{}}'),(30,'profile_source_read','{{}}'),
 (45,'context_admission','{{}}'),(47,'research_baseline_freeze','{{}}'),
 (80,'report_output','{{"next_gate":"RETURN_TO_ROUTER"}}')) v(step_order,step_id,payload);
INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18)
VALUES ('R-OK-1','test_one.py','actions://ci-1','PASS','PASS'),
('R-OK-2','test_two.py','actions://ci-2','PASS','PASS'),
('R-LEGAL','test_legal.py','actions://ci-legal','PASS','PASS');
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_code,status,updated_at,manifest)
VALUES
 ('OLD1','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',now()-interval '48 hours','{{}}'),
 ('OLD2','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',now()-interval '48 hours','{{}}'),
 ('E1','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',now()-interval '1 hour','{{}}');
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload,observed_at)
 VALUES ('OLD2',40,'input_validate','STEP_PASS_WITH_EVIDENCE','{{}}',now()-interval '1 hour');
"""
        checks="""
SELECT 'GENERIC_SCORE='||r.code||':'||(s.v->>'A')||':'||(s.v->>'score')||':'||
       (s.v->>'decision')||':'||(s.v->>'hard_block')
FROM (VALUES ('R-OK-1'),('R-OK-2'),('R-NOTEST'),('R-LEGAL')) r(code)
CROSS JOIN LATERAL (SELECT public.lf_rule_promotion_score_v1('PARENT-1',r.code) AS v) s
ORDER BY r.code;
SELECT 'APPLY_NOTEST='||(j->>'status')||':'||(j->>'written')
 FROM (SELECT public.lf_rule_promotion_auto_apply_v1('PARENT-1','R-NOTEST') j) x;
SELECT 'APPLY_LEGAL='||(j->>'status')||':'||(j->>'written')
 FROM (SELECT public.lf_rule_promotion_auto_apply_v1('PARENT-1','R-LEGAL') j) x;
SELECT 'APPLY_OK1='||(j->>'status')||':'||(j->>'written')
 FROM (SELECT public.lf_rule_promotion_auto_apply_v1('PARENT-1','R-OK-1') j) x;
SELECT 'APPLY_OK2='||(j->>'status')||':'||(j->>'written')
 FROM (SELECT public.lf_rule_promotion_auto_apply_v1('PARENT-1','R-OK-2') j) x;
SELECT 'APPLY_REPLAY='||(j->>'status')||':'||(j->>'written')
 FROM (SELECT public.lf_rule_promotion_auto_apply_v1('PARENT-1','R-OK-1') j) x;
SELECT 'PROMOTED='||rule_code||':'||status||':'||decided_by
 FROM public.lf_rule_promotion_v1 WHERE rule_code IN ('R-OK-1','R-OK-2','R-LEGAL','R-NOTEST')
 ORDER BY rule_code;
SELECT 'RULE_STATE='||codigo||':'||estado FROM lf_ops.reglas
 WHERE codigo IN ('R-OK-1','R-OK-2','R-NOTEST','R-LEGAL') ORDER BY codigo;
SELECT 'ABANDON='||(j->>'execution_id')||':'||(j->>'abandoned') FROM
 (SELECT public.lf_execution_mark_abandoned_v1('OLD1','SIN_AVANCE_24H_OWNER_20261115') AS j) x
UNION ALL
SELECT 'ABANDON='||(j->>'execution_id')||':'||(j->>'abandoned') FROM
 (SELECT public.lf_execution_mark_abandoned_v1('OLD2','SIN_AVANCE_24H_OWNER_20261115') AS j) x
UNION ALL
SELECT 'ABANDON='||(j->>'execution_id')||':'||(j->>'abandoned') FROM
 (SELECT public.lf_execution_mark_abandoned_v1('E1','SIN_AVANCE_24H_OWNER_20261115') AS j) x;
SELECT 'EXEC_STATE='||execution_id||':'||status FROM public.lf_operation_execution
 WHERE execution_id IN ('OLD1','OLD2','E1') ORDER BY execution_id;
SELECT 'OLD1_REASON='||(manifest->>'abandoned_reason')
 FROM public.lf_operation_execution WHERE execution_id='OLD1';
"""
        test="BEGIN;\n"+decide+"\n"+request+"\n"+migration_body+"\n"+setup+"\n"+checks+"\nROLLBACK;\n"
        test+="SELECT 'POST_ROLLBACK_PROMOTIONS='||count(*) FROM public.lf_rule_promotion_v1;\n"
        test+="SELECT 'POST_ROLLBACK_RULES='||count(*) FROM lf_ops.reglas WHERE codigo IN ('R-OK-1','R-OK-2') AND estado='CANDIDATO';\n"
        test+="SELECT 'POST_ROLLBACK_ABANDON='||count(*) FROM public.lf_operation_execution WHERE execution_id='OLD1';\n"
        for pg in ("17.6","18.7"):
            with self.subTest(engine=pg):
                name="lf-rule-generic-"+uuid.uuid4().hex[:10]
                started=subprocess.run(["docker","run","-d","--rm","--name",name,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(started.returncode,0,started.stderr[-2000:])
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                           capture_output=True,text=True,timeout=10)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    def run_sql(sql):
                        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
                          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                          input=sql,capture_output=True,text=True,timeout=160)
                        self.assertEqual(p.returncode,0,p.stderr[-6500:]+"\n"+p.stdout[-3500:])
                        return p.stdout
                    run_sql(initialization)
                    result=run_sql(test)
                    expected=(
                      "GENERIC_SCORE=R-OK-1:40:100:AUTO:false",
                      "GENERIC_SCORE=R-OK-2:40:100:AUTO:false",
                      "GENERIC_SCORE=R-NOTEST:0:60:MANUAL:false",
                      "GENERIC_SCORE=R-LEGAL:40:100:MANUAL:true",
                      "APPLY_NOTEST=MANUAL:false","APPLY_LEGAL=MANUAL:false",
                      "APPLY_OK1=APPLIED:true","APPLY_OK2=APPLIED:true",
                      "APPLY_REPLAY=BLOCKED:false",
                      "PROMOTED=R-OK-1:APPLIED:AUTO_SCORE_V1",
                      "PROMOTED=R-OK-2:APPLIED:AUTO_SCORE_V1",
                      "RULE_STATE=R-OK-1:VIGENTE","RULE_STATE=R-OK-2:VIGENTE",
                      "RULE_STATE=R-NOTEST:CANDIDATO","RULE_STATE=R-LEGAL:CANDIDATO",
                      "ABANDON=OLD1:true","ABANDON=OLD2:false","ABANDON=E1:false",
                      "EXEC_STATE=OLD1:ABANDONED","EXEC_STATE=OLD2:IN_PROGRESS",
                      "EXEC_STATE=E1:IN_PROGRESS",
                      "OLD1_REASON=SIN_AVANCE_24H_OWNER_20261115",
                      "POST_ROLLBACK_PROMOTIONS=0","POST_ROLLBACK_RULES=2",
                      "POST_ROLLBACK_ABANDON=0")
                    for marker in expected:
                        self.assertIn(marker,result,"MISSING "+marker+"\n"+result[-4200:])
                    print(f"PASS_GENERIC_SCORE_AUTO_APPLY_ABANDON_PG{pg}_BEGIN_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,text=True,timeout=30)
if __name__=="__main__":
    unittest.main()
