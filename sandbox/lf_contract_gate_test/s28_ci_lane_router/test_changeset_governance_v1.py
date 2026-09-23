#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


CG = load("changeset_governance_test", "lf_changeset_governance.py")
ROUTER = load("lane_router_changeset_test", "lf_ci_lane_router.py")


def write_manifest(root: Path, solution_ref: str, paths: dict[str, str]) -> str:
    rel = f"changesets/{solution_ref}.json"
    target = root / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"solution_ref": solution_ref, "paths": paths}, sort_keys=True), encoding="utf-8")
    return rel


def has(result: dict, code: str) -> bool:
    return any(row.get("code") == code for row in result["findings"])


def main() -> int:
    family_checks = 0
    manifest_checks = 0
    reg = CG.load_registry()

    # 1/6: fixed MIGRATION remains authoritative and routes only its own control.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        mig = "supabase/migrations/20260923000000_example.sql"
        result = CG.evaluate(repo_root=root, changed_paths=[mig], registry=reg)
        assert result["family_by_path"][mig] == "MIGRATION"
        lane = ROUTER.classify([mig], family_by_path=result["family_by_path"], family_controls=result["family_controls"])
        assert lane.required_controls == (ROUTER.CONTROL_MIGRATION_SOURCE_PARITY,)
        family_checks += 1

    # 2/6: a non-fixed path may be declared by exactly one manifest.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        path = "sandbox/lf_contract_gate_test/example/test_case.py"
        manifest = write_manifest(root, "SOL-TEST-001", {path: "TEST"})
        result = CG.evaluate(repo_root=root, changed_paths=[path, manifest], registry=reg)
        assert result["result"] == "PASS" and result["family_by_path"][path] == "TEST"
        family_checks += 1

    # 3/6: fixed family cannot be overridden by manifest (spec negative: services -> TEST).
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        service = "services/profile_runtime_api/example.py"
        manifest = write_manifest(root, "SOL-SVC-001", {service: "TEST"})
        result = CG.evaluate(repo_root=root, changed_paths=[service, manifest], registry=reg)
        assert has(result, "FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE")
        assert result["family_by_path"][service] == "SERVICE"
        family_checks += 1

    # 4/6: when a manifest exists, every non-fixed changed path must be declared.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        declared = "docs/a.md"
        omitted = "mystery/b.txt"
        manifest = write_manifest(root, "SOL-DECL-001", {declared: "DOC"})
        result = CG.evaluate(repo_root=root, changed_paths=[declared, omitted, manifest], registry=reg)
        assert has(result, "FAIL_CHANGESET_UNDECLARED_PATH")
        family_checks += 1

    # 5/6: manifest cannot invent an undeclared family.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        path = "mystery/a.txt"
        manifest = write_manifest(root, "SOL-FAMILY-001", {path: "NOT_A_FAMILY"})
        result = CG.evaluate(repo_root=root, changed_paths=[path, manifest], registry=reg)
        assert has(result, "FAIL_CHANGESET_UNKNOWN_MANIFEST_FAMILY")
        family_checks += 1

    # 6/6: unknown without manifest is REPORT_ONLY classification, never parity fallback.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        path = "mystery/new_surface.xyz"
        result = CG.evaluate(repo_root=root, changed_paths=[path], registry=reg)
        assert result["result"] == "CLASSIFICATION_REQUIRED" and result["would_block"] is False
        lane = ROUTER.classify([path], family_by_path=result["family_by_path"], family_controls=result["family_controls"])
        assert lane.mode == "CLASSIFICATION_REQUIRED"
        assert ROUTER.CONTROL_MIGRATION_SOURCE_PARITY not in lane.required_controls
        family_checks += 1

    # 1/2 manifest integrity: one manifest binds filename + solution_ref + diff paths.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        path = "docs/one.md"
        manifest = write_manifest(root, "SOL-MANIFEST-001", {path: "DOC"})
        result = CG.evaluate(repo_root=root, changed_paths=[path, manifest], registry=reg)
        assert result["manifest_count"] == 1
        assert result["solution_ref"] == "SOL-MANIFEST-001"
        assert result["findings"] == []
        manifest_checks += 1

    # 2/2 manifest integrity: two solution manifests are mechanically detected.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        first = write_manifest(root, "SOL-A-001", {})
        second = write_manifest(root, "SOL-B-001", {})
        result = CG.evaluate(repo_root=root, changed_paths=[first, second], registry=reg)
        assert result["manifest_count"] == 2
        assert has(result, "FAIL_CHANGESET_MULTIPLE_SOLUTIONS")
        manifest_checks += 1

    assert family_checks == 6
    assert manifest_checks == 2
    print("PASS_CHANGESET_FAMILY_POLICY=6/6")
    print("PASS_CHANGESET_MANIFEST_POLICY=2/2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
