"""Owner score route: PG17.6 + PG18.7, SQL functions on source-backed fixtures.
Only genuine docker PostgreSQL with BEGIN/ROLLBACK; no live promotion or DB writes.
Categories, pending decisions and source refs are projected from owner 19:05 SELECT.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from test_rule_promotion_independent_step70_pgdual_v1 import SCHEMA, SOURCE

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql"
WIZARD_REF = ("github://cristhianlujan/claude-persona-lf-patch@"
    "4c300100fa6df3f15c3d9a2433b5dbda2695239f/"
    "sandbox/lf_contract_gate_test/edge_function_operation/"
    "test_b2b_wizard_three_step_pgdual_v1.py")
CI_RUN = "actions://cristhianlujan/claude-persona-lf-patch/runs/43771883221"
CASES = [
    ("B2B-RULE-LOAD-WIZARD-001","WORKFLOW",False,100,"AUTO",False),
    ("B2B-RULE-IDEMP-001","INTEGRITY",False,60,"MANUAL",False),
    ("B2B-RULE-STORAGE-002","STORAGE",False,60,"MANUAL",False),
    ("B2B-RULE-VALIDATION-VALID-ONLY-001","VALIDATION",False,60,"MANUAL",False),
    ("B2B-RULE-LOAD-DEBT-TEMPORAL-BASIS-001","B2B_CARGAS",True,40,"BLOCKED",True),
    ("B2B-RULE-APPROVAL-001","APPROVAL",False,20,"BLOCKED",True),
    ("B2B-RULE-LOAD-NAMING-001","CARGAS",False,20,"BLOCKED",False),
    ("B2B-RULE-STORAGE-001","STORAGE",False,20,"BLOCKED",False),
    ("B2B-RULE-INSTALLMENT-001","BUSINESS",True,0,"BLOCKED",True),
    ("B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001","B2B_CARGAS",True,0,"BLOCKED",True),
    ("B2B-RULE-INSTALLMENT-PLAN-001","OFERTAS_CUOTAS",True,0,"BLOCKED",True),
    ("B2B-RULE-LEGAL-001","LEGAL",True,0,"BLOCKED",True),
    ("B2B-RULE-THEME-002","THEME",True,0,"BLOCKED",True),
]
BOUND_RULES = [CASES[i][0] for i in (0,1,2,3,4)]

def q(s):
    return "'" + str(s).replace("'", "''") + "'"

def extract(source, start, end):
    a = source.index("-- " + start)
    b = source.index("-- " + end, a)
    return source[a:b]

class OwnerScoreContextPGDual(unittest.TestCase):
    def test_score_matrix_and_semantic_gate_pg17_pg18_rollback(self):
        self.assertTrue(shutil.which("docker"), "DOCKER_REQUIRED")
        migration = MIG.read_text(encoding="utf-8")
        score_fn = extract(migration, "LF_OWNER_SCORE_SCORER_BEGIN",
                           "LF_OWNER_SCORE_SCORER_END")
        request_fn = extract(migration, "LF_OWNER_SCORE_REQUEST_BEGIN",
                             "LF_OWNER_SCORE_REQUEST_END")
        self.assertIn("NOT_PROVEN_OWNER_ACCEPTED",score_fn)
        self.assertIn("PASS_REVIEWED_CURRENT_CONTEXT",request_fn)
        self.assertNotIn("PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED",request_fn)
        self.assertIn("20261115222000",migration[:300])
        fixture = (
          SCHEMA + "\n" + SOURCE.read_text(encoding="utf-8") + """
ALTER TABLE lf_ops.reglas ADD COLUMN categoria text DEFAULT 'OTHER';
ALTER TABLE lf_ops.reglas ADD COLUMN pendiente_decision boolean DEFAULT false;
ALTER TABLE lf_ops.reglas ADD COLUMN updated_at timestamptz
  DEFAULT '2026-09-01T00:00:00Z'::timestamptz;
ALTER TABLE public.lf_operation_execution_steps ADD COLUMN observed_at timestamptz
  DEFAULT '2026-11-15T22:46:32Z'::timestamptz;
