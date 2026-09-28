#!/usr/bin/env python3
"""Owner-local deterministic execution surface for GATE_CHECK_OBSERVABILITY.

Applicability is owned upstream. This runner executes only the canonical package
self-tests through run_gate_checks_v1.py and emits bounded diagnostics.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "gate_check_observability_owner_runner_v1.json"
ENGINE = HERE / "run_gate_checks_v1.py"
DEFAULT_ARTIFACT_DIR = ROOT / ".lf_gate_diagnostics/gate_check_observability/control"
TEST_GLOB = "sandbox/lf_contract_gate_test/gate_check_observability/test_*.py"


def command_spec(artifact_dir: Path = DEFAULT_ARTIFACT_DIR) -> list[str]:
    artifact_arg = (
        artifact_dir.relative_to(ROOT).as_posix()
        if artifact_dir.is_relative_to(ROOT)
        else str(artifact_dir)
    )
    return [
        sys.executable,
        str(ENGINE.relative_to(ROOT)),
        "--gate-id",
        "GATE_CHECK_OBSERVABILITY_OWNER_V1",
        "--step-id",
        "owner_self_validation",
        "--mode",
        "COLLECT_ALL",
        "--glob",
        TEST_GLOB,
        "--artifact-dir",
        artifact_arg,
        "--artifact-name",
        "lf_gate_error_v1.json",
        "--check-prefix",
        "GCO",
        "--owner",
        "GATE_CHECK_OBSERVABILITY",
        "--next-action",
        "FIX_GATE_CHECK_OBSERVABILITY_AND_RERUN",
        "--downstream-impact",
        "OBSERVABILITY",
        "--downstream-impact",
        "ASSURANCE",
    ]


def self_test() -> dict[str, Any]:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    argv = command_spec()
    joined = " ".join(argv).lower()

    assert contract["durable_name"] == "GATE_CHECK_OBSERVABILITY_OWNER_RUNNER_V1"
    assert contract["owner"] == "GATE_CHECK_OBSERVABILITY"
    assert contract["input_contract"]["must_not_decide_run_skip"] is True
    assert contract["owned_execution"]["runner"].endswith("run_gate_checks_v1.py")
    assert contract["owned_execution"]["test_glob"] == TEST_GLOB
    assert contract["qualification_boundary"]["consumer_specific_claim_or_excel_qualification"] == "NOT_MOVED_BY_THIS_PR"
    assert contract["handoff"] == "PASE_ORCHESTRATOR_BIND_GATE_CHECK_OBSERVABILITY"
    assert contract["merge_authorized"] is False
    assert contract["deployment_authorized"] is False
    assert contract["production_authorized"] is False
    assert ENGINE.is_file()

    required_tokens = (
        "run_gate_checks_v1.py",
        "gate_check_observability/test_*.py",
        "--owner gate_check_observability",
        "--mode collect_all",
    )
    for token in required_tokens:
        assert token in joined, token

    forbidden = (
        "validate-lf-packs.yml",
        "profile_runtime_v3",
        "run_profile_runtime",
        "qualify_wf_diagnostic_claim_v1.py",
        "qualify_deep_excel_matrix_v1.py",
        "transversal_asset_readme",
        "lf-db-regression",
        "psql",
        "supabase",
        "deploy",
        "production",
    )
    for token in forbidden:
        assert token not in joined, token

    return {
        "schema_version": "lf-gate-check-observability-owner-runner-selftest/v1",
        "status": "PASS",
        "owner": "GATE_CHECK_OBSERVABILITY",
        "engine": str(ENGINE.relative_to(ROOT)),
        "test_glob": TEST_GLOB,
    }


def run(artifact_dir: Path) -> dict[str, Any]:
    if not ENGINE.is_file():
        raise SystemExit("BLOCK_GCO_OWNER_ENGINE_MISSING")
    completed = subprocess.run(command_spec(artifact_dir), cwd=ROOT, check=False)
    if completed.returncode != 0:
        raise SystemExit(f"BLOCK_GCO_OWNER_SELF_VALIDATION:rc={completed.returncode}")
    return {
        "schema_version": "lf-gate-check-observability-owner-runner/v1",
        "owner": "GATE_CHECK_OBSERVABILITY",
        "status": "PASS",
        "artifact_dir": str(artifact_dir),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--artifact-dir", type=Path, default=DEFAULT_ARTIFACT_DIR)
    args = parser.parse_args()

    if args.self_test:
        payload = self_test()
        print("GATE_CHECK_OBSERVABILITY_OWNER_RUNNER_V1=PASS 15/15")
        print(json.dumps(payload, sort_keys=True))
        return 0
    if args.list:
        print(json.dumps({"owner": "GATE_CHECK_OBSERVABILITY", "argv": command_spec(args.artifact_dir)}, sort_keys=True))
        return 0

    payload = run(args.artifact_dir)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
