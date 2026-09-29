#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLAN_PATH = HERE / "lf_ci_execution_plan_v2.py"
CONTRACT_PATH = Path(__file__).resolve().parents[3] / "sandbox/lf_contract_gate_test/transversal_assets/lf_governance_super_admin/lf_governance_super_admin_contract_v1.json"


def load_plan_module():
    spec = importlib.util.spec_from_file_location("lf_ci_execution_plan_super_admin_tested", PLAN_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def temp_contract(payload: dict) -> Path:
    root = Path(tempfile.mkdtemp(prefix="lf-super-admin-plan-binding-"))
    path = root / "contract.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def temp_repo() -> Path:
    root = Path(tempfile.mkdtemp(prefix="lf-super-admin-plan-repo-"))
    path = root / "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("# evidence\n", encoding="utf-8")
    return root


def main() -> None:
    P = load_plan_module()
    checks = 0

    identity = P.load_super_admin_identity()
    assert identity["super_admin"] == "LF_GOVERNANCE"
    assert identity["schema_version"] == "lf-ci-governance-admin-identity/v1"
    assert identity["binding_materialized"] is False
    checks += 1

    raw = CONTRACT_PATH.read_bytes()
    assert identity["source_revision"] == hashlib.sha256(raw).hexdigest()
    checks += 1

    plan = P.build_plan(
        changed_paths=["docs/p0/MATRIZ_OPCIONES_OCR_CV.md"],
        lane_required_controls=(),
        lane_mode="DEEP_SHARED_KNOWN",
        repo_root=temp_repo(),
    )
    assert plan["governance_admin"] == identity
    assert "super_admin" not in plan
    assert all("super_admin" not in row for row in plan["not_applicable_controls"])
    assert all(isinstance(values, list) for values in plan["carrier_controls"].values())
    checks += 1

    missing = Path(tempfile.mkdtemp(prefix="lf-super-admin-missing-")) / "missing.json"
    try:
        P.load_super_admin_identity(missing)
    except P.PlanError as exc:
        assert "FAIL_CI_SUPER_ADMIN_CONTRACT_READ" in str(exc)
    else:
        raise AssertionError("missing super-admin contract was accepted")
    checks += 1

    base = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    bad_schema = dict(base)
    bad_schema["schema_version"] = "wrong/v1"
    try:
        P.load_super_admin_identity(temp_contract(bad_schema))
    except P.PlanError as exc:
        assert "FAIL_CI_SUPER_ADMIN_CONTRACT_SCHEMA" in str(exc)
    else:
        raise AssertionError("wrong super-admin schema was accepted")
    checks += 1

    identity_drift = json.loads(json.dumps(base))
    identity_drift["invariants"]["super_admin_equals"] = "OTHER_GOVERNANCE"
    try:
        P.load_super_admin_identity(temp_contract(identity_drift))
    except P.PlanError as exc:
        assert "FAIL_CI_SUPER_ADMIN_IDENTITY_DRIFT" in str(exc)
    else:
        raise AssertionError("super-admin identity drift was accepted")
    checks += 1

    broken_boundary = json.loads(json.dumps(base))
    broken_boundary["invariants"]["super_admin_is_not_carrier"] = False
    try:
        P.load_super_admin_identity(temp_contract(broken_boundary))
    except P.PlanError as exc:
        assert "FAIL_CI_SUPER_ADMIN_INVARIANT:super_admin_is_not_carrier" in str(exc)
    else:
        raise AssertionError("super-admin/carrier collapse was accepted")
    checks += 1

    source = PLAN_PATH.read_text(encoding="utf-8")
    assert '"LF_GOVERNANCE"' not in source
    assert "lf_ci_control_impact_registry_v2.json" in source
    assert "lf_governance_super_admin_contract_v1.json" in source
    checks += 1

    print(f"PASS_LF_CI_SUPER_ADMIN_PLAN_BINDING_V1 checks={checks}")


if __name__ == "__main__":
    main()
