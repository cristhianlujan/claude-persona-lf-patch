"""PG17.6/PG18.7 exact source preimages -> target migration -> negative + ROLLBACK.

All DB instances are disposable docker instances, no production credentials.
"""
import shutil
import subprocess
import time
import uuid
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixture_router_ig_preimage_pgdual_v1.sql"
MIGRATION=ROOT/"supabase/migrations/20261114190000_lf_router_ig_skill_policy_only_v1.sql"
ROUTER="public.lf_router_resolve_core_v1"
DERIVE="programacion.fn_lf_router_input_governance_derive_v1"
ADAPTER="programacion.fn_lf_profile_adapter_input_governance_resolve_v1"
PROFILE_RESOLVER="programacion.fn_lf_profile_input_governance_resolve_v1"

def func_source(fn):
 return "(SELECT pg_get_functiondef(to_regprocedure('"+fn+"("+("text,text,text,text,text" if fn==ROUTER else "text,text,jsonb,text" if fn==PROFILE_RESOLVER else "text,jsonb,text")+ ")')))"

class RouterIgPolicyPgDual(unittest.TestCase):
 def run_pg(self,tag,version):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  name="lf-router-ig-"+uuid.uuid4().hex[:11]
  start=subprocess.run(["docker","run","--rm","-d","--name",name,
     "-e","POSTGRES_PASSWORD=postgres",tag],capture_output=True,text=True,timeout=180)
  self.assertEqual(start.returncode,0,start.stderr[-1100:])
  try:
   for _ in range(95):
    check=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=7)
    if check.returncode==0:break
    time.sleep(1)
   else:self.fail("POSTGRES_NEVER_READY")
   def query(script,expected_error=None):
    p=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq","-v","ON_ERROR_STOP=1",
       "-U","postgres","-d","postgres"],input=script,text=True,capture_output=True,timeout=145)
    if expected_error:
     self.assertNotEqual(p.returncode,0,"NEGATIVE_NOT_REJECTED")
     self.assertIn(expected_error,p.stderr[-15000:])
    else:self.assertEqual(p.returncode,0,p.stderr[-6000:])
    return p.stdout.strip()
   self.assertTrue(query("SHOW server_version_num;").startswith(version))
   fixture=BASE.read_text(encoding="utf-8")
   # The source fixture is from pg_get_functiondef, not fabricated PLpgSQL.
   self.assertEqual(fixture.count("CREATE OR REPLACE FUNCTION"),4)
   query(fixture)
   sql=MIGRATION.read_text(encoding="utf-8")
   self.assertIn("LF_ROUTER_IG_SOURCE_DEPENDENCY_REMAINED",sql)
   self.assertIn("LF_IG_POLICY_9_PLUS_1_PREIMAGE_DRIFT",sql)
   self.assertIn("ACTION_AUTHORIZATION_GATE",sql)
   inner=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
   before=query("SELECT md5("+func_source(ROUTER)+");")
   self.assertEqual(before,"ebb137df72e52c016e0e66c24035aeaf")
   test_sql="BEGIN;\n"+inner+"""
SELECT CASE WHEN
  position('fn_lf_router_input_governance_derive_v1' in """+func_source(ROUTER)+""")=0
  AND position('v_input_governance' in """+func_source(ROUTER)+""")=0
  THEN 'PASS_ROUTER_SOURCE_NO_IG' ELSE 'FAIL_ROUTER_STILL_CALLS_IG' END;
SELECT count(*)||':'||count(*) FILTER (WHERE selection_mode='SEMANTIC_OPTIONAL')||':'||
  count(*) FILTER (WHERE applicability_contract->>'only_if_applicable'='false')
  FROM public.lf_skill_selector_policy_v1 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
SELECT CASE WHEN
  position('BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS' in """+func_source(ADAPTER)+""")>0
  AND position('''decision'',''FINDING'',''continuation_allowed'',true' in """+func_source(ADAPTER)+""")>0
  AND position('''decision'',''FINDING'',''continuation_allowed'',true' in """+func_source(DERIVE)+""")>0
  AND position('BLOCK_INPUT_GOVERNANCE_EFFECT_AUTHORITY' in """+func_source(ADAPTER)+""")>0
  AND position('''continuation_allowed'',false' in """+func_source(ADAPTER)+""")>0
  AND position('lf_activo_relaciones' in """+func_source(PROFILE_RESOLVER)+""")=0
  AND position('lf_skill_selector_policy_v1' in """+func_source(PROFILE_RESOLVER)+""")>0
  AND position('''continuation_allowed'',false' in """+func_source(PROFILE_RESOLVER)+""")>0
  THEN 'PASS_IG_CONTENT_FAIL_OPEN_AUTHORITY_FAIL_CLOSED'
  ELSE 'FAIL_IG_CONTENT_OR_FLOW_CLASSIFICATION' END;
SELECT programacion.fn_lf_profile_input_governance_resolve_v1(
 'regla de carga','ACT-0051','{}'::jsonb,'CONTEXT_PACK')->>'blocking_code';
SELECT programacion.fn_lf_profile_input_governance_resolve_v1(
 'regla de carga','ACT-0051','{}'::jsonb,'CONSUMER_NOT_ALLOWED')->>'blocking_code';
DO $lf_each_path$
DECLARE
 r record; src text; spot integer; segment text; seen boolean; cnt integer:=0;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_ADAPTER_METADATA_INVALID',false),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED',false),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_ADAPTER_CONTRACT_INVALID',false),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_EFFECT_AUTHORITY',false),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_EVALUATION_FAILED',false),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_RUNTIME_REQUIRED',true),
  ('programacion.fn_lf_profile_adapter_input_governance_resolve_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_CONTENT_EXCEPTION',true),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_ADAPTER_METADATA_INVALID',false),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_PROFILE_ONLY',false),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED',false),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_ADAPTER_CONTRACT_INVALID',false),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',true),
  ('programacion.fn_lf_router_input_governance_derive_v1(text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',true),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_NOT_SEMANTICALLY_RESOLVED',false),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SEMANTIC_RECEIPT_INVALID',false),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_EFFECT_AUTHORITY',false),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED',false),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',true),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',true),
  ('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure,'BLOCK_PROFILE_INPUT_GOVERNANCE',true)
 ) t(fn,code,expected_continuation)
 LOOP
   SELECT pg_get_functiondef(r.fn) INTO src;
   spot:=strpos(src,'''blocking_code'', '''||r.code||'''');
   IF spot=0 THEN RAISE EXCEPTION 'IG_PATH_CODE_ABSENT:%',r.code; END IF;
   segment:=substr(src,spot,440);
   IF strpos(segment,'''continuation_allowed'',true')>0
      OR strpos(segment,'''continuation_allowed'', true')>0 THEN
     seen:=true;
   ELSIF strpos(segment,'''continuation_allowed'',false')>0
      OR strpos(segment,'''continuation_allowed'', false')>0 THEN
     seen:=false;
   ELSE RAISE EXCEPTION 'IG_PATH_CONTINUATION_ABSENT:%',r.code;
   END IF;
   IF seen IS DISTINCT FROM r.expected_continuation THEN
     RAISE EXCEPTION 'IG_PATH_WRONG_CLASSIFICATION:%,expected=%,observed=%',
       r.code,r.expected_continuation,seen;
   END IF;
   cnt:=cnt+1;
 END LOOP;
 IF cnt<>26 THEN RAISE EXCEPTION 'IG_PATH_COUNT_MISMATCH:%',cnt; END IF;
 RAISE NOTICE 'PASS_IG_BLOCK_AND_FINDING_SOURCE_PATHS_%',cnt;
END $lf_each_path$;
SELECT 'PASS_IG_BLOCK_AND_FINDING_SOURCE_PATHS_26';
ROLLBACK;
SELECT md5("""+func_source(ROUTER)+""");
SELECT count(*) FILTER (WHERE selection_mode='DETERMINISTIC_REQUIRED')||':'||
  count(*) FILTER (WHERE selection_mode='SEMANTIC_OPTIONAL')
  FROM public.lf_skill_selector_policy_v1 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
"""
   out=query(test_sql).splitlines()
   for marker in ("PASS_ROUTER_SOURCE_NO_IG","10:10:10",
                  "PASS_IG_CONTENT_FAIL_OPEN_AUTHORITY_FAIL_CLOSED",
                  "9:1",before,
                  "BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_NOT_SEMANTICALLY_RESOLVED",
                  "BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED",
                  "PASS_IG_BLOCK_AND_FINDING_SOURCE_PATHS_26"):
     self.assertIn(marker,out,out)
   # Policy preimage drift must fail closed with no writes.
   corrupt="BEGIN; UPDATE public.lf_skill_selector_policy_v1 SET selection_mode='SEMANTIC_OPTIONAL' WHERE profile_code='ACT-0051';\n"+inner
   query(corrupt,expected_error="LF_IG_POLICY_9_PLUS_1_PREIMAGE_DRIFT")
   self.assertEqual(query("SELECT count(*) FROM public.lf_skill_selector_policy_v1 WHERE selection_mode='DETERMINISTIC_REQUIRED';"),"9")
   print("PASS_LF_ROUTER_IG_POLICY_PG_ROLLBACK_"+tag,flush=True)
  finally:
   subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=45)
 def test_pg176(self):self.run_pg("postgres:17.6","170006")
 def test_pg187(self):self.run_pg("postgres:18.7","180007")

if __name__=="__main__":unittest.main()
