#!/usr/bin/env python3
"""Temporary compatibility bridge from the historical Contract Check path.

This file intentionally preserves only the *path identity*
``scripts/lf_contract_check.py`` while Contract Check callers are migrated.
It is NOT the Contract Check implementation and MUST be removed after cutover.

Canonical execution is delegated to the new Final Thin Carrier:

    scripts/lf_contract_check.py (temporary bridge)
      -> contract_check_carrier_v1.py
      -> contract_check_semantic_integration_v1.py
      -> predicate semantics / Contract Check Core

No LF Contract Check v0.21 functional logic is retained here. Historical APIs
that represented responsibilities outside the new Contract Check boundary fail
closed instead of silently executing the retired implementation.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from typing import Any

BRIDGE_STATUS = "TEMPORARY_COMPATIBILITY_BRIDGE"
CLEANUP_REQUIRED = True
NEW_CONSUMERS_ALLOWED = False
RETIRED_IMPLEMENTATION = "LF_CONTRACT_CHECK_V0_21"

ROOT = Path(__file__).resolve().parents[1]
CARRIER_PATH = (
    ROOT
    / "sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py"
)


class LegacyContractCheckApiRetired(RuntimeError):
    """Raised when a caller still depends on a retired v0.21-only API."""


def _load_carrier():
    spec = importlib.util.spec_from_file_location(
        "contract_check_final_thin_carrier_v1", CARRIER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"contract_check_carrier_unloadable:{CARRIER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CARRIER = _load_carrier()


def fail(code: str, message: str) -> None:
    """Compatibility failure primitive used by historical importers.

    Kept only so stale adapters fail deterministically rather than crashing on
    import. It does not reproduce any v0.21 Contract Check behavior.
    """
    print(f"{code}: {message}")
    raise SystemExit(1)


def run_git(args: list[str]) -> str:
    """Compatibility utility for stale adapters; not Contract Check semantics."""
    result = subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def _retired_api(name: str) -> None:
    raise LegacyContractCheckApiRetired(
        f"LEGACY_CONTRACT_CHECK_API_RETIRED:{name};"
        "migrate caller to its canonical capability or the new Contract Check carrier"
    )


def validate_changed_files(changed_files: list[str]) -> list[str]:
    """Retired repository/scope API retained as a fail-closed compatibility stub."""
    _ = changed_files
    _retired_api("validate_changed_files")
    return []


def get_changed_files() -> list[str]:
    """Retired event/path-discovery API retained as a fail-closed stub."""
    _retired_api("get_changed_files")
    return []


def validate_candidate_receipt_shape(
    path: str, receipt: dict[str, Any], governed_files: list[str]
) -> None:
    """Retired receipt API retained only to expose the migration boundary."""
    _ = (path, receipt, governed_files)
    _retired_api("validate_candidate_receipt_shape")


def run(packet: Any) -> dict[str, Any]:
    """Canonical bridge API: delegate one packet to the Final Thin Carrier."""
    return CARRIER.run(packet)


def main(argv: list[str] | None = None) -> None:
    """Delegate CLI execution to the Final Thin Carrier and preserve exit code."""
    rc = int(CARRIER.main(argv))
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
