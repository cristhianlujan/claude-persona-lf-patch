#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, subprocess, sys, tempfile
from pathlib import Path
CLAIM="WF_DIAGNOSTIC_COMPLETE_V1"
REQUIRED={"test_identity","assertion_or_error","expected_actual","durable_artifact","correlation","owner_repair_resume"}
RUNNER=Path(__file__).with_name("run_gate_checks_v1.py")
def args():
    p=argparse.ArgumentParser(); p.add_argument("--artifact-dir",required=True); return p.parse_args()
def sql_json(query:str):
    proc=subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-At","-c",query],capture_output=True,text=True)
    if proc.returncode: raise RuntimeError(proc.stderr.strip()[-1200:])
    lines=[x for x in proc.stdout.splitlines() if x.strip()]
    return json.loads(lines[-1])
def main():
    a=args(); out=Path(a.artifact_dir); out.mkdir(parents=True,exist_ok=True)
    catalog=sql_json("""select jsonb_build_object(
      'claim_code',c.claim_code,'version',c.version,'status',c.status,'closure_rule',c.closure_rule,'source_ref',c.source_ref,
      'obligations',coalesce((select jsonb_agg(distinct o.obligation_code) from public.lf_assurance_obligation_catalog o where o.claim_code=c.claim_code and o.claim_version=c.version and o.required),'[]'::jsonb)
    ) from public.lf_assurance_claim_catalog c where c.claim_code='WF_DIAGNOSTIC_COMPLETE_V1' and c.version=1;""")
    closure=set((catalog.get("closure_rule") or {}).get("required") or [])
    assert closure==REQUIRED,(closure,REQUIRED)
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); failing=root/"test_known_assertion.py"; failing.write_text("assert {'actual':1} == {'expected':2}, 'expected 2 actual 1'\n",encoding="utf-8")
        diag=out/"controlled_failure"
        cmd=[sys.executable,str(RUNNER),"--gate-id","WF_DIAGNOSTIC_COMPLETE_CANARY","--step-id","claim_canary","--mode","COLLECT_ALL","--command-json",json.dumps({"argv":[sys.executable,str(failing)],"source_path":str(failing),"critical":False}),"--artifact-dir",str(diag),"--artifact-name","lf_gate_error_v1.json","--check-prefix","CLM","--owner","GATE_CHECK_OBSERVABILITY","--next-action","FIX_FAILED_CHECK_AND_RERUN"]
        proc=subprocess.run(cmd,capture_output=True,text=True)
        assert proc.returncode==1,(proc.stdout,proc.stderr)
        report=json.loads((diag/"lf_gate_error_v1.json").read_text(encoding="utf-8"))
        check=report["checks"][0]
        proof={
          "test_identity": bool(check.get("source_path") and check.get("check_id") and report.get("run_id") and report.get("job_id")),
          "assertion_or_error": bool(check.get("error_class") and (check.get("assertion_text") or check.get("error_summary"))),
          "expected_actual": bool(check.get("expected") and check.get("actual") and check.get("condition")),
          "durable_artifact": (diag/"lf_gate_error_v1.json").is_file() and bool(check.get("stdout_ref") and check.get("stderr_ref") and check.get("traceback_ref")),
          "correlation": bool(check.get("trace_id") and check.get("parent_trace_id") and check.get("source_commit") and check.get("tested_commit")),
          "owner_repair_resume": bool(check.get("owner")=="GATE_CHECK_OBSERVABILITY" and check.get("next_action"))
        }
        assert set(proof)==REQUIRED and all(proof.values()),proof
        receipt={"schema_version":"lf-claim-qualification/v1","claim_code":CLAIM,"claim_version":1,"claim_status":catalog.get("status"),"catalog_source_ref":catalog.get("source_ref"),"result":"PASS","closure_required":sorted(REQUIRED),"closure_proof":proof,"controlled_failure_report":str((diag/"lf_gate_error_v1.json").as_posix()),"source_sha":os.environ.get("GITHUB_SHA")}
        (out/"wf_diagnostic_claim_qualification_v1.json").write_text(json.dumps(receipt,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        print("WF_DIAGNOSTIC_COMPLETE_V1_QUALIFICATION_PASS")
if __name__=="__main__": main()
