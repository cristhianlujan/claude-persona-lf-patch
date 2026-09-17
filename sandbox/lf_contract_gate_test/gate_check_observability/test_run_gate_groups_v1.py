#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNNER = HERE / "run_gate_groups_v1.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def fake_child(path: Path) -> None:
    write(path, '''#!/usr/bin/env python3
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser()
for x in ['gate-id','step-id','mode','artifact-dir','artifact-name','check-prefix','owner','next-action','run-id','job-id']: p.add_argument('--'+x)
p.add_argument('--command-json',action='append',default=[]); p.add_argument('--downstream-impact',action='append',default=[])
a=p.parse_args(); rows=[]
for i,raw in enumerate(a.command_json,1):
 s=json.loads(raw); rc=subprocess.run(s['argv']).returncode
 rows.append({'check_id':f'{a.check_prefix}-{i:03d}','check_status':'PASS' if rc==0 else 'FAIL','source_path':s['source_path'],'error_class':None if rc==0 else 'AssertionError','error_summary':None if rc==0 else 'AssertionError: boom','assertion_text':None if rc==0 else 'AssertionError: boom','failure_id':None if rc==0 else 'f'*64,'trace_id':f'T-{i}','traceback_ref':None if rc==0 else 'trace','source_commit':'a'*40,'tested_commit':'a'*40,'diagnostic_complete':True,'rc':rc})
result='FAIL' if any(x['check_status']=='FAIL' for x in rows) else 'PASS'
out={'gate_id':a.gate_id,'step_id':a.step_id,'owner':a.owner,'run_id':a.run_id,'gate_result':result,'diagnostic_complete':True,'executed_check_count':len(rows),'checks':rows}
d=Path(a.artifact_dir); d.mkdir(parents=True,exist_ok=True); (d/a.artifact_name).write_text(json.dumps(out))
raise SystemExit(1 if result=='FAIL' else 0)
''')


def manifest(root: Path, fail_second: bool = False) -> Path:
    tests = []
    for i in range(4):
        path = root / f"test_{i}.py"
        write(path, "assert False, 'boom'\n" if fail_second and i == 2 else "print('ok')\n")
        tests.append(str(path))
    value = {
        "schema_version": "lf-gate-group-manifest/v1",
        "consumer_code": "TEST",
        "gate_id": "TEST_GATE",
        "owner": "TEST_OWNER",
        "discover_glob": str(root / "test_*.py"),
        "expected_total_checks": 4,
        "groups": [
            {"group_id": "G01", "execution_class": "DETERMINISTIC", "tests": tests[:2]},
            {"group_id": "G02", "execution_class": "DETERMINISTIC", "tests": tests[2:]},
        ],
    }
    path = root / "manifest.json"
    write(path, json.dumps(value))
    return path


def run_case(root: Path, manifest_path: Path, child: Path, groups: list[str] | None = None):
    artifact = root / "artifact"
    cmd = [
        sys.executable, str(RUNNER),
        "--manifest", str(manifest_path),
        "--artifact-dir", str(artifact),
        "--runner", str(child),
        "--run-id", "R1",
        "--job-id", "J1",
    ]
    for group in groups or []:
        cmd += ["--group", group]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    summary = json.loads((artifact / "lf_gate_group_summary_v1.json").read_text(encoding="utf-8"))
    return proc, summary


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); child = root / "child.py"; fake_child(child); manifest_path = manifest(root)
        proc, summary = run_case(root, manifest_path, child)
        assert proc.returncode == 0, proc.stderr
        assert summary["full_coverage"] and summary["claim_ready"] and summary["excel_ready"]
        assert summary["prueba_a_nivel_general"]["executed_check_count"] == 4
        assert len(summary["prueba_paso_a_paso"]) == 2

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); child = root / "child.py"; fake_child(child); manifest_path = manifest(root, True)
        proc, summary = run_case(root, manifest_path, child)
        assert proc.returncode == 1
        assert summary["executed_group_ids"] == ["G01", "G02"]
        assert summary["gate_result"] == "FAIL"
        assert not summary["claim_ready"]
        assert summary["prueba_paso_a_paso"][1]["executed_check_count"] == 2

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); child = root / "child.py"; fake_child(child); manifest_path = manifest(root)
        proc, summary = run_case(root, manifest_path, child, ["G01"])
        assert proc.returncode == 0
        assert summary["targeted_repair_only"]
        assert not summary["full_coverage"]
        assert not summary["claim_ready"] and not summary["excel_ready"]

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); child = root / "child.py"; fake_child(child); manifest_path = manifest(root)
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        data["groups"][0]["tests"].append(data["groups"][1]["tests"][0])
        write(manifest_path, json.dumps(data))
        proc, summary = run_case(root, manifest_path, child)
        assert proc.returncode == 2
        assert summary["gate_result"] == "BLOCKED"
        assert "duplicate_test_assignment" in summary["error_summary"]

    print("LF_GATE_GROUP_ORCHESTRATOR_V1_TEST_PASS")


if __name__ == "__main__":
    main()
