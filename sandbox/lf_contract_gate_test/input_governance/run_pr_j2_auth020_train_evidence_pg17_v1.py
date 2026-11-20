#!/usr/bin/env python3
"""PR-J2: exact SQL in disposable real PG17 transaction, then independent readback.
The completed Train event is SYNTHETIC only in this fixture; remote SELECT is separate.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
BASE=Path(__file__).resolve().parent
OUT=ROOT/".lf_ci/pr_j2"
DOC=ROOT/"docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json"
HARNESS=BASE/"pr_i_auth020_projection_rollback.sql"
BASE_RUNNER=BASE/"run_pr_i_auth020_projection_pg17_v1.py"
FIXTURE=BASE/"pr_j2_auth020_evidence_fixture_pg17.sql"
MIGRATION=ROOT/"supabase/migrations/20261118103000_lf_ig_auth020_rule_contract_train_evidence_pr_j2_v1.sql"
MARKERS=("PR_I_BASELINE_PASS","PR_J2_NEG_TAMPERED_TRAIN_RECEIPT_REJECTED",
         "PR_J2_RULE_CONTRACT_LEVEL_TRAIN_EVIDENCE_INSERT_PASS",
         "PR_J2_TRANSACTION_INSERT_READBACK_PASS")
def sha(b):return hashlib.sha256(b).hexdigest()
def require(condition,msg):
 if not condition:raise RuntimeError(msg)
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 result={"status":"FAIL","scope":"RULE_CONTRACT_LEVEL","remote_supabase_written":False,
         "actual_train_fixture":"SYNTHETIC_FOR_SQL_GATE_TEST",
         "live_train_verified":"SELECT_ONLY_SEPARATELY","backend_e2e":"NOT_TESTED"}
 try:
  require(os.getenv("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","PR_J2_REPO_GUARD")
  require(os.getenv("GITHUB_EVENT_NAME")=="pull_request","PR_J2_EVENT_GUARD")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
  require(head==os.getenv("PR_J2_EXACT_HEAD") and len(head)==40,"PR_J2_EXACT_HEAD_DRIFT")
  result["exact_head"]=head
  for k,v in {"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres",
              "PGDATABASE":"postgres","PGPASSWORD":"pr_i_ephemeral_pg17_only"}.items():
   require(os.getenv(k)==v,"PR_J2_EPHEMERAL_GUARD_"+k)
  s=importlib.util.spec_from_file_location("baseline_runner",BASE_RUNNER)
  m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
  d=json.loads(DOC.read_text())
  require(d["patch_sha256"]=="adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02","PR_J2_PATCH_DRIFT")
  prefix=HARNESS.read_text().split("\nBEGIN;\nDO $trial$")
  require(len(prefix)==2,"PR_J2_SOURCE_FIXTURE_SPLIT_DRIFT")
  init=prefix[0]
  replacements={
   "@@AUTH020_BASELINE_ROW@@":m.dollar(d["source_full_row_for_isolated_pg17_fixture"],"auth20_orig"),
   "@@POLICY_DESCRIPTION@@":m.string(d["policy20_candidate_proposal"]["proposed_description"],"policy_current"),
   "@@POLICY_CONFIG@@":m.dollar(d["policy20_candidate_proposal"]["proposed_policy_config"],"policy_cfg"),
   "@@POLICY_PROVENANCE@@":m.dollar(d["policy20_candidate_proposal"]["source_parameter_provenance"],"policy_prov")
  }
  for k,v in replacements.items():
   require(init.count(k)==1,"PR_J2_FIXTURE_PLACEHOLDER_DRIFT:"+k)
   init=init.replace(k,v)
  migration=MIGRATION.read_text()
  require(migration.splitlines().count("BEGIN;")==1 and migration.splitlines().count("COMMIT;")==1,
          "PR_J2_EXACT_MIGRATION_TRANSACTION_DRIFT")
  require(migration.count("INSERT INTO public.lf_ig_functional_train_evidence_v1")==1,
          "PR_J2_EXACT_RECEIPT_INSERT_DRIFT")
  require("UPDATE lf_ops.reglas" not in migration and "INSERT INTO lf_ops.reglas" not in migration,
          "PR_J2_RULE_WRITE_NOT_ALLOWED")
  check=("\nDO $prj2_check$ BEGIN "
   "IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1 "
   "WHERE rule_code='B2B-RULE-AUTH-020')<>1 "
   "THEN RAISE EXCEPTION 'PR_J2_IN_TX_INSERT_MISSING'; END IF; "
   "RAISE NOTICE 'PR_J2_TRANSACTION_INSERT_READBACK_PASS'; "
   "END $prj2_check$;\nROLLBACK;")
  sql=init+"\n"+FIXTURE.read_text()+"\n"+migration.replace("COMMIT;",check,1)
  require(sql.splitlines().count("BEGIN;")==1 and sql.splitlines().count("ROLLBACK;")==1,
          "PR_J2_ROLLBACK_REQUIRED")
  (OUT/"trial.sql").write_text(sql)
  p=m.psql("-f",str(OUT/"trial.sql"))
  log=p.stdout+"\n"+p.stderr
  (OUT/"postgresql.log").write_text(log)
  result["sql_exit_code"]=p.returncode
  result["report_sha256"]=sha(log.encode())
  result["migration_sha256"]=sha(MIGRATION.read_bytes())
  result["assembled_sql_sha256"]=sha(sql.encode())
  result["checks"]={k:k in log for k in MARKERS}
  rb=m.psql("-At","-c",
    "SELECT CASE WHEN (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1)=0 "
    "AND (SELECT count(*) FROM lf_ops.reglas)=579 "
    "AND (SELECT count(*) FROM lf_ops.politicas_seguridad WHERE status='CANDIDATO')=1 "
    "AND (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='CANDIDATO')=1 "
    "AND public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')="
    "'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8' "
    "THEN 'PR_J2_INDEPENDENT_POST_ROLLBACK_PASS' ELSE 'PR_J2_DRIFT' END")
  result["readback"]=rb.stdout.strip()
  result["readback_exit_code"]=rb.returncode
  result["readback_sha256"]=sha((rb.stdout+"\n"+rb.stderr).encode())
  require(p.returncode==0,"PR_J2_SQL_TRANSACTION_FAIL")
  require(all(result["checks"].values()),"PR_J2_REQUIRED_CASES_MISSING")
  require(rb.returncode==0 and rb.stdout.strip()=="PR_J2_INDEPENDENT_POST_ROLLBACK_PASS",
          "PR_J2_INDEPENDENT_READBACK_FAIL")
  result["status"]="PASS_RULE_CONTRACT_LEVEL_PROTECTED_RECEIPT"
 except Exception as e:
  result["blocking_error"]=str(e)[:400]
 finally:
  (OUT/"report.json").write_text(json.dumps(result,sort_keys=True,indent=2)+"\n")
  print(json.dumps(result,sort_keys=True))
 return 0 if result["status"]=="PASS_RULE_CONTRACT_LEVEL_PROTECTED_RECEIPT" else 1
if __name__=="__main__":sys.exit(main())
