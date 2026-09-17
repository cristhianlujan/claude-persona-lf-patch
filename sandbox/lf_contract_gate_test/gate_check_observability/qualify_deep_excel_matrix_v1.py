#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os
from pathlib import Path
def args():
    p=argparse.ArgumentParser(); p.add_argument("--matrix",required=True); p.add_argument("--summary",required=True); p.add_argument("--artifact-dir",required=True); return p.parse_args()
def main():
    a=args(); matrix=json.loads(Path(a.matrix).read_text(encoding="utf-8")); summary=json.loads(Path(a.summary).read_text(encoding="utf-8"))
    rows=matrix["rows"]; required=matrix["required_columns"]; fronts=matrix["required_fronts"]
    errors=[]
    if [r["front"] for r in rows]!=fronts: errors.append("FRONT_ORDER_OR_SET_MISMATCH")
    for r in rows:
        missing=[c for c in required if not r.get(c)]
        if missing: errors.append(f"{r.get('front')}:MISSING:"+",".join(missing))
        if r.get("Resultado")!="PASS": errors.append(f"{r.get('front')}:RESULT_NOT_PASS")
    general=summary.get("prueba_a_nivel_general") or {}
    if summary.get("gate_result")!="PASS": errors.append("GROUP_GATE_NOT_PASS")
    if summary.get("full_coverage") is not True: errors.append("FULL_COVERAGE_FALSE")
    if summary.get("claim_ready") is not True: errors.append("CLAIM_READY_FALSE")
    if summary.get("excel_ready") is not True: errors.append("EXCEL_READY_FALSE")
    if int(general.get("expected_check_count") or 0)!=46 or int(general.get("executed_check_count") or 0)!=46: errors.append("REAL_RUNNER_NOT_46_OF_46")
    if int(general.get("expected_group_count") or 0)!=10 or int(general.get("executed_group_count") or 0)!=10: errors.append("GROUPS_NOT_10_OF_10")
    out=Path(a.artifact_dir); out.mkdir(parents=True,exist_ok=True)
    receipt={"schema_version":"lf-deep-excel-qualification/v1","capability_code":matrix["capability_code"],"result":"PASS" if not errors else "FAIL","required_columns":len(required),"fronts":fronts,"matrix_rows":len(rows),"real_groups_expected":general.get("expected_group_count"),"real_groups_executed":general.get("executed_group_count"),"real_checks_expected":general.get("expected_check_count"),"real_checks_executed":general.get("executed_check_count"),"full_coverage":summary.get("full_coverage"),"source_sha":os.environ.get("GITHUB_SHA"),"errors":errors}
    (out/"deep_excel_qualification_v1.json").write_text(json.dumps(receipt,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    if errors: raise SystemExit("DEEP_EXCEL_MATRIX_QUALIFICATION_FAIL "+",".join(errors))
    print("DEEP_EXCEL_MATRIX_QUALIFICATION_PASS rows=9 columns=23 groups=10 checks=46")
if __name__=="__main__": main()
