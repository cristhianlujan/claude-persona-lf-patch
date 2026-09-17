#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRIDGE = HERE / "persist_gate_failures_to_ekb_v1.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def fixture(root: Path) -> Path:
    child = root / "groups/G01/lf_gate_error_v1.json"
    child.parent.mkdir(parents=True)
    report = {
        "gate_id": "TEST::G01",
        "owner": "PROFILE_RUNTIME",
        "run_id": "99",
        "gate_result": "FAIL",
        "checks": [{
            "check_id": "G01-001",
            "check_status": "FAIL",
            "source_path": "x/test_a.py",
            "error_class": "AssertionError",
            "error_summary": "AssertionError: expected",
            "assertion_text": "AssertionError: expected",
            "failure_id": "f" * 64,
            "trace_id": "T1",
            "traceback_ref": "trace",
            "source_commit": "a" * 40,
            "tested_commit": "a" * 40,
        }],
    }
    write(child, json.dumps(report))
    summary = {
        "gate_id": "TEST",
        "owner": "PROFILE_RUNTIME",
        "run_id": "99",
        "gate_result": "FAIL",
        "groups": [{"group_id": "G01", "result": "FAIL", "report_ref": str(child)}],
    }
    summary_path = root / "summary.json"
    write(summary_path, json.dumps(summary))
    return summary_path


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); summary = fixture(root); out = root / "out"
        proc = subprocess.run([
            sys.executable, str(BRIDGE), "--summary", str(summary),
            "--artifact-dir", str(out), "--emit-only",
        ], capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr
        candidates = json.loads((out / "ekb_candidates_v1.json").read_text(encoding="utf-8"))
        assert candidates["candidate_count"] == 1
        item = candidates["candidates"][0]
        assert item["codigo"].startswith("CI-GATE-G01-")
        assert item["root_cause_family"] == "UNCLASSIFIED_WITH_REASON"
        assert item["detectability"] == "LOUD_EARLY"

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); summary = fixture(root); out = root / "out"; fake = root / "psql"; log = root / "sql.json"
        write(fake, '''#!/usr/bin/env python3
import json,os,sys
open(os.environ['FAKE_PSQL_LOG'],'w').write(json.dumps(sys.argv[1:]))
print('{"writer":"public.lf_write_pipeline_ekb_v1","classification":"RECURRENCE"}')
''')
        fake.chmod(0o755)
        env = {**os.environ, "PGPASSWORD": "secret", "FAKE_PSQL_LOG": str(log)}
        proc = subprocess.run([
            sys.executable, str(BRIDGE), "--summary", str(summary),
            "--artifact-dir", str(out), "--write", "--psql", str(fake),
            "--execution-id", "EXEC-1",
        ], env=env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr
        argv = json.loads(log.read_text(encoding="utf-8"))
        sql = argv[argv.index("-c") + 1]
        assert "lf_write_pipeline_ekb_v1" in sql
        assert "insert into" not in sql.lower() and "update " not in sql.lower()
        receipt = json.loads((out / "ekb_persistence_receipt_v1.json").read_text(encoding="utf-8"))
        assert receipt["status"] == "EKB_PERSISTED"

    source = BRIDGE.read_text(encoding="utf-8").lower()
    assert "insert into public.lf_error_knowledge" not in source
    assert "update public.lf_error_knowledge" not in source
    print("LF_GATE_EKB_BRIDGE_V1_TEST_PASS")


if __name__ == "__main__":
    main()
