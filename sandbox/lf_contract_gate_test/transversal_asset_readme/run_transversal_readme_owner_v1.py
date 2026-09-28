#!/usr/bin/env python3
"""Owner-local execution surface for TRANSVERSAL_README.

Applicability and inventory acquisition are owned upstream. This runner only
executes the canonical README contract tests and validator over a supplied
read-only inventory snapshot.
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
CONTRACT = HERE / "transversal_readme_owner_runner_v1.json"
SELF_TEST = HERE / "test_validate_active_shared_readmes_v1.py"
VALIDATOR = HERE / "validate_active_shared_readmes_v1.py"


def command_specs(inventory_json: Path, repo_root: Path, require_codes: list[str]) -> list[list[str]]:
    validator = [
        sys.executable,
        str(VALIDATOR.relative_to(ROOT)),
        "--inventory-json",
        str(inventory_json),
        "--repo-root",
        str(repo_root),
    ]
    for code in require_codes:
        validator.extend(["--require-code", code])
    return [
        [sys.executable, str(SELF_TEST.relative_to(ROOT))],
        validator,
    ]


def self_test() -> dict[str, Any]:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    dummy_inventory = Path("/tmp/lf_transversal_readme_inventory.json")
    specs = command_specs(dummy_inventory, Path("."), ["PRE_EKB_GATE"])
    flattened = "\n".join(" ".join(spec) for spec in specs).lower()

    assert contract["durable_name"] == "TRANSVERSAL_README_OWNER_RUNNER_V1"
    assert contract["owner"] == "TRANSVERSAL_README"
    assert contract["input_contract"]["must_not_decide_run_skip"] is True
    assert contract["input_contract"]["must_not_query_database"] is True
    assert contract["owned_execution"]["validator"].endswith("validate_active_shared_readmes_v1.py")
    assert contract["handoff"] == "PASE_ORCHESTRATOR_BIND_TRANSVERSAL_README"
    assert contract["merge_authorized"] is False
    assert contract["deployment_authorized"] is False
    assert contract["production_authorized"] is False
    assert SELF_TEST.is_file()
    assert VALIDATOR.is_file()

    required_tokens = (
        "test_validate_active_shared_readmes_v1.py",
        "validate_active_shared_readmes_v1.py",
        "--inventory-json",
        "--repo-root",
        "--require-code pre_ekb_gate",
    )
    for token in required_tokens:
        assert token in flattened, token

    forbidden = (
        "psql",
        "pgpassword",
        "supabase",
        "validate-lf-packs.yml",
        "gate_check_observability",
        "profile_runtime_v3",
        "lf-contract-check",
        "deploy",
        "production",
    )
    for token in forbidden:
        assert token not in flattened, token

    return {
        "schema_version": "lf-transversal-readme-owner-runner-selftest/v1",
        "status": "PASS",
        "owner": "TRANSVERSAL_README",
        "commands": len(specs),
    }


def run(inventory_json: Path, repo_root: Path, require_codes: list[str]) -> dict[str, Any]:
    if not inventory_json.is_file():
        raise SystemExit(f"BLOCK_TRANSVERSAL_README_INVENTORY_MISSING:{inventory_json}")
    for spec in command_specs(inventory_json, repo_root, require_codes):
        completed = subprocess.run(spec, cwd=ROOT, check=False)
        if completed.returncode != 0:
            raise SystemExit(f"BLOCK_TRANSVERSAL_README_OWNER_CHECK:rc={completed.returncode}")
    return {
        "schema_version": "lf-transversal-readme-owner-runner/v1",
        "owner": "TRANSVERSAL_README",
        "status": "PASS",
        "inventory_json": str(inventory_json),
        "required_codes": require_codes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--inventory-json", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--require-code", action="append", default=[])
    args = parser.parse_args()

    if args.self_test:
        payload = self_test()
        print("TRANSVERSAL_README_OWNER_RUNNER_V1=PASS 16/16")
        print(json.dumps(payload, sort_keys=True))
        return 0
    if args.inventory_json is None:
        raise SystemExit("BLOCK_TRANSVERSAL_README_OWNER_INVENTORY_REQUIRED")
    if args.list:
        print(json.dumps({"owner": "TRANSVERSAL_README", "commands": command_specs(args.inventory_json, args.repo_root, args.require_code)}, sort_keys=True))
        return 0

    payload = run(args.inventory_json, args.repo_root, args.require_code)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
