#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "pase_orchestrator_v1.py"


def load_target():
    spec = importlib.util.spec_from_file_location("pase_orchestrator_v1_test_target", TARGET)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_PASE_ORCHESTRATOR_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def plan(required, carrier_controls, *, coverage=True):
    return {
        "schema_version": "lf-ci-execution-plan/v2",
        "coverage_complete": coverage,
        "required_controls": sorted(required),
        "carrier_controls": carrier_controls,
        "plan_sha256": "plan-sha",
        "applicability_sha256": "app-sha",
        "evidence_sha256": "evidence-sha",
    }


def expect_error(module, payload, code, registry_path=None):
    try:
        kwargs = {"registry_path": registry_path} if registry_path is not None else {}
        module.build_dispatch_plan(payload, **kwargs)
    except module.PaseOrchestratorError as exc:
        assert str(exc).startswith(code), (code, str(exc))
        return
    raise AssertionError(f"expected {code}")


def main() -> int:
    module = load_target()
    checks = 0

    payload = plan(
        ["DB_CANDIDATE_APPLY_ROLLBACK", "MIGRATION_SOURCE_PARITY"],
        {
            "LF_CONTRACT_CHECK": ["MIGRATION_SOURCE_PARITY"],
            "LF_DB_REGRESSION": ["DB_CANDIDATE_APPLY_ROLLBACK"],
        },
    )
    got = module.build_dispatch_plan(payload)
    assert [row["carrier"] for row in got["dispatches"]] == [
        "LF_CONTRACT_CHECK",
        "LF_DB_REGRESSION",
    ], got
    assert got["applicability_authority"] == "UPSTREAM_PLAN_ONLY"
    assert got["execution_semantics"] == "SEQUENTIAL_DELEGATION_ONLY"
    checks += 1

    got = module.build_dispatch_plan(plan([], {}))
    assert got["dispatches"] == []
    assert got["dispatch_count"] == 0
    assert got["control_count"] == 0
    checks += 1

    expect_error(
        module,
        plan(
            ["MIGRATION_SOURCE_PARITY", "PROFILE_PACK"],
            {"LF_CONTRACT_CHECK": ["MIGRATION_SOURCE_PARITY"]},
        ),
        "FAIL_PASE_CARRIER_COVERAGE",
    )
    checks += 1

    expect_error(
        module,
        plan(
            ["MIGRATION_SOURCE_PARITY"],
            {
                "LF_CONTRACT_CHECK": ["MIGRATION_SOURCE_PARITY"],
                "VALIDATE_LF_PACKS": ["MIGRATION_SOURCE_PARITY"],
            },
        ),
        "FAIL_PASE_CONTROL_MULTI_CARRIER",
    )
    checks += 1

    expect_error(
        module,
        plan(
            ["MIGRATION_SOURCE_PARITY"],
            {"VALIDATE_LF_PACKS": ["MIGRATION_SOURCE_PARITY"]},
        ),
        "FAIL_PASE_CARRIER_DRIFT",
    )
    checks += 1

    expect_error(
        module,
        plan(["MIGRATION_SOURCE_PARITY"], {"LF_CONTRACT_CHECK": ["MIGRATION_SOURCE_PARITY"]}, coverage=False),
        "FAIL_PASE_PLAN_COVERAGE_INCOMPLETE",
    )
    checks += 1

    with tempfile.TemporaryDirectory() as tmp:
        registry = Path(tmp) / "registry.json"
        registry.write_text(
            json.dumps(
                {
                    "schema_version": "lf-ci-control-impact-registry/v2",
                    "controls": [
                        {"control_id": "A", "carrier": "CARRIER_A", "dependencies": ["B"]},
                        {"control_id": "B", "carrier": "CARRIER_B", "dependencies": ["A"]},
                    ],
                }
            ),
            encoding="utf-8",
        )
        expect_error(
            module,
            plan(["A", "B"], {"CARRIER_A": ["A"], "CARRIER_B": ["B"]}),
            "FAIL_PASE_CARRIER_DEPENDENCY_CYCLE",
            registry,
        )
    checks += 1

    source = TARGET.read_text(encoding="utf-8")
    for forbidden in (
        "import subprocess",
        "import urllib",
        "import requests",
        "execute_sql",
        "apply_migration",
        "changed_paths",
        ".classify(",
        "validate_contract(",
    ):
        assert forbidden not in source, forbidden
    checks += 1

    print(f"PASS_PASE_ORCHESTRATOR_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