ALTER TABLE public.lf_operation_execution ADD COLUMN manifest jsonb DEFAULT '{}'::jsonb;
CREATE TRIGGER lf_rule_promotion_guard BEFORE UPDATE ON lf_ops.reglas
  FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();
""" + "\n".join(
    "INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision,updated_at) VALUES ("
    +q(code)+",'CANDIDATO',"+q(cat)+","
    +("true" if pending else "false")
    +",'2026-09-01T00:00:00Z'::timestamptz);"
    for code,cat,pending,*_ in CASES
 ) + "\n"
)
        refs = json.dumps([{"source_ref":"supabase://lf_ops.reglas/"+code}
                           for code in BOUND_RULES],separators=(",",":"))
        behavior = json.dumps([{"rule_code":CASES[0][0],
            "test_ref":WIZARD_REF,"pg17":"PASS","pg18":"PASS","ci_run":CI_RUN}],
            separators=(",",":"))
        bind = f"""
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(
evidence_payload,'{{profile_output,deliverable_created,product_decision,source_refs}}',
{q(refs)}::jsonb) WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(
evidence_payload,'{{profile_output,deliverable_created,behavior_tests}}',
{q(behavior)}::jsonb,true) WHERE execution_id='PARENT-1' AND step_order=50;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(
evidence_payload,'{{semantic_judge_result,judge_v3_evidence}}',
'{{"unsupported_claims":[]}}'::jsonb,true) WHERE execution_id='PARENT-1' AND step_order=70;
UPDATE public.lf_operation_execution SET manifest='{{"no_promotion":true}}'::jsonb
WHERE execution_id='PARENT-1';
"""
        matrix = "SELECT 'SCORE='||x.code||'='||(x.score->>'score')||':'||(x.score->>'decision')||':'||(x.score->>'hard_block') FROM (\n"
        matrix += "SELECT code,public.lf_rule_promotion_score_v1('PARENT-1',code) score FROM (VALUES\n"
        matrix += ",\n".join(f"({q(row[0])})" for row in CASES)
        matrix += ") a(code)) x;"
        invalids = [
          ("MISSING_STEP70","DELETE FROM public.lf_operation_execution_steps WHERE execution_id='PARENT-1' AND step_order=70;"),
          ("FAIL_STEP70","UPDATE public.lf_operation_execution_steps SET status='STEP_FAIL' WHERE execution_id='PARENT-1' AND step_order=70;"),
          ("WRONG_CANDIDATE_HASH","UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{semantic_judge_result,candidate_sha256}',to_jsonb(repeat('f',64))) WHERE execution_id='PARENT-1' AND step_order=70;"),
          ("WRONG_SCOPE_HASH","UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{scope_authority_packet_sha256}',to_jsonb('sha256:'||repeat('f',64))) WHERE execution_id='PARENT-1' AND step_order=40;"),
          ("WRONG_STEP60_HASH","UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{raw_output_sha256}',to_jsonb(repeat('f',64))) WHERE execution_id='PARENT-1' AND step_order=60;"),
          ("UNSUPPORTED_CLAIM","UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{semantic_judge_result,judge_v3_evidence,unsupported_claims}','[\"unproven\"]'::jsonb) WHERE execution_id='PARENT-1' AND step_order=70;"),
        ]
        negative_sql = ""
        for label,mutation in invalids:
            negative_sql += f"""
SAVEPOINT neg;
{mutation}
SELECT 'NEG_{label}='||(public.lf_rule_promotion_request_v1(
 'PARENT-1','B2B-RULE-LOAD-WIZARD-001','negative gate')->>'blocking_code');
ROLLBACK TO SAVEPOINT neg;
"""
        # Alter only within SAVEPOINT, then restore. Distinguish JSON-only from PG SQL tests.
        quality_probes = f"""
