#!/usr/bin/env python3
"""PR-I real PG17 snapshot projection & rollback. NOT real login QA or Train receipt."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
DOC=ROOT/"docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_i_auth020_projection_rollback.sql"
OUT=ROOT/".lf_ci/pr_i_auth020"
MARKERS=(
 "PR_I_BASELINE_PASS authentic_rule_source_sha_and_md5_match=true effective_permission38=0 policy20=CANDIDATO",
 "PR_I_CONFIG_PROJECTION_PASS before_sha=8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8 candidate_sha=16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061 ttl_ref=true rule_status=VIGENTE production_auth=false",
 "PR_I_REAL_POST_ROLLBACK_PASS rule_source_restored=true policy20=CANDIDATO permission38=CANDIDATO no_v2_receipts_created=true",
)

def die(condition,msg):
 if not condition:raise RuntimeError(msg)
def sha(data):return hashlib.sha256(data).hexdigest()
def dollar(obj,tag):
 value=json.dumps(obj,ensure_ascii=False,sort_keys=True)
 token="$"+tag+"$"
 die(token not in value,"PR_I_UNSAFE_SQL_LITERAL")
 return token+value+token+"::jsonb"
def string(value,tag):
 token="$"+tag+"$"
 die(token not in value,"PR_I_UNSAFE_POLICY_STRING")
 return token+value+token
def psql(*args):
 return subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1",
    "-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres",*args],
    env=os.environ.copy(),text=True,capture_output=True,timeout=110,check=False)
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 result={"status":"FAIL","engine":"REAL_POSTGRESQL_17",
   "execution_kind":"CONFIGURATION_PROJECTION_ONLY",
   "actual_login_runtime_functional_checks":"NOT_TESTED",
   "actual_login_runtime_negative_checks":"NOT_TESTED",
   "is_pr_h_functional_evidence":"NO",
   "remote_db_writes":False,
   "owner_v2_decision_recorded":False}
 try:
  die(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch",
     "REPOSITORY_NOT_AUTHORIZED")
  die(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PR_ONLY")
  head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],
          text=True).strip()
  die(bool(os.getenv("PR_I_EXACT_HEAD")) and head==os.getenv("PR_I_EXACT_HEAD"),
      "PR_I_EXACT_HEAD_DRIFT")
  result["candidate_head"]=head
  for k,v in (("PGHOST","127.0.0.1"),("PGPORT","5432"),
              ("PGUSER","postgres"),("PGDATABASE","postgres"),
              ("PGPASSWORD","pr_i_ephemeral_pg17_only")):
   die(os.getenv(k)==v,"PR_I_EPHEMERAL_PG_GUARD_"+k)
  doc=json.loads(DOC.read_text())
  patch=doc["governed_rule_patch"]
  src=doc["source_full_row_for_isolated_pg17_fixture"]
  pol=doc["policy20_candidate_proposal"]
  die(src["codigo"]=="B2B-RULE-AUTH-020" and src["id"]==439 and
      src["estado"]=="VIGENTE","PR_I_SOURCE_RULE_DRIFT")
  die(doc["status"]=="DRAFT_NOT_REGISTERED_NO_AUTH020_DB_WRITE",
      "PR_I_UNVERIFIED_AUTHORITATIVE_RECORD")
  die(doc["patch_sha256"]=="adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02",
      "PR_I_PATCH_SHA_DRIFT")
  die(not any(k in patch["changes"]["valor_config"] for k in
      ("hold_hours","human_approval_count_required",
       "current_authorized_recovery_profile_ids")),
      "PR_I_LEGACY_FIELDS_REMAIN")
  die("48 horas" not in patch["changes"]["descripcion"],
      "PR_I_DESCRIPTION_MENTIONS_48_HOUR_HOLD")
  replacements={
   "@@AUTH020_BASELINE_ROW@@":dollar(src,"auth20_orig"),
   "@@RULE_PATCH@@":dollar(patch,"auth20_patch"),
   "@@POLICY_DESCRIPTION@@":string(pol["proposed_description"],"policy_current"),
   "@@POLICY_CONFIG@@":dollar(pol["proposed_policy_config"],"policy_cfg"),
   "@@POLICY_PROVENANCE@@":dollar(pol["source_parameter_provenance"],"policy_prov")
  }
  # Policy fixture is intentionally CANDIDATO. This test does not UPDATE it.
  harness=HARNESS.read_text()
  for k,v in replacements.items():
   die(harness.count(k)==1,"PR_I_HARNESS_DRIFT_"+k)
   harness=harness.replace(k,v)
  die(harness.splitlines().count("BEGIN;")==1 and
      harness.splitlines().count("ROLLBACK;")==1 and
      harness.splitlines().count("COMMIT;")==0,
      "PR_I_REAL_ROLLBACK_NOT_CONFIRMED")
  sql=OUT/"transaction.sql"
  sql.write_text(harness)
  result["source_artifact"]={"patch_path":str(DOC.relative_to(ROOT)),
     "patch_file_sha256":sha(DOC.read_bytes()),
     "harness_sha256":sha(HARNESS.read_bytes()),
     "assembled_sql_sha256":sha(harness.encode())}
  run=psql("-f",str(sql))
  logs=run.stdout+"\n"+run.stderr
  (OUT/"postgresql.log").write_text(logs)
  result["sql_exit_code"]=run.returncode
  result["log_sha256"]=sha(logs.encode())
  result["assertions"]={m:m in logs for m in MARKERS}
  rb=psql("-At","-c",
    "SELECT CASE WHEN (SELECT count(*) FROM lf_ops.reglas)=1 "
    "AND (SELECT count(*) FROM lf_ops.politicas_seguridad WHERE status='CANDIDATO')=1 "
    "AND (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE status='CANDIDATO')=1 "
    "AND public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')="
    "'8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8' "
    "THEN 'PR_I_RESTORED_SOURCE_AUTH020_UNCHANGED' "
    "ELSE 'PR_I_SOURCE_DRIFT' END")
  result["readback_exit_code"]=rb.returncode
  result["readback"]=rb.stdout.strip()
  die(run.returncode==0,"PR_I_SQL_FAILED")
  die(all(result["assertions"].values()),"PR_I_REQUIRED_ASSERTIONS_MISSING")
  die(rb.returncode==0 and result["readback"]=="PR_I_RESTORED_SOURCE_AUTH020_UNCHANGED",
      "PR_I_INDEPENDENT_READBACK_FAILED")
  result["status"]="PASS_CONFIG_ONLY"
 except Exception as e:
  result["blocking_error"]=str(e)[:500]
 finally:
  (OUT/"report.json").write_text(json.dumps(result,sort_keys=True,indent=2)+"\n")
  print(json.dumps(result,sort_keys=True))
 return 0 if result["status"]=="PASS_CONFIG_ONLY" else 1

if __name__=="__main__":sys.exit(main())
