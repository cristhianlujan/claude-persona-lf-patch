#!/usr/bin/env python3
"""PR-J: exact-source RULE_CONTRACT_LEVEL PG17 probe; not production login E2E."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
BASE=Path(__file__).parent
OUT=ROOT/".lf_ci/pr_j_auth020"
DOC=ROOT/"docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json"
CASES=BASE/"pr_j_auth020_rule_contract_cases.sql"
HARNESS=BASE/"pr_i_auth020_projection_rollback.sql"
RUNNER=BASE/"run_pr_i_auth020_projection_pg17_v1.py"

MARKERS=[
 "PR_I_BASELINE_PASS",
 "PR_I_CONFIG_PROJECTION_PASS",
 "PR_I_REAL_POST_ROLLBACK_PASS",
 "PR_J_NEG_OPERATOR_PERMISSION_PASS",
 "PR_J_NEG_DNI_PASS",
 "PR_J_POS_ISSUE_DNI_TTL_PASS",
 "PR_J_NEG_PREMATURE_SESSION_PASS",
 "PR_J_NEG_REISSUED_OLD_KEY_PASS",
 "PR_J_NEG_EXPIRED_KEY_PASS",
 "PR_J_NEG_EXPIRED_REVERIFY_PASS",
 "PR_J_NEG_REUSE_PASS",
 "PR_J_NEG_PASSWORD_REQUIRED_PASS",
 "PR_J_NEG_ATOMIC_ROLLBACK_PASS",
 "PR_J_POS_ATOMIC_COMPLETION_PASS",
 "PR_J_NEG_MFA_BYPASS_PASS",
 "PR_J_RULE_CONTRACT_LEVEL_FUNCTIONAL_NEGATIVE_PASS",
]
def sha(data):
 return hashlib.sha256(data).hexdigest()
def require(ok, code):
 if not ok:raise RuntimeError(code)
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 report={"status":"FAIL","scope":"RULE_CONTRACT_LEVEL",
         "test_runtime":"ISOLATED_POSTGRESQL17_MODEL",
         "login_backend_e2e":"NOT_TESTED",
         "dni_real_verification":"NOT_TESTED",
         "key_email_delivery":"NOT_TESTED",
         "actual_login_mfa":"NOT_TESTED",
         "remote_supabase_written":False,
         "owner_v2_decision_recorded":False}
 try:
  require(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","PR_J_REPO_GUARD")
  require(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PR_J_PR_EVENT_ONLY")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
  require(head==os.environ.get("PR_J_EXACT_HEAD") and len(head)==40,"PR_J_HEAD_DRIFT")
  report["exact_head"]=head
  for k,v in {"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres",
              "PGDATABASE":"postgres","PGPASSWORD":"pr_i_ephemeral_pg17_only"}.items():
   require(os.environ.get(k)==v,"PR_J_EPHEMERAL_PG_GUARD_"+k)
  spec=importlib.util.spec_from_file_location("pr_i_baseline",RUNNER)
  baseline=importlib.util.module_from_spec(spec)
  spec.loader.exec_module(baseline)
  d=json.loads(DOC.read_text())
  p=d["governed_rule_patch"]
  require(d["patch_sha256"]=="adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02","PR_J_PATCH_HASH_DRIFT")
  require(d["candidate_snapshot_sha256"]=="16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061","PR_J_CANDIDATE_HASH_DRIFT")
  require(d["source"]["source_snapshot_sha256"]=="8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8","PR_J_SOURCE_HASH_DRIFT")
  replacement={
   "@@AUTH020_BASELINE_ROW@@":baseline.dollar(d["source_full_row_for_isolated_pg17_fixture"],"auth20_orig"),
   "@@RULE_PATCH@@":baseline.dollar(p,"auth20_patch"),
   "@@POLICY_DESCRIPTION@@":baseline.string(d["policy20_candidate_proposal"]["proposed_description"],"policy_current"),
   "@@POLICY_CONFIG@@":baseline.dollar(d["policy20_candidate_proposal"]["proposed_policy_config"],"policy_cfg"),
   "@@POLICY_PROVENANCE@@":baseline.dollar(d["policy20_candidate_proposal"]["source_parameter_provenance"],"policy_prov")
  }
  sql=HARNESS.read_text()
  for key,val in replacement.items():
   require(sql.count(key)==1,"PR_J_PLACEHOLDER_DRIFT_"+key)
   sql=sql.replace(key,val)
  require(sql.count("\nROLLBACK;\n")==1,"PR_J_ROLLBACK_ANCHOR_DRIFT")
  tests=CASES.read_text()
  require("COMMIT;" not in tests and "ROLLBACK;" not in tests and "BEGIN;" not in tests,"PR_J_CASE_TRANSACTION_DRIFT")
  sql=sql.replace("\nROLLBACK;\n","\n"+tests+"\nROLLBACK;\n",1)
  require(sql.splitlines().count("BEGIN;")==1 and sql.splitlines().count("ROLLBACK;")==1,
          "PR_J_MUST_USE_ONE_BEGIN_ROLLBACK")
  assembled=OUT/"contract_trial.sql"
  assembled.write_text(sql)
  trial=baseline.psql("-f",str(assembled))
  logs=trial.stdout+"\n"+trial.stderr
  (OUT/"postgresql.log").write_text(logs)
  report["sql_exit_code"]=trial.returncode
  report["pg_report_sha256"]=sha(logs.encode())
  report["source_json_sha256"]=sha(DOC.read_bytes())
  report["test_cases_sha256"]=sha(CASES.read_bytes())
  report["assembled_sql_sha256"]=sha(sql.encode())
  report["checks"]={k:k in logs for k in MARKERS}
  readback_sql=("SELECT CASE WHEN "
    "(SELECT count(*) FROM lf_ops.reglas)=1 AND "
    "(SELECT count(*) FROM lf_ops.politicas_seguridad WHERE status='CANDIDATO')=1 AND "
    "(SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='CANDIDATO')=1 AND "
    "public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')="
    "'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8' "
    "AND (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r "
    "WHERE codigo='B2B-RULE-AUTH-020')='7588d5a7de4d94a864fca9e63cd10ebe' "
    "THEN 'PR_J_INDEPENDENT_READBACK_RESTORED' ELSE 'PR_J_READBACK_DRIFT' END")
  rb=baseline.psql("-At","-c",readback_sql)
  report["readback"]=rb.stdout.strip()
  report["readback_exit_code"]=rb.returncode
  report["readback_sha256"]=sha((rb.stdout+"\n"+rb.stderr).encode())
  report["check_manifest_sha256"]=sha(json.dumps(report["checks"],sort_keys=True,separators=(",",":")).encode())
  require(trial.returncode==0,"PR_J_REAL_PG17_SQL_FAILED")
  require(all(report["checks"].values()),"PR_J_REQUIRED_FUNCTIONAL_NEGATIVE_CHECK_MISSING")
  require(rb.returncode==0 and rb.stdout.strip()=="PR_J_INDEPENDENT_READBACK_RESTORED","PR_J_SECOND_CONNECTION_READBACK_FAILED")
  report["functional_checks_status"]="PASS"
  report["negative_checks_status"]="PASS"
  report["pg_rollback_status"]="PASS"
  report["independent_readback_status"]="PASS"
  report["status"]="PASS_RULE_CONTRACT_LEVEL"
 except Exception as exc:
  report["blocking_error"]=str(exc)[:350]
 finally:
  (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
  print(json.dumps(report,sort_keys=True))
 return 0 if report["status"]=="PASS_RULE_CONTRACT_LEVEL" else 1
if __name__=="__main__":sys.exit(main())
