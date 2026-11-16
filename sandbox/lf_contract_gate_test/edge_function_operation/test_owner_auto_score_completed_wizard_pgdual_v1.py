"""Owner 19:55: real SQL behavior PG17/PG18, rule auto approval and apply.
All synthetic writes occur in disposable Docker, BEGIN/ROLLBACK; real RUN never fabricated.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from test_rule_promotion_independent_step70_pgdual_v1 import SCHEMA, SOURCE

ROOT=Path(__file__).resolve().parents[3]
NEW=ROOT/"supabase/migrations/20261116010000_lf_owner_auto_score_apply_wizard_v1.sql"
OLD=ROOT/"supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql"
REF=("github://cristhianlujan/claude-persona-lf-patch@"
     "4c300100fa6df3f15c3d9a2433b5dbda2695239f/"
     "sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_wizard_three_step_pgdual_v1.py")
CI="actions://cristhianlujan/claude-persona-lf-patch/runs/43771883221"
RULE="B2B-RULE-LOAD-WIZARD-001"

def literal(v):
    return "'"+str(v).replace("'","''")+"'"

def segment(s,a,b):
    return s.split("-- "+a,1)[1].split("-- "+b,1)[0].strip()

class AutoWizardPGDual(unittest.TestCase):
    def test_completed_run_auto_decide_apply_and_rollback(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        old=OLD.read_text(encoding="utf-8")
        new=NEW.read_text(encoding="utf-8")
        score=segment(old,"LF_OWNER_SCORE_SCORER_BEGIN","LF_OWNER_SCORE_SCORER_END")
        request=segment(old,"LF_OWNER_SCORE_REQUEST_BEGIN","LF_OWNER_SCORE_REQUEST_END")
        decide_new=segment(new,"DECIDE_BEGIN","DECIDE_END")
        request_new=segment(new,"REQUEST_BEGIN","REQUEST_END")
        self.assertIn("AUTO_SCORE_AUTHORITY_NOT_ATTESTED",decide_new)
        self.assertIn("COMPLETED_PARENT_STEPS_NOT_CLEAN",request_new)
        self.assertIn("lf_rule_promotion_apply_v1",request_new)
        self.assertNotIn("HUMAN:AUTO_SCORE_V1",new)
        refs=json.dumps([{"source_ref":"supabase://lf_ops.reglas/"+RULE}],separators=(",",":"))
        tests=json.dumps([{"rule_code":RULE,"pg17":"PASS","pg18":"PASS",
                           "test_ref":REF,"ci_run":CI}],separators=(",",":"))
        initialization=SCHEMA+"\n"+SOURCE.read_text(encoding="utf-8")+"""
ALTER TABLE lf_ops.reglas ADD COLUMN categoria text NOT NULL DEFAULT 'OTHER';
ALTER TABLE lf_ops.reglas ADD COLUMN pendiente_decision boolean NOT NULL DEFAULT false;
ALTER TABLE lf_ops.reglas ADD COLUMN updated_at timestamptz NOT NULL DEFAULT '2026-09-01T00:00:00Z';
ALTER TABLE public.lf_operation_execution_steps ADD COLUMN observed_at timestamptz DEFAULT '2026-11-16T01:00:00Z';
ALTER TABLE public.lf_operation_execution ADD COLUMN manifest jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE TRIGGER lf_rule_promotion_guard BEFORE UPDATE ON lf_ops.reglas
 FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();
""" + (
f"INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision) VALUES"
f"({literal(RULE)},'CANDIDATO','WORKFLOW',false);\n"
)
        setup=f"""
UPDATE public.lf_operation_execution SET status='COMPLETED',
 manifest='{{"no_promotion":true}}'::jsonb WHERE execution_id='PARENT-1';
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{profile_output,deliverable_created,product_decision,source_refs}}',{literal(refs)}::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{profile_output,deliverable_created,behavior_tests}}',{literal(tests)}::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,
 '{{semantic_judge_result,judge_v3_evidence}}','{{"unsupported_claims":[]}}'::jsonb,true)
 WHERE execution_id='PARENT-1' AND step_order=70;
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload)
 SELECT 'PARENT-1',v.step_order,v.step_id,'STEP_PASS_WITH_EVIDENCE',v.payload::jsonb
 FROM (VALUES
 (0,'init_execution','{{}}'),(10,'router','{{}}'),(20,'profile_resolve','{{}}'),
 (30,'profile_source_read','{{}}'),(45,'context_admission','{{}}'),
 (47,'research_baseline_freeze','{{}}'),
 (80,'report_output','{{"next_gate":"RETURN_TO_ROUTER"}}')) v(step_order,step_id,payload);
