#!/usr/bin/env python3
"""Independent source-level semantic judge for FULL_REGRESSION P1-P8.

F04 judges source semantics only. It deliberately does not assert physical
carrier cutover/activation, which belongs to the governed activation phase.
"""
from __future__ import annotations

import ast
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PLAN = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
EMITTER = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py"
IMPACT_REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
TRANSVERSAL_INDEX = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/README.md"
SUPER_ADMIN = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/lf_governance_super_admin/lf_governance_super_admin_contract_v1.json"
IMPLEMENTATION = HERE / "full_regression_v1.py"
ASSET_README = HERE / "README.md"


def check(point: str, expectation: str, evidence: list[str], ok: bool, gap: str = "") -> dict:
    return {
        "point": point,
        "expectation": expectation,
        "evidence": evidence,
        "semantic_verdict": "PASS" if ok else "FAIL",
        "gap": "" if ok else gap,
    }


def declares_full_regression_asset(path: Path) -> bool:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        if not isinstance(value, ast.Constant) or value.value != "FULL_REGRESSION":
            continue
        if any(isinstance(target, ast.Name) and target.id == "ASSET_CODE" for target in targets):
            return True
    return False


def main() -> int:
    required_files = [PLAN, EMITTER, IMPACT_REGISTRY, TRANSVERSAL_INDEX, SUPER_ADMIN, IMPLEMENTATION, ASSET_README]
    missing = [str(path.relative_to(ROOT)) for path in required_files if not path.is_file()]
    if missing:
        print(json.dumps({"schema_version": "lf-full-regression-semantic-judge/v2", "verdict": "FAIL", "missing": missing}, sort_keys=True))
        return 2

    plan = PLAN.read_text(encoding="utf-8")
    emitter = EMITTER.read_text(encoding="utf-8")
    impl = IMPLEMENTATION.read_text(encoding="utf-8")
    readme = ASSET_README.read_text(encoding="utf-8")
    index = TRANSVERSAL_INDEX.read_text(encoding="utf-8")
    impact = json.loads(IMPACT_REGISTRY.read_text(encoding="utf-8"))
    super_admin = json.loads(SUPER_ADMIN.read_text(encoding="utf-8"))

    executable_identities = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.py")
        if declares_full_regression_asset(path)
    )

    points = [
        check(
            "P1",
            "FULL_REGRESSION consumes upstream applicability and cannot decide it locally.",
            ["applicability_authority", "local_applicability_decisions=0", "PLAN.validate_plan_contract"],
            '"applicability_authority": "CHANGESET_GOVERNANCE_LF_V1+LF_CI_EXECUTION_PLAN_V2"' in plan
            and '"local_applicability_decisions": 0' in plan
            and "PLAN.validate_plan_contract(plan)" in impl,
            "local applicability authority remains or consumer validation is missing",
        ),
        check(
            "P2",
            "FULL_REGRESSION never expands to run-everything.",
            ["run_everything=False", "no full-list expansion", "planned/executed equality"],
            '"run_everything": False' in plan
            and "required.update(full_regression_controls)" not in plan
            and "actual != planned_controls" in impl
            and "sorted(executed) != required" in impl,
            "run-everything expansion or loose execution remains",
        ),
        check(
            "P3",
            "Carrier partition is supplied by the governed plan and duplicate execution is blocked.",
            ["FAIL_CI_PLAN_DUPLICATE_CONTROL_CARRIER", "duplicate carrier receipt", "duplicate control execution"],
            "FAIL_CI_PLAN_DUPLICATE_CONTROL_CARRIER" in plan
            and "BLOCK_FULL_REGRESSION_DUPLICATE_CARRIER_RECEIPT" in impl
            and "BLOCK_FULL_REGRESSION_DUPLICATE_CONTROL_EXECUTION" in impl,
            "carrier/control duplication is not fail-closed",
        ),
        check(
            "P4",
            "Retired controls cannot be planned or executed.",
            ["retired control guards in plan and consumer"],
            "FAIL_CI_RETIRED_CONTROL_IN_REQUIRED_SET" in plan
            and "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_PLANNED" in impl
            and "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_EXECUTED" in impl,
            "retired control guard incomplete",
        ),
        check(
            "P5",
            "Legacy full_regression_controls is compatibility-only and has zero applicability authority.",
            ["HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY", "no legacy expansion", "emitter has no full-list logic"],
            "HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY" in plan
            and "required.update(full_regression_controls)" not in plan
            and "full_regression_controls" not in emitter,
            "legacy full list still influences applicability",
        ),
        check(
            "P6",
            "Missing, invalid, unresolved or incompatible evidence fails closed.",
            ["FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED", "FAIL_CI_PLAN_SHA256", "receipt/source guards"],
            "FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED" in plan
            and "FAIL_CI_PLAN_SHA256" in plan
            and "BLOCK_FULL_REGRESSION_PLAN_INVALID" in impl
            and "BLOCK_FULL_REGRESSION_RECEIPT_SHA" in impl,
            "fail-closed evidence boundary incomplete",
        ),
        check(
            "P7",
            "No applicable controls means NOT_APPLICABLE and zero execution.",
            ["applicability_decision", "NOT_APPLICABLE consumer branch"],
            '"NOT_APPLICABLE" if not required_sorted else "APPLY"' in plan
            and '_base_output(plan, "NOT_APPLICABLE")' in impl
            and '"executed_controls": []' in impl,
            "zero-control semantics are not explicit",
        ),
        check(
            "P8",
            "One FULL_REGRESSION implementation; no second router/registry/carrier is introduced by this lot.",
            ["single ASSET_CODE declaration", "existing impact registry reused", "transversal locator"],
            executable_identities == ["sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py"]
            and impact.get("schema_version") == "lf-ci-control-impact-registry/v2"
            and index.count("`FULL_REGRESSION` — `TRANSVERSAL_FULL_REGRESSION`") == 1,
            f"parallel identity/path detected: {executable_identities}",
        ),
    ]

    extra = {
        "super_admin_preserved": (
            '"governance_admin"' in plan
            and "load_super_admin_identity" in plan
            and super_admin.get("invariants", {}).get("super_admin_is_not_carrier") is True
        ),
        "activation_not_claimed": "no cutover, runtime activation or production activation is authorized here" in readme.lower(),
        "carrier_cutover_not_smuggled": "physical carrier cutover/remap belongs to its governed activation phase" in readme,
        "canonical_identity": 'CANONICAL_NAME = "TRANSVERSAL_FULL_REGRESSION"' in impl,
    }

    verdict = "PASS" if all(row["semantic_verdict"] == "PASS" for row in points) and all(extra.values()) else "FAIL"
    result = {
        "schema_version": "lf-full-regression-semantic-judge/v2",
        "asset_code": "FULL_REGRESSION",
        "verdict": verdict,
        "points": points,
        "additional_checks": extra,
        "executable_identities": executable_identities,
        "activation_scope": "SOURCE_QUALIFICATION_ONLY",
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    if verdict == "PASS":
        print("FULL_REGRESSION_SEMANTIC_JUDGE_PASS P1-P8=8/8")
        return 0
    print("FULL_REGRESSION_SEMANTIC_JUDGE_FAIL")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
