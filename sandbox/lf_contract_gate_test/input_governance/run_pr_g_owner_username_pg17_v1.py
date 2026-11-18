#!/usr/bin/env python3
"""PR-G exact-head real PostgreSQL 17 isolated trial of owner username-only V2."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
DEST_GLOB="*_lf_ig_owner_username_only_pr_g_v1.sql"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_g_owner_username_only_rollback.sql"
OUT=ROOT/".lf_ci/pr_g_username_decision"
MARKERS=(
 "PR_G_PREIMAGE_PASS source_function_md5=2d6f2592e8f7e002ab29f212bcca0663 decisions=0",
 "PR_G_IN_TRANSACTION_PASS username_only=1 generated_sha=true real_postgresql=true foreign_user_denied=true rules_unchanged=3",
 "PR_G_REAL_POST_ROLLBACK_PASS decisions=0 legacy_function_restored=true auth_rules=3",
)
def sha(data):
 return hashlib.sha256(data).hexdigest()
def guard(ok,code):
 if not ok: raise RuntimeError(code)
def psql(*args):
 return subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres",*args],
  capture_output=True,text=True,env=os.environ.copy(),timeout=130,check=False)
def extract_table(source,name):
 needle="CREATE TABLE public."+name+"("
 start=source.find(needle)
 guard(start>=0,"PR_G_BASELINE_TABLE_MISSING_"+name)
 end=source.find("\n);",start)
 guard(end>start,"PR_G_BASELINE_TABLE_END_MISSING_"+name)
 frag=source[start:end+3]+";"
 guard(frag.count("CREATE TABLE ")==1,"PR_G_BASELINE_TABLE_AMBIGUOUS_"+name)
 return frag
def extract_fn(source):
 start=source.find("CREATE FUNCTION public.lf_ig_rule_owner_decide_v2(")
 guard(start>=0,"PR_G_BASELINE_OWNER_FUNCTION_MISSING")
 end=source.find("\n$fn$;",start)
 guard(end>start,"PR_G_BASELINE_OWNER_END_MISSING")
 return source[start:end+len("\n$fn$;")]
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 report={"status":"FAIL","engine":"REAL_POSTGRESQL_17","isolated_runner":True,
         "remote_supabase_written":False,"live_user_decision_recorded":False}
 try:
  guard(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PR_ONLY")
  guard(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","REPO_DRIFT")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
  guard(bool(os.getenv("PR_G_EXACT_HEAD")) and head==os.getenv("PR_G_EXACT_HEAD"),"PR_G_HEAD_DRIFT")
  report["candidate_head"]=head
  for k,v in (("PGHOST","127.0.0.1"),("PGPORT","5432"),("PGUSER","postgres"),
              ("PGDATABASE","postgres"),("PGPASSWORD","pr_g_ephemeral_pg17_only")):
   guard(os.getenv(k)==v,"PR_G_LOCAL_PG_ONLY_"+k)
  matches=list((ROOT/"supabase/migrations").glob(DEST_GLOB))
  guard(len(matches)==1,"PR_G_MIGRATION_MUST_EXIST_UNIQUE")
  migration=matches[0].read_text()
  origin=BASE.read_text()
  harness=HARNESS.read_text()
  guards=[
    "PR_G_OWNER_WRITER_PREIMAGE_MD5_DRIFT",
    "PR_G_IDENTITY_CONSTRAINT_PREIMAGE_DRIFT",
    "PR_G_OWNER_WRITER_POSTIMAGE_MD5_DRIFT",
    "PR_G_IDENTITY_CONSTRAINT_POSTIMAGE_MD5_DRIFT",
    "PR_G_OWNER_EXECUTE_ACL_DRIFT"
  ]
  guard(all(g in migration for g in guards),"PR_G_MIGRATION_GUARDS_INCOMPLETE")
  guard("lf_ig_rule_finalize_v2" in migration and "No alteration" in migration,
        "PR_G_MIGRATION_DOC_SCOPE_MISSING")
  for forbidden in ("UPDATE lf_ops.reglas","INSERT INTO lf_ops.reglas","DROP FUNCTION",
                    "CREATE OR REPLACE FUNCTION public.lf_ig_rule_finalize_v2"):
   guard(forbidden not in migration,"PR_G_AUTH_RULE_OR_GATE_SCOPE_DRIFT_"+forbidden)
  substitutions={
   "@@PROJECT_OWNER_TABLE_DDL@@":extract_table(origin,"lf_ig_project_owner_v2"),
   "@@OWNER_DECISION_TABLE_DDL@@":extract_table(origin,"lf_ig_owner_decision_v2"),
   "@@SOURCE_OWNER_WRITER_DDL@@":extract_fn(origin),
   "@@PR_G_MIGRATION_SQL@@":migration,
  }
  sql=harness
  for k,v in substitutions.items():
   guard(sql.count(k)==1,"PR_G_PLACEHOLDER_MISMATCH_"+k)
   sql=sql.replace(k,v)
  guard(sql.splitlines().count("BEGIN;")==1 and sql.splitlines().count("ROLLBACK;")==1
        and sql.splitlines().count("COMMIT;")==0,"PR_G_TRANSACTION_SCOPE_INVALID")
  report["sources"]={
   "baseline_migration":BASE.name,"baseline_sha256":sha(origin.encode()),
   "migration":matches[0].name,"migration_sha256":sha(migration.encode()),
   "harness_sha256":sha(harness.encode()),"assembled_sha256":sha(sql.encode()),
  }
  script=OUT/"transaction.sql"
  script.write_text(sql)
  run=psql("-f",str(script))
  combined=run.stdout+"\n"+run.stderr
  (OUT/"postgresql.log").write_text(combined)
  report["sql_exit_code"]=run.returncode
  report["sql_log_sha256"]=sha(combined.encode())
  report["assertions"]={m:m in combined for m in MARKERS}
  readback=psql("-At","-c",
    "SELECT CASE WHEN (SELECT count(*) FROM public.lf_ig_owner_decision_v2)=0 "
    "AND md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))="
    "'2d6f2592e8f7e002ab29f212bcca0663' "
    "AND (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')=3 "
    "THEN 'PRG_RESTORED_0_3_ORIGINAL_MD5' ELSE 'PRG_NOT_RESTORED' END")
  report["readback_exit_code"]=readback.returncode
  report["readback"]=readback.stdout.strip()
  guard(run.returncode==0,"PR_G_REAL_SQL_FAILED")
  guard(all(report["assertions"].values()),"PR_G_REAL_ASSERTIONS_MISSING")
  guard(readback.returncode==0 and report["readback"]=="PRG_RESTORED_0_3_ORIGINAL_MD5",
        "PR_G_POST_ROLLBACK_INDEPENDENT_READBACK_FAILED")
  report["status"]="PASS"
 except Exception as e:
  report["blocking_error"]=str(e)[:650]
 finally:
  (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
  print(json.dumps(report,sort_keys=True))
 return 0 if report["status"]=="PASS" else 1
if __name__=="__main__":
 sys.exit(main())
