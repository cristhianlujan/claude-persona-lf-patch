"""Negative real scoring behavior PG17.6/PG18.7, 40 current CANDIDATO. 
NOT a certification of AUTH behavioral implementation; no PASS/ci_run registered.
"""
import shutil, subprocess, time, unittest, uuid
from pathlib import Path
HERE=Path(__file__).parent
SOURCE=(HERE/"fixtures/lf_e21_candidate_score_live_source_20261116.sql").read_text()
RULES=(HERE/"fixtures/lf_e21_candidate_rules_40_snapshot_20261116.sql").read_text()
DDL="""
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY,estado text,categoria text,pendiente_decision boolean,updated_at timestamptz DEFAULT now());
CREATE TABLE lf_ops.regla_behavior_tests(regla_codigo text,test_ref text,ci_run text,pg17 text,pg18 text,source_sha text);
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_order integer,step_id text,status text,evidence_payload jsonb,observed_at timestamptz DEFAULT now(),PRIMARY KEY(execution_id,step_order));
"""
TEST="""
BEGIN;
INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18)
 SELECT codigo,'NEGATIVE_SYNTHETIC_ONLY','DO_NOT_REGISTER','PASS','PASS' FROM lf_ops.reglas;
DO $e21$
DECLARE r record;s jsonb;n integer;
BEGIN
 SELECT count(*) INTO n FROM lf_ops.reglas;
 IF n<>40 THEN RAISE EXCEPTION 'E21_L2_EXPECTED_40:%',n; END IF;
 FOR r IN SELECT codigo,pendiente_decision FROM lf_ops.reglas LOOP
   s:=public.lf_rule_promotion_score_v1('E21-NO-REAL-RUN',r.codigo);
   IF s->>'A'<>'0' OR s->>'B'<>'0' OR s->>'D'<>'0' OR
      (r.pendiente_decision AND s->>'score'<>'0') OR
      (NOT r.pendiente_decision AND s->>'score'<>'20') OR
      s->>'decision'<>'BLOCKED' THEN
     RAISE EXCEPTION 'E21_L2_FALSE_A_SCORING:%:%',r.codigo,s; END IF;
 END LOOP;
END $e21$;
SELECT 'L2_UNBOUND_ALL_BLOCKED='||count(*) FROM lf_ops.reglas r
WHERE public.lf_rule_promotion_score_v1('E21-NO-REAL-RUN',r.codigo)->>'decision'='BLOCKED';
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload) VALUES
('E21-PARTIAL',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('b',64))),
('E21-PARTIAL',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('raw_output_sha256',repeat('a',64),'profile_output',
  jsonb_build_object('deliverable_created',
   jsonb_build_object('product_decision',jsonb_build_object('source_refs',
    jsonb_build_array(
     jsonb_build_object('source_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-049'),
     jsonb_build_object('source_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004')))))));
DO $e21$ DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-PARTIAL','B2B-RULE-AUTH-004');
 IF v->>'A'<>'0' OR v->>'B'<>'0' THEN RAISE EXCEPTION 'E21_PARTIAL_HASH_CHAIN_SCORED:%',v; END IF;
END $e21$;
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload,observed_at) VALUES
('E21-PARTIAL',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('raw_output_sha256',repeat('a',64)),now()+interval '1 hour'),
('E21-PARTIAL',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('semantic_judge_result',jsonb_build_object(
  'verdict','PASS_REVIEWED_CURRENT_CONTEXT','candidate_sha256',repeat('a',64),
  'scope_packet_sha256',repeat('b',64),
  'judge_v3_evidence',jsonb_build_object('unsupported_claims','[]'::jsonb)
 )),now()+interval '2 hours');
DO $e21$ DECLARE v jsonb;w jsonb;
BEGIN
 v:=public.lf_rule_promotion_score_v1('E21-PARTIAL','B2B-RULE-AUTH-004');
 w:=public.lf_rule_promotion_score_v1('E21-PARTIAL','B2B-RULE-AUTH-049');
 IF v->>'A'<>'40' OR v->>'B'<>'30' OR v->>'C'<>'20' OR v->>'D'<>'10'
 OR v->>'decision'<>'AUTO' OR v->>'score'<>'100' THEN
 RAISE EXCEPTION 'E21_SYNTHETIC_SCORER_SANITY:%',v; END IF;
 IF w->>'A'<>'40' OR w->>'B'<>'30' OR w->>'C'<>'0' OR w->>'D'<>'10'
 OR w->>'hard_block'<>'true' OR w->>'decision'<>'MANUAL' OR w->>'score'<>'80' THEN
 RAISE EXCEPTION 'E21_AUTH049_UNRESOLVED_MANUAL:%',w; END IF;
END $e21$;
SELECT 'E21_L2_SYNTHETIC_CHAIN_TESTED=PASS';
ROLLBACK;
SELECT 'E21_L2_NO_REGISTRY_RESIDUE='||count(*) FROM lf_ops.regla_behavior_tests;
SELECT 'E21_L2_NO_STEP_RESIDUE='||count(*) FROM public.lf_operation_execution_steps;
"""
class PGDual(unittest.TestCase):
 def test_40_candidate_scoring_bound_to_real_steps(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for version in ("17.6","18.7"):
   with self.subTest(version=version):
    n="lf-e21-l2-"+uuid.uuid4().hex[:8]
    c=subprocess.run(["docker","run","-d","--rm","--name",n,"-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
        capture_output=True,text=True,timeout=180)
    self.assertEqual(c.returncode,0,c.stderr)
    try:
     for _ in range(90):
      p=subprocess.run(["docker","exec",n,"pg_isready","-U","postgres"],capture_output=True,text=True,timeout=10)
      if p.returncode==0:
       l=subprocess.run(["docker","logs",n],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (l.stdout+l.stderr):break
      time.sleep(.5)
     self.assertEqual(p.returncode,0,"PG_NOT_READY")
     def sql(t):
      r=subprocess.run(["docker","exec","-i",n,"psql","-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=t,capture_output=True,text=True,timeout=180)
      self.assertEqual(r.returncode,0,r.stderr[-3500:]+"\n"+r.stdout[-1500:])
      return r.stdout
     sql(DDL+"\n"+SOURCE+"\n"+RULES)
     out=sql(TEST)
     for x in ("L2_UNBOUND_ALL_BLOCKED=40","E21_L2_SYNTHETIC_CHAIN_TESTED=PASS",
               "E21_L2_NO_REGISTRY_RESIDUE=0","E21_L2_NO_STEP_RESIDUE=0"):
      self.assertIn(x,out,out[-1600:])
     print("PASS_E21_L2_RULE_SCORE_NEGATIVES_PG"+version+"_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",n],capture_output=True,timeout=30)
if __name__=="__main__": unittest.main()
