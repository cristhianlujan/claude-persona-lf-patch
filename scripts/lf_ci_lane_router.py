#!/usr/bin/env python3
"""Fail-closed path router for expensive/specialized LF CI lanes.

It decides applicability only. It never converts a failing applicable gate into PASS.
Unknown paths remain in DEEP_SHARED, while migration parity is required only when the
change intersects migration-owned source/validator surfaces.
"""
from __future__ import annotations

import argparse
import json
from pathlib import PurePosixPath
from typing import Iterable

GENERAL_MIGRATION_VALIDATORS = {
    "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
}
INPUT_GOVERNANCE_VALIDATORS = {
    "sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py",
}
CI_ROUTER_SURFACES = {
    ".github/workflows/lf-contract-check.yml",
    "scripts/lf_ci_lane_router.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py",
    ".github/workflows/s28-ci-lane-router-canary.yml",
}
S30_POLICY_PREFIX = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/"

INPUT_GOVERNANCE_MIGRATION_TOKENS = (
    "input_governance_",
    "programacion_input_governance_",
    "retire_b2b_auth005_legacy_totp_screen",
)


def _norm(path: str) -> str:
    value = str(PurePosixPath(path.strip()))
    if value in {".", ""} or value.startswith("../") or value.startswith("/"):
        raise ValueError(f"INVALID_CHANGED_PATH:{path}")
    return value


def classify(paths: Iterable[str]) -> dict:
    changed = sorted({_norm(p) for p in paths if p and p.strip()})
    if not changed:
        return {
            "status": "BLOCKED",
            "blocking_code": "BLOCK_CI_LANE_ROUTER_EMPTY_CHANGESET",
            "changed": [],
        }

    migration_files = [p for p in changed if p.startswith("supabase/migrations/") and p.endswith(".sql")]
    general_migration = bool(migration_files or GENERAL_MIGRATION_VALIDATORS.intersection(changed))
    input_governance = bool(INPUT_GOVERNANCE_VALIDATORS.intersection(changed)) or any(
        any(token in PurePosixPath(p).name for token in INPUT_GOVERNANCE_MIGRATION_TOKENS)
        for p in migration_files
    )
    s30_policy = any(p.startswith(S30_POLICY_PREFIX) for p in changed)
    ci_router = bool(CI_ROUTER_SURFACES.intersection(changed))

    known = set(migration_files) | GENERAL_MIGRATION_VALIDATORS.intersection(changed) | INPUT_GOVERNANCE_VALIDATORS.intersection(changed) | CI_ROUTER_SURFACES.intersection(changed)
    known.update(p for p in changed if p.startswith(S30_POLICY_PREFIX))
    unknown = [p for p in changed if p not in known]

    return {
        "status": "ROUTED",
        "changed": changed,
        "lanes": {
            "MIGRATION_PARITY": general_migration,
            "INPUT_GOVERNANCE_MIGRATION_PARITY": input_governance,
            "S30_POLICY": s30_policy,
            "CI_ROUTER_SELF_TEST": ci_router,
            "DEEP_SHARED": bool(unknown),
        },
        "unknown_paths": unknown,
        "rules": {
            "migration_parity_not_applicable_is_not_pass": True,
            "applicable_gate_failure_remains_blocking": True,
            "unknown_paths_do_not_silently_skip_shared_deep": True,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = classify(args.paths)
    print(json.dumps(result, sort_keys=True) if args.json else result)
    raise SystemExit(0 if result.get("status") == "ROUTED" else 2)


if __name__ == "__main__":
    main()
