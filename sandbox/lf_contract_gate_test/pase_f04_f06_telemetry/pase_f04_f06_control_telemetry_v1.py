#!/usr/bin/env python3
"""F04/F06 control runner adapter with the F09-015 telemetry envelope shape."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[3]
TELEMETRY_SCHEMA = "pase_f09_015_telemetry_v1"
TELEMETRY_STAGES = ("transport", "queries", "control_execution", "judges", "evidence_persistence", "total")
NOT_APPLICABLE = "NOT_APPLICABLE"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def digest(value: object) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(count: int, duration_ms: float, byte_count: int) -> dict:
    return {"count": count, "duration_ms": round(max(0.0, duration_ms), 3), "bytes": max(0, byte_count)}


def run_control(*, control_id: str, run_identity: dict, execute: Callable[[], dict],
                judge: Callable[[dict], dict]) -> dict:
    """Time producer, independent verdict mapping and evidence envelope packing."""
    started_at = utc_now()
    total_start = time.perf_counter_ns()
    producer_start = time.perf_counter_ns()
    result = execute()
    producer_ms = (time.perf_counter_ns() - producer_start) / 1_000_000
    judge_start = time.perf_counter_ns()
    verdict = judge(result)
    judge_ms = (time.perf_counter_ns() - judge_start) / 1_000_000
    persistence_start = time.perf_counter_ns()
    evidence_bytes = len(json.dumps({"result": result, "verdict": verdict}, sort_keys=True,
                                    separators=(",", ":")).encode())
    persistence_ms = (time.perf_counter_ns() - persistence_start) / 1_000_000
    finished_at = utc_now()
    stages = {
        "transport": stage(0, 0, 0),
        "queries": stage(0, 0, 0),
        "control_execution": stage(1, producer_ms, len(json.dumps(result, sort_keys=True).encode())),
        "judges": stage(1, judge_ms, len(json.dumps(verdict, sort_keys=True).encode())),
        "evidence_persistence": stage(1, persistence_ms, evidence_bytes),
        "total": stage(1, (time.perf_counter_ns() - total_start) / 1_000_000, evidence_bytes),
    }
    envelope = {
        "schema": TELEMETRY_SCHEMA,
        "trace_id": run_identity["execution_id"],
        "run_identity": run_identity,
        "step_id": "control_execution",
        "control_id": control_id,
        "started_at": started_at,
        "finished_at": finished_at,
        "duration_ms": stages["total"]["duration_ms"],
        "stages": stages,
        "input_digest": run_identity["source_sha256"],
        "result_digest": digest(result),
        "derived_status_ref": "independent_control_judge",
        "verdict": verdict.get("status", "BLOCKED"),
    }
    return {"control_id": control_id, "result": result, "verdict": verdict,
            TELEMETRY_SCHEMA: envelope}


def make_run_identity(*, control_id: str, repository: str, pr: str, head_sha: str,
                      run_id: str, run_attempt: str, source_path: Path, source_sha256: str) -> dict:
    return {
        "run_kind": "PASE_CONTROL",
        "suite_id": "PASE_F04_F06_CONTROL_RUNNER",
        "repository": repository,
        "pr": str(pr),
        "git_head_sha": head_sha,
        "github_run_id": str(run_id),
        "github_run_attempt": str(run_attempt),
        "train_run_id": str(run_id),
        "execution_id": f"PASE-CONTROL-PR{pr}-R{run_id}-A{run_attempt}-{control_id}",
        "migration_version": NOT_APPLICABLE,
        "source_blob": source_path.as_posix(),
        "source_sha256": source_sha256,
        "control_id": control_id,
    }


def _subprocess(argv: list[str]) -> dict:
    proc = subprocess.run(argv, cwd=ROOT, text=True, capture_output=True, check=False)
    return {"returncode": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}


def run_f04(*, base_sha: str, head_sha: str, repository: str, pr: str,
            run_id: str, run_attempt: str) -> dict:
    source = ROOT / "sandbox/lf_contract_gate_test/pase_scenario_qualification/run_f04_terminal_scenario_profiles_v1.py"
    identity = make_run_identity(control_id="F04_SCENARIO_PROFILES", repository=repository, pr=pr,
                                 head_sha=head_sha, run_id=run_id, run_attempt=run_attempt,
                                 source_path=source.relative_to(ROOT), source_sha256=sha256_file(source))
    output_dir = ".f04-q99-scenario-results"
    result = run_control(
        control_id="F04_SCENARIO_PROFILES", run_identity=identity,
        execute=lambda: _subprocess([sys.executable, str(source), "--base-sha", base_sha,
                                     "--head-sha", head_sha, "--output-dir", output_dir]),
        judge=lambda value: {"status": "PASS" if value["returncode"] == 0 and
                             "PASS_F04_TERMINAL_SCENARIO_PROFILES=" in value["stdout"] else "BLOCKED",
                             "producer_returncode": value["returncode"],
                             "producer_marker_seen": "PASS_F04_TERMINAL_SCENARIO_PROFILES=" in value["stdout"]},
    )
    return result


def run_f06(*, exact_main_sha: str, repository: str, pr: str, head_sha: str,
            run_id: str, run_attempt: str) -> dict:
    inventory = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"
    source = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/test_pase_control_binding_inventory_v1.py"
    inventory_doc = json.loads(inventory.read_text(encoding="utf-8"))
    observed_main = inventory_doc.get("observed_git_main_sha")
    identity = make_run_identity(control_id="F06_CONTROL_BINDING_INVENTORY", repository=repository, pr=pr,
                                 head_sha=head_sha, run_id=run_id, run_attempt=run_attempt,
                                 source_path=inventory.relative_to(ROOT), source_sha256=sha256_file(inventory))
    static_result = _subprocess([sys.executable, str(source)])
    return run_control(
        control_id="F06_CONTROL_BINDING_INVENTORY", run_identity=identity,
        execute=lambda: {"static_validation": static_result, "observed_main_sha": observed_main,
                         "exact_main_sha": exact_main_sha, "inventory_sha256": sha256_file(inventory)},
        judge=lambda value: {"status": "BLOCKED" if value["observed_main_sha"] != exact_main_sha else
                             ("PASS" if value["static_validation"]["returncode"] == 0 else "FAIL"),
                             "reason": "BLOCK_STALE_CURRENTNESS" if value["observed_main_sha"] != exact_main_sha else
                             "STATIC_VALIDATION_FAILED" if value["static_validation"]["returncode"] else "CURRENT"},
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("control", choices=("f04", "f06"))
    parser.add_argument("--base-sha", default="")
    parser.add_argument("--main-sha", default="")
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--pr", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    args = parser.parse_args()
    if args.control == "f04":
        if not args.base_sha:
            parser.error("f04 requires --base-sha")
        report = run_f04(base_sha=args.base_sha, head_sha=args.head_sha, repository=args.repository,
                         pr=args.pr, run_id=args.run_id, run_attempt=args.run_attempt)
    else:
        if not args.main_sha:
            parser.error("f06 requires --main-sha")
        report = run_f06(exact_main_sha=args.main_sha, repository=args.repository, pr=args.pr,
                         head_sha=args.head_sha, run_id=args.run_id, run_attempt=args.run_attempt)
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0 if report["verdict"]["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
