#!/usr/bin/env python3
"""PR-H: exact-head real ephemeral PG17 BEGIN/ROLLBACK of actual V2 finalizer."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
DEST_GLOB="*_lf_ig_functional_train_impact_gate_pr_h_v1.sql"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_h_functional_train_rollback.sql"
OUT=ROOT/".lf_ci/pr_h_functional_impact"
MARKERS=(
 "PR_H_PREIMAGE_PASS original_md5=9d1a771fe5dd8b466b76071b582f19fa owner_rows=0 change_rows=0 auth_rules=3",
 "PR_H_FOREIGN_USER_REJECTED_PASS",
 "PR_H_MISSING_CANDIDATE_HASH_REJECTED_PASS",
 "PR_H_IN_TRANSACTION_PASS functional_applied=true correct_candidate=true bad_run_denied=true null_hash_denied=true wrong_hash_denied=true foreign_owner_denied=true auth_unchanged=3",
 "PR_H_POST_ROLLBACK_PASS decisions=0 changes=0 auth_rules=3 impact_evidence_absent=true finalizer_original=true",
)
def sha(s): return hashlib.sha256(s).hexdigest()
def guard(ok,msg):
 if not ok: raise RuntimeError(msg)
def psql(*args):
 return subprocess.run(
  ["psql","-X","-v","ON_ERROR_STOP=1","-h","127.0.0.1","-p","5432",
   "-U","postgres","-d","postgres",*args],
  capture_output=True,text=True,env=os.environ.copy(),timeout=140,check=False)
def table(source,name):
 mark=f"CREATE TABLE public.{name}("
 start=source.find(mark)
 guard(start>=0,"PR_H_BASELINE_TABLE_MISSING:"+name)
 end=source.find("\n);",start)
 guard(end>start,"PR_H_BASELINE_TABLE_END_MISSING:"+name)
 return source[start:end+3]+";"
def finalizer(source):
 start=source.find("CREATE FUNCTION public.lf_ig_rule_finalize_v2(")
 guard(start>=0,"PR_H_BASELINE_FINALIZER_MISSING")
 end=source.find("\n$fn$;",start)
 guard(end>start,"PR_H_BASELINE_FINALIZER_END_MISSING")
 return source[start:end+len("\n$fn$;")]
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 report={"status":"FAIL","engine":"REAL_POSTGRESQL_17",
         "remote_supabase_written":False,
         "rule_or_policy_writes_on_remote":False,
         "test_fixture_not_real_owner_or_train_receipt":True}
 try:
  guard(os.getenv("GITHUB_EVENT_NAME")=="pull_request","PR_H_PR_ONLY")
  guard(os.getenv("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch",
        "PR_H_REPO_MISMATCH")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
  guard(bool(os.getenv("PR_H_EXACT_HEAD")) and head==os.getenv("PR_H_EXACT_HEAD"),
        "PR_H_HEAD_MISMATCH")
  report["candidate_head"]=head
  for k,v in (("PGHOST","127.0.0.1"),("PGPORT","5432"),
              ("PGUSER","postgres"),("PGDATABASE","postgres"),
              ("PGPASSWORD","pr_h_ephemeral_pg17_only")):
   guard(os.getenv(k)==v,"PR_H_LOCAL_PG_REQUIRED_"+k)
  migrations=list((ROOT/"supabase/migrations").glob(DEST_GLOB))
  guard(len(migrations)==1,"PR_H_MIGRATION_NOT_UNIQUE")
  origin=BASE.read_text()
  mig=migrations[0].read_text()
  harness=HARNESS.read_text()
  for required in ("9d1a771fe5dd8b466b76071b582f19fa",
                   "df1acd69a46b8bc4a6c257d95cc9a47a",
                   "PR_H_FINALIZER_REPLACEMENT_COUNT_2",
                   "PR_H_FINALIZER_PREIMAGE_DRIFT",
                   "LF_IG_VIGENTE_FUNCTIONAL_TRAIN_EVIDENCE_MISSING",
                   "LF_IG_VIGENTE_FUNCTIONAL_TRAIN_RUN_UNVERIFIED",
                   "LF_IG_VIGENTE_FUNCTIONAL_CANDIDATE_HASH_DRIFT"):
   guard(required in mig,"PR_H_MIGRATION_GUARD_MISSING:"+required)
  for forbidden in ("UPDATE lf_ops.reglas","DELETE FROM lf_ops.reglas",
                    "INSERT INTO lf_ops.reglas","ALTER TABLE public.lf_ig_rule_change_v2",
                    "ALTER TABLE public.lf_ig_owner_decision_v2",
                    "DROP FUNCTION","CREATE FUNCTION public.lf_ig_rule_owner_decide_v2",
                    "CREATE FUNCTION public.lf_ig_rule_child_guard_v2"):
   guard(forbidden not in mig,"PR_H_FORBIDDEN_SCOPE:"+forbidden)
  subs={
   "@@PROJECT_OWNER_TABLE_DDL@@":table(origin,"lf_ig_project_owner_v2"),
   "@@OWNER_DECISION_TABLE_DDL@@":table(origin,"lf_ig_owner_decision_v2"),
   "@@RULE_CHANGE_TABLE_DDL@@":table(origin,"lf_ig_rule_change_v2"),
   "@@SOURCE_FINALIZER_DDL@@":finalizer(origin),
   "@@PR_H_MIGRATION_SQL@@":mig,
  }
  script=harness
  for placeholder,src in subs.items():
   guard(script.count(placeholder)==1,"PR_H_SOURCE_TEMPLATE_DRIFT:"+placeholder)
   script=script.replace(placeholder,src)
  guard(script.splitlines().count("BEGIN;")==1
        and script.splitlines().count("ROLLBACK;")==1
        and script.splitlines().count("COMMIT;")==0,"PR_H_BEGIN_ROLLBACK_REQUIRED")
  report["sources"]={
   "baseline_sha256":sha(origin.encode()),"migration":migrations[0].name,
   "migration_sha256":sha(mig.encode()),"harness_sha256":sha(harness.encode()),
   "assembled_sha256":sha(script.encode()),
  }
  assembled=OUT/"transaction.sql"
  assembled.write_text(script)
  run=psql("-f",str(assembled))
  log=run.stdout+"\n"+run.stderr
  (OUT/"postgresql.log").write_text(log)
  report["sql_exit_code"]=run.returncode
  report["sql_log_sha256"]=sha(log.encode())
  report["assertions"]={x:x in log for x in MARKERS}
  check=psql("-At","-c",
   "SELECT CASE WHEN "
   "(SELECT count(*) FROM public.lf_ig_owner_decision_v2)=0 "
   "AND (SELECT count(*) FROM public.lf_ig_rule_change_v2)=0 "
   "AND (SELECT count(*) FROM lf_ops.reglas)=3 "
   "AND to_regclass('public.lf_ig_functional_train_evidence_v1') IS NULL "
   "AND md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))="
   "'9d1a771fe5dd8b466b76071b582f19fa' "
   "THEN 'PRH_RESTORED_0_0_3_ORIGINAL_MD5' ELSE 'PRH_ROLLBACK_DRIFT' END")
  report["readback_exit_code"]=check.returncode
  report["readback"]=check.stdout.strip()
  guard(run.returncode==0,"PR_H_REAL_SQL_FAILED")
  guard(all(report["assertions"].values()),"PR_H_TEST_ASSERTION_MISSING")
  guard(check.returncode==0 and report["readback"]=="PRH_RESTORED_0_0_3_ORIGINAL_MD5",
        "PR_H_READBACK_FAILED")
  report["status"]="PASS"
 except Exception as e:
  report["blocking_error"]=str(e)[:700]
 finally:
  (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
  print(json.dumps(report,sort_keys=True))
 return 0 if report["status"]=="PASS" else 1
if __name__=="__main__": sys.exit(main())