"""
        test=f"""
BEGIN;
{score}
{request}
{decide_new}
{request_new}
{setup}
SELECT 'SCORE='||(public.lf_rule_promotion_score_v1('PARENT-1',{literal(RULE)})->>'score');
SELECT 'DECISION='||(public.lf_rule_promotion_score_v1('PARENT-1',{literal(RULE)})->>'decision');
SELECT 'AUTO_RESULT='||(public.lf_rule_promotion_request_v1(
  'PARENT-1',{literal(RULE)},'Owner 19:55 authorized score auto')->>'status');
SELECT 'RULE_AFTER='||estado FROM lf_ops.reglas WHERE codigo={literal(RULE)};
SELECT 'RECORD='||status||':'||decided_by||':'||
  (decided_at IS NOT NULL)::text||':'||(applied_at IS NOT NULL)::text
 FROM public.lf_rule_promotion_v1 WHERE rule_code={literal(RULE)};
-- Negative: score=0 for unrelated fixture-only rule, AUTO cannot approve it.
INSERT INTO public.lf_rule_promotion_v1(rule_code,request_execution_id,
 requested_by_profile,request_snapshot_sha256)
 VALUES ('RULE-CAND-001','PARENT-1','PERFIL-PRODUCT-DIRECTOR-LF',
 public.lf_asset_snapshot_sha_v1('REGLA','RULE-CAND-001'));
SELECT 'AUTO_LOW='||(public.lf_rule_promotion_decide_v1(
 (SELECT promotion_id FROM public.lf_rule_promotion_v1 WHERE rule_code='RULE-CAND-001'),
 'APPROVE','AUTO_SCORE_V1','rejected')->>'blocking_code');
SELECT 'BOT='||(public.lf_rule_promotion_decide_v1(
 (SELECT promotion_id FROM public.lf_rule_promotion_v1 WHERE rule_code='RULE-CAND-001'),
 'APPROVE','BOT:FORGED','rejected')->>'blocking_code');
ROLLBACK;
SELECT 'RULE_ROLLBACK='||estado FROM lf_ops.reglas WHERE codigo={literal(RULE)};
SELECT 'PROMOTIONS_ROLLBACK='||count(*) FROM public.lf_rule_promotion_v1;
"""
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-auto-wizard-"+uuid.uuid4().hex[:9]
                started=subprocess.run(["docker","run","-d","--rm","--name",name,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(started.returncode,0,started.stderr[-1800:])
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                            capture_output=True,text=True,timeout=10)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr): break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    def sql(source):
                        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
                            "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                            input=source,capture_output=True,text=True,timeout=180)
                        self.assertEqual(p.returncode,0,p.stderr[-6500:]+"\n"+p.stdout[-2300:])
                        return p.stdout
                    sql(initialization)
                    out=sql(test)
                    for x in (
                        "SCORE=100","DECISION=AUTO","AUTO_RESULT=APPLIED",
                        "RULE_AFTER=VIGENTE","RECORD=APPLIED:AUTO_SCORE_V1:true:true",
                        "AUTO_LOW=AUTO_SCORE_AUTHORITY_NOT_ATTESTED",
                        "BOT=APPROVER_MUST_BE_HUMAN",
                        "RULE_ROLLBACK=CANDIDATO","PROMOTIONS_ROLLBACK=0"
                    ):
                        self.assertIn(x,out,x+"\n"+out[-3000:])
                    print(f"PASS_OWNER_AUTO_SCORE_COMPLETE_RUN_PG{pg}_APPLY_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,text=True,timeout=30)
if __name__=="__main__": unittest.main()
