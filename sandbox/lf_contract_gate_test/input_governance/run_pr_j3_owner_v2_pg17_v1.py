#!/usr/bin/env python3
"""PR-J3A exact-head real PG17 gate repair: no fictitious actual owner decision."""
import hashlib, json, os, re, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"sandbox/lf_contract_gate_test/input_governance"
SQL=ROOT/"supabase/migrations"
OUT=ROOT/".lf_ci/j3_owner_no_promotion"
BASE_DDL=SQL/"20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
PG=SQL/"20261118080200_lf_ig_owner_username_only_pr_g_v1.sql"
J3=SQL/"20261118115000_lf_ig_owner_v2_no_promotion_veto_removed_pr_j3a_v1.sql"
HARNESS=BASE/"pr_g_owner_username_only_rollback.sql"
def guard(x,s):
 if not x: raise RuntimeError(s)
def sha(x):return hashlib.sha256(x.encode()).hexdigest()
def psql(*args):
 return subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres",*args],capture_output=True,text=True,env=os.environ.copy(),timeout=90)
def extract_table(s,name):
 token="CREATE TABLE public."+name+"("
 a=s.find(token); b=s.find("\n);",a)
 guard(a>=0 and b>a,"BASELINE_TABLE_NOT_FOUND:"+name)
 return s[a:b+3]+";"
