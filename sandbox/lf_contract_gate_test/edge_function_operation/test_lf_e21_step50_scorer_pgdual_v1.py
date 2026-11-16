"""PG17/18 B/D source-ref scorer real function, Step40/50/60/70 hash chain.
Synthetic rows are rollback-only; this does NOT register a real CI PASS for A.
"""
import re,shutil,subprocess,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).parent
SCORE=(HERE/"fixtures/lf_e21_step50_scorer_live_source_20261116.sql").read_text()
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_e21_step50_verified_real_effect_v1.sql"))
assert len(MIGS)==1
MIG=MIGS[0].read_text()
NEW=re.search(r"DO \$score_patch\$[\s\S]*?\$new\$([\s\S]*?)\$new\$",MIG)
assert NEW,"SCORER_PATCH_NOT_FOUND"
PATCH="""
DO $change$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('public.lf_rule_promotion_score_v1(text,text)'::regprocedure);
 d:=replace(d,$old$  IF is_bound AND has_ref THEN b:=30; END IF;$old$,$new$"""+NEW.group(1)+"""$new$);
 IF position('step50_effect_verification,rule_receipts' IN d)=0 THEN
 RAISE EXCEPTION 'E21_SCORER_NOT_PATCHED'; END IF;
 EXECUTE d;
END $change$;
"""
SETUP=r"""
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas (
 codigo text PRIMARY KEY,estado text NOT NULL,categoria text NOT NULL,
 pendiente_decision boolean NOT NULL,updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE lf_ops.regla_behavior_tests (
 regla_codigo text,pg17 text,pg18 text,ci_run text
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text NOT NULL,step_order int NOT NULL,step_id text NOT NULL,
 status text NOT NULL,evidence_payload jsonb NOT NULL,
 observed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(execution_id,step_order)
);
"""
TX=r"""
BEGIN;
INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision)
VALUES ('B2B-RULE-AUTH-004','CANDIDATO','SECURITY',false);
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload)
VALUES
('E21-FIXTURE',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('a',64))),
('E21-FIXTURE',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('raw_output_sha256',repeat('b',64),
   'step50_effect_verification',jsonb_build_object(
     'status','VERIFIED','rule_receipts',jsonb_build_array(
        jsonb_build_object('rule_code','B2B-RULE-AUTH-004',
          'source_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004'))),
   'profile_output',jsonb_build_object('repair_execution',jsonb_build_object(
     'rule_receipts',jsonb_build_array(jsonb_build_object(
        'rule_code','B2B-RULE-AUTH-004'))))
  ));
DO $e21$
DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-FIXTURE','B2B-RULE-AUTH-004');
 IF v->>'A'<>'0' OR v->>'B'<>'0' OR v->>'D'<>'0' THEN
 RAISE EXCEPTION 'STEP50_UNBOUND_B_SHOULD_BE_ZERO:%',v; END IF;
END $e21$;
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload,observed_at)
VALUES
('E21-FIXTURE',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('raw_output_sha256',repeat('b',64)),now()+interval '1 second'),
('E21-FIXTURE',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('semantic_judge_result',jsonb_build_object(
  'verdict','PASS_REVIEWED_CURRENT_CONTEXT',
  'candidate_sha256',repeat('b',64),'scope_packet_sha256',repeat('a',64),
  'judge_v3_evidence',jsonb_build_object('unsupported_claims','[]'::jsonb))),
 now()+interval '2 seconds');
DO $e21$
DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-FIXTURE','B2B-RULE-AUTH-004');
 IF v->>'A'<>'0' OR v->>'B'<>'30' OR v->>'C'<>'20' OR v->>'D'<>'10'
 OR v->>'score'<>'60' OR v->>'decision'<>'MANUAL' THEN
 RAISE EXCEPTION 'STEP50_VERIFIED_SRCR_BD_NOT_SCORED:%',v; END IF;
END $e21$;
SELECT 'STEP50_VERIFIED_SRCR_BD=PASS';

-- Wrong rule receipt cannot score B/D.
UPDATE public.lf_operation_execution_steps
SET evidence_payload=jsonb_set(evidence_payload,
 '{step50_effect_verification,rule_receipts,0,source_ref}',
 to_jsonb('supabase://lf_ops.reglas/B2B-RULE-AUTH-049'::text))
WHERE execution_id='E21-FIXTURE' AND step_order=50;
DO $e21$ DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-FIXTURE','B2B-RULE-AUTH-004');
 IF v->>'B'<>'0' OR v->>'D'<>'0' THEN
 RAISE EXCEPTION 'STEP50_WRONG_RULE_BD_SCORED:%',v; END IF;
END $e21$;
SELECT 'STEP50_WRONG_RULE_FAIL_CLOSED=PASS';

-- Legacy Product Director source-ref path remains supported.
UPDATE public.lf_operation_execution_steps
SET evidence_payload=(evidence_payload-'step50_effect_verification')||
 jsonb_build_object('profile_output',jsonb_build_object(
 'deliverable_created',jsonb_build_object(
 'product_decision',jsonb_build_object(
 'source_refs',jsonb_build_array(jsonb_build_object(
 'source_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004'))))))
WHERE execution_id='E21-FIXTURE' AND step_order=50;
DO $e21$ DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-FIXTURE','B2B-RULE-AUTH-004');
 IF v->>'B'<>'30' THEN
 RAISE EXCEPTION 'STEP50_LEGACY_PD_SCORE_REGRESSED:%',v; END IF;
END $e21$;
SELECT 'STEP50_LEGACY_PD_BD_PRESERVED=PASS';
ROLLBACK;
SELECT 'STEP50_ROLLBACK_NO_RULE_ROWS='||count(*) FROM lf_ops.reglas;
SELECT 'STEP50_ROLLBACK_NO_STEP_ROWS='||count(*) FROM public.lf_operation_execution_steps;
"""
class Step50ScorerPGDual(unittest.TestCase):
 def test_server_bound_receipt_scoring_pg17_pg18(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-e21-score-"+uuid.uuid4().hex[:9]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      text=True,capture_output=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr)
    try:
     for _ in range(90):
      x=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       text=True,capture_output=True,timeout=10)
      if x.returncode==0:
       log=subprocess.run(["docker","logs",name],text=True,capture_output=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (log.stdout+log.stderr):break
      time.sleep(.5)
     self.assertEqual(x.returncode,0,"PG_NOT_READY")
     def sql(s):
      z=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
        "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
        input=s,text=True,capture_output=True,timeout=180)
      self.assertEqual(z.returncode,0,z.stderr[-4200:]+"\n"+z.stdout[-2100:])
      return z.stdout
     sql(SETUP+"\n"+SCORE+"\n"+PATCH)
     out=sql(TX)
     for m in (
       "STEP50_VERIFIED_SRCR_BD=PASS",
       "STEP50_WRONG_RULE_FAIL_CLOSED=PASS",
       "STEP50_LEGACY_PD_BD_PRESERVED=PASS",
       "STEP50_ROLLBACK_NO_RULE_ROWS=0",
       "STEP50_ROLLBACK_NO_STEP_ROWS=0"):
      self.assertIn(m,out,m+"\n"+out[-2000:])
     print("PASS_E21_STEP50_SCORER_SOURCE_BOUND_BD_PG"+pg+"_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
