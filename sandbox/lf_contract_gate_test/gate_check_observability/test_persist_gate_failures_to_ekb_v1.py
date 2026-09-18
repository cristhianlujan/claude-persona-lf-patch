#!/usr/bin/env python3
from __future__ import annotations

import json
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
        root = Path(td)
        summary = fixture(root)
        out = root / "out"
        proc = subprocess.run([
            sys.executable,
            str(BRIDGE),
            "--summary",
            str(summary),
            "--artifact-dir",
            str(out),
            "--emit-only",
        ], capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr
        candidates = json.loads((out / "ekb_candidates_v1.json").read_text(encoding="utf-8"))
        assert candidates["candidate_count"] == 1
        assert candidates["productive_target"] == "public.lf_operation_gate_check_results"
        assert candidates["productive_ingress"] == "public.lf_record_gate_checks_v1"
        assert candidates["pre_ekb_gate"] == "PRE_EKB_GATE"
        assert candidates["direct_ekb_write_allowed"] is False
        item = candidates["candidates"][0]
        assert item["codigo"].startswith("CI-GATE-G01-")
        assert item["root_cause_family"] == "UNCLASSIFIED_WITH_REASON"
        assert item["detectability"] == "LOUD_EARLY"

        receipt = json.loads((out / "ekb_persistence_receipt_v1.json").read_text(encoding="utf-8"))
        assert receipt["status"] == "EMIT_ONLY_LEDGER_REQUIRED"
        assert receipt["productive_target"] == "public.lf_operation_gate_check_results"
        assert receipt["productive_ingress"] == "public.lf_record_gate_checks_v1"
        assert receipt["pre_ekb_gate"] == "PRE_EKB_GATE"
        assert receipt["direct_ekb_write_allowed"] is False

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        summary = fixture(root)
        out = root / "out"
        proc = subprocess.run([
            sys.executable,
            str(BRIDGE),
            "--summary",
            str(summary),
            "--artifact-dir",
            str(out),
            "--write",
        ], capture_output=True, text=True)
        assert proc.returncode != 0
        assert "--write" in proc.stderr

    source = BRIDGE.read_text(encoding="utf-8").lower()
    for forbidden in (
        "lf_write_pipeline_ekb_v1",
        "pgpassword",
        "canonical_writer_sql",
        "subprocess.run",
        "insert into transversal.error_knowledge",
        "update transversal.error_knowledge",
        "insert into public.lf_error_knowledge",
        "update public.lf_error_knowledge",
    ):
        assert forbidden not in source, forbidden

    assert "public.lf_operation_gate_check_results" in source
    assert "public.lf_record_gate_checks_v1" in source
    assert "pre_ekb_gate" in source
    print("LF_GATE_EKB_BRIDGE_EMIT_ONLY_V2_TEST_PASS")


if __name__ == "__main__":
    main()