def extract_fn(s):
 a=s.find("CREATE FUNCTION public.lf_ig_rule_owner_decide_v2(")
 b=s.find("\n$fn$;",a)
 guard(a>=0 and b>a,"BASELINE_OWNER_DDL_NOT_FOUND")
 return s[a:b+len("\n$fn$;")]
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 report={"status":"FAIL","scope":"J3A_NO_PROMOTION_GATE_ONLY","pg":"REAL_ISOLATED_17",
         "prod_auth020_written":False,"real_owner_decision":False,"backend_e2e":"NOT_TESTED"}
 try:
  guard(os.getenv("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","REPO_MISMATCH")
  guard(os.getenv("GITHUB_EVENT_NAME")=="pull_request","PR_ONLY")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
  guard(head==os.getenv("J3_EXACT_HEAD") and len(head)==40,"HEAD_DRIFT")
  report["head"]=head
  for k,v in {"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres","PGDATABASE":"postgres","PGPASSWORD":"j3_ephemeral_pg17_only"}.items():
   guard(os.getenv(k)==v,"PG_LOCAL_ONLY_"+k)
  base=BASE_DDL.read_text(); pg=PG.read_text(); j3=J3.read_text(); fixture=HARNESS.read_text()
  init=fixture.split("\nDO $pre$\n",1)
  guard(len(init)==2,"PR_G_FIXTURE_SPLIT_MISSING")
  start=init[0]
  for k,v in {
   "@@PROJECT_OWNER_TABLE_DDL@@":extract_table(base,"lf_ig_project_owner_v2"),
   "@@OWNER_DECISION_TABLE_DDL@@":extract_table(base,"lf_ig_owner_decision_v2"),
   "@@SOURCE_OWNER_WRITER_DDL@@":extract_fn(base)
  }.items():
   guard(start.count(k)==1,"FIXTURE_PLACEHOLDER_"+k)
   start=start.replace(k,v)
  guard("DO $j3$" in j3 and "PR_J3_OWNER_V2_GUARD_ONLY_PASS" in j3 and
        "UPDATE lf_ops.reglas" not in j3 and "INSERT INTO lf_ops.reglas" not in j3 and
        "lf_ig_rule_finalize_v2" not in j3.split("DO $j3$",1)[1],
        "PR_J3_MIGRATION_SCOPE_DRIFT")
  block=r"""
BEGIN;
""" + pg + r"""
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{no_promotion}','false'::jsonb)
 WHERE execution_id='PRG-EPHEMERAL-PARENT';
DO $before$
DECLARE v_src text;
BEGIN
v_src:=encode(extensions.digest(convert_to(
 'LF_RULE_ABSENT:B2B-PRG-TEST-001','UTF8'),'sha256'),'hex');
BEGIN
 PERFORM public.lf_ig_rule_owner_decide_v2('PRG-EPHEMERAL-PARENT',
 'B2B-PRG-TEST-001',v_src,'{"usuario":"Cristhian Lujan","veredicto":"RECHAZAR"}');
 RAISE EXCEPTION 'J3_LEGACY_VETO_NOT_REPRODUCED';
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM NOT LIKE 'LF_IG_OWNER_PARENT_NOT_ADMITTED%'
 THEN RAISE EXCEPTION 'J3_UNEXPECTED_LEGACY_GATE:%',SQLERRM; END IF;
END;
RAISE NOTICE 'PR_J3_BEFORE_NO_PROMOTION_FALSE_BLOCKED_PASS';
END $before$;
""" + j3 + r"""
DO $after$
DECLARE v_src text; result jsonb;
BEGIN
 v_src:=encode(extensions.digest(convert_to(
  'LF_RULE_ABSENT:B2B-PRG-TEST-001','UTF8'),'sha256'),'hex');
 BEGIN
 PERFORM public.lf_ig_rule_owner_decide_v2('PRG-EPHEMERAL-PARENT',
 'B2B-PRG-TEST-001',v_src,'{"usuario":"other","veredicto":"RECHAZAR"}');
 RAISE EXCEPTION 'J3_WRONG_OWNER_WAS_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'LF_IG_OWNER_DECISION_INPUT_INVALID%'
  THEN RAISE; END IF;
 END;
 result:=public.lf_ig_rule_owner_decide_v2('PRG-EPHEMERAL-PARENT',
 'B2B-PRG-TEST-001',v_src,
 '{"usuario":"Cristhian Lujan","veredicto":"RECHAZAR"}');
 IF result->>'status'<>'RECHAZADO' OR result->>'write_performed'<>'false'
 OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>1
 OR (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'J3_FALSE_NATIVE_RUN_WRITER_NOT_VALID'; END IF;
 RAISE NOTICE 'PR_J3_AFTER_FALSE_NATIVE_RUN_ACCEPTED_PASS owner_only=true no_rule_write=true';
END $after$;
ROLLBACK;
DO $post$
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
   <> '2d6f2592e8f7e002ab29f212bcca0663'
 OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 OR (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'J3_ROLLBACK_NOT_RESTORED'; END IF;
 RAISE NOTICE 'PR_J3_ROLLBACK_PASS 0_decisions_3_rules_orig_function';
END $post$;
"""
  assembled=start+"\n"+block
  guard(assembled.splitlines().count("BEGIN;")==1 and assembled.splitlines().count("ROLLBACK;")==1,"TRANSACTION_NOT_SINGLE")
  (OUT/"trial.sql").write_text(assembled)
  run=psql("-f",str(OUT/"trial.sql"))
  log=run.stdout+"\n"+run.stderr
  (OUT/"postgresql.log").write_text(log)
  report["trial_exit"]=run.returncode;report["sql_log_sha256"]=sha(log)
  notices=[
   "PR_J3_BEFORE_NO_PROMOTION_FALSE_BLOCKED_PASS",
   "PR_J3_OWNER_V2_GUARD_ONLY_PASS",
   "PR_J3_AFTER_FALSE_NATIVE_RUN_ACCEPTED_PASS",
   "PR_J3_ROLLBACK_PASS"
  ]
  report["checks"]={k:k in log for k in notices}
  report["new_owner_function_md5"]=(re.findall(r"PR_J3_OWNER_V2_GUARD_ONLY_PASS before=[0-9a-f]{32} after=([0-9a-f]{32})",log) or [None])[0]
  rb=psql("-At","-c",
    "SELECT CASE WHEN (SELECT count(*) FROM public.lf_ig_owner_decision_v2)=0 "
    "AND (SELECT count(*) FROM lf_ops.reglas)=3 "
    "AND md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))="
    "'2d6f2592e8f7e002ab29f212bcca0663' "
    "THEN 'PR_J3_READBACK_RESTORED' ELSE 'PR_J3_READBACK_DRIFT' END")
  report["readback_exit"]=rb.returncode;report["readback"]=rb.stdout.strip()
  report["migration_sha256"]=sha(j3)
  guard(run.returncode==0 and all(report["checks"].values()),"PG17_ASSERTIONS_FAIL")
  guard(rb.returncode==0 and report["readback"]=="PR_J3_READBACK_RESTORED","INDEPENDENT_READBACK_FAIL")
  report["status"]="PASS_FIXTURE_GUARD"
 except Exception as e:report["blocker"]=str(e)[:500]
 finally:
  (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
  print(json.dumps(report,sort_keys=True))
 return 0 if report["status"]=="PASS_FIXTURE_GUARD" else 1
if __name__=="__main__":sys.exit(main())
