#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "profile_runtime" / "runner.py"
FAKE = ROOT / "profile_runtime" / "tests" / "fake_executor.py"


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RUNNER), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        manifest = tmp_path / "manifest.json"
        request = tmp_path / "request.json"
        blocked_dir = tmp_path / "blocked"
        pass_dir = tmp_path / "pass"

        manifest.write_text(json.dumps({
            "manifest_version": "PROFILE_RUNTIME_MANIFEST_V1",
            "profile_id": "TEST-PROFILE",
            "profile_slug": "test_profile",
            "entrypoint": "profile_runtime/README.md",
            "load_paths": [],
            "adapters": [],
            "deterministic_validators": [],
            "router": {"path": "TEST -> PROFILE"},
            "semantic_judge": {"enabled": False}
        }), encoding="utf-8")
        request.write_text(json.dumps({
            "task_mode": "REVIEW",
            "user_request": "fresh harness transport test",
            "canonical_context": {"authority": "synthetic-test-only"},
            "canonical_source_refs": ["synthetic://test-context"]
        }), encoding="utf-8")

        blocked = run([
            "--manifest", str(manifest),
            "--request", str(request),
            "--activation-path", "BOTH",
            "--output-dir", str(blocked_dir),
        ])
        if blocked.returncode != 2:
            print("FAIL:no-executor must block", blocked.stdout, blocked.stderr)
            return 1
        blocked_receipt = json.loads((blocked_dir / "receipt.json").read_text(encoding="utf-8"))
        if blocked_receipt.get("status") != "BLOCKED":
            print("FAIL:blocked receipt status")
            return 1
        if blocked_receipt.get("behavioral_evidence_eligible") is not False:
            print("FAIL:blocked run cannot be behavioral evidence")
            return 1

        passed = run([
            "--manifest", str(manifest),
            "--request", str(request),
            "--activation-path", "BOTH",
            "--output-dir", str(pass_dir),
            "--executor-command", f"{sys.executable} {FAKE}",
            "--executor-kind", "SYNTHETIC_TEST",
        ])
        if passed.returncode != 0:
            print("FAIL:synthetic harness run", passed.stdout, passed.stderr)
            return 1
        receipt = json.loads((pass_dir / "receipt.json").read_text(encoding="utf-8"))
        if receipt.get("status") != "PASS_HARNESS_ONLY":
            print("FAIL:synthetic run must be PASS_HARNESS_ONLY")
            return 1
        if receipt.get("behavioral_evidence_eligible") is not False:
            print("FAIL:synthetic executor must never be behavioral evidence")
            return 1
        comparison = receipt.get("direct_router_comparison", {})
        if comparison.get("materially_consistent") is not True:
            print("FAIL:direct/router transport comparison")
            return 1
        for name in (
            "profile_execution_direct.raw.stdout.txt",
            "profile_execution_router.raw.stdout.txt",
            "parsed_direct.json",
            "parsed_router.json",
        ):
            if not (pass_dir / name).is_file():
                print(f"FAIL:missing evidence file:{name}")
                return 1

    print(json.dumps({
        "result": "PASS_HARNESS_ONLY",
        "assertions": [
            "missing real executor blocks",
            "raw output captured before parse",
            "direct/router are separate executions",
            "synthetic executor is never behavioral evidence"
        ]
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