SAVEPOINT invalid_fixture;
UPDATE public.lf_operation_execution_steps
SET evidence_payload=jsonb_set(evidence_payload,
'{{profile_output,deliverable_created,behavior_tests}}',
'[{{"rule_code":"B2B-RULE-LOAD-WIZARD-001","test_ref":"fixture.json","pg17":"PASS","pg18":"PASS","ci_run":"{CI_RUN}"}}]'::jsonb)
WHERE execution_id='PARENT-1' AND step_order=50;
SELECT 'FIXTURE_ONLY='||(public.lf_rule_promotion_score_v1(
'PARENT-1','B2B-RULE-LOAD-WIZARD-001')->>'score');
ROLLBACK TO SAVEPOINT invalid_fixture;
SAVEPOINT hard_block;
UPDATE lf_ops.reglas SET categoria='LEGAL' WHERE codigo='B2B-RULE-LOAD-WIZARD-001';
SELECT 'HARD_BLOCK='||(public.lf_rule_promotion_score_v1(
'PARENT-1','B2B-RULE-LOAD-WIZARD-001')->>'decision');
ROLLBACK TO SAVEPOINT hard_block;
SELECT 'NO_PROMOTION_TRUE_SCORE='||(public.lf_rule_promotion_score_v1(
'PARENT-1','B2B-RULE-LOAD-WIZARD-001')->>'score');
UPDATE public.lf_operation_execution SET manifest='{{"no_promotion":false}}'::jsonb
WHERE execution_id='PARENT-1';
SELECT 'NO_PROMOTION_FALSE_SCORE='||(public.lf_rule_promotion_score_v1(
'PARENT-1','B2B-RULE-LOAD-WIZARD-001')->>'score');
SELECT 'REQUEST='||(j->>'status')||':'||(j->>'score_decision')||':'||
(j->>'judge_independence')||':'||(j#>>'{{auto_decision_attempt,blocking_code}}')
FROM (SELECT public.lf_rule_promotion_request_v1(
 'PARENT-1','B2B-RULE-LOAD-WIZARD-001','owner score') j) x;
SELECT 'PROMOTION_IN_TX='||count(*) FROM public.lf_rule_promotion_v1;
"""
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-owner-score-"+uuid.uuid4().hex[:10]
                started=subprocess.run(["docker","run","-d","--rm","--name",name,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(started.returncode,0,started.stderr[-2000:])
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                            capture_output=True,text=True,timeout=10)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],
                                capture_output=True,text=True,timeout=10)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    def sql(input):
                        p=subprocess.run(["docker","exec","-i",name,"psql",
                          "-X","-A","-t","-U","postgres","-d","postgres",
                          "-v","ON_ERROR_STOP=1"],input=input,capture_output=True,
                          text=True,timeout=130)
                        self.assertEqual(p.returncode,0,p.stderr[-4500:]+p.stdout[-2000:])
                        return p.stdout
                    sql(fixture)
                    out=sql("BEGIN;\n"+score_fn+"\n"+request_fn+"\n"+bind+
                            matrix+"\n"+negative_sql+"\n"+quality_probes+
                            "\nROLLBACK;\n"
                            "SELECT 'POST_ROLLBACK='||count(*) FROM public.lf_rule_promotion_v1;\n"
                            "SELECT 'RULE_STATE='||estado FROM lf_ops.reglas "
                            "WHERE codigo='B2B-RULE-LOAD-WIZARD-001';")
                    for code,cat,pending,score,decision,hard in CASES:
                        marker=f"SCORE={code}={score}:{decision}:{str(hard).lower()}"
                        self.assertIn(marker,out,marker+"\n"+out[-4500:])
                    for label,_ in invalids:
                        self.assertIn("NEG_"+label+"=PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED",out,out[-4500:])
                    for marker in (
                      "FIXTURE_ONLY=60",
                      "HARD_BLOCK=MANUAL",
                      "NO_PROMOTION_TRUE_SCORE=100",
                      "NO_PROMOTION_FALSE_SCORE=100",
                      "REQUEST=PENDING_HUMAN_APPROVAL:AUTO:NOT_PROVEN_OWNER_ACCEPTED:APPROVER_MUST_BE_HUMAN",
                      "PROMOTION_IN_TX=1","POST_ROLLBACK=0","RULE_STATE=CANDIDATO",
                    ):
                        self.assertIn(marker,out,marker+"\n"+out[-4500:])
                    print(f"PASS_OWNER_SCORE_MATRIX_PG{pg}_13_RULES_HASH_NEGATIVES_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

if __name__=="__main__":
    unittest.main()
