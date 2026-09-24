#!/usr/bin/env python3
"""Independent semantic judge for FULL_REGRESSION P1-P8."""
from __future__ import annotations

import ast
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PLAN = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
EMITTER = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py"
SHARED_REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json"
IMPACT_REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
ROUTER_README = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md"
ASSET_README = HERE / "README.md"
IMPLEMENTATION = HERE / "full_regression_v1.py"
WORKFLOWS = [
    ROOT / ".github/workflows/lf-contract-check.yml",
    ROOT / ".github/workflows/validate-lf-packs.yml",
    ROOT / ".github/workflows/lf-db-regression.yml",
]


def check(point: str, expectation: str, evidence: list[str], ok: bool, gap: str = "") -> dict:
    return {
        "point": point,
        "expectation": expectation,
        "evidence": evidence,
        "semantic_verdict": "PASS" if ok else "FAIL",
        "gap": "" if ok else gap,
    }


def _declares_full_regression_asset(path: Path) -> bool:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (UnicodeDecodeError, SyntaxError):
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
    plan = PLAN.read_text(encoding="utf-8")
    emitter = EMITTER.read_text(encoding="utf-8")
    impl = IMPLEMENTATION.read_text(encoding="utf-8")
    asset_readme = ASSET_README.read_text(encoding="utf-8")
    router_readme = ROUTER_README.read_text(encoding="utf-8")
    shared = json.loads(SHARED_REGISTRY.read_text(encoding="utf-8"))
    impact = json.loads(IMPACT_REGISTRY.read_text(encoding="utf-8"))

    executable_identities = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.py")
        if _declares_full_regression_asset(path)
    )

    registered_paths = {row["path"] for row in shared.get("controls", [])}
    required_asset_paths = {
        "sandbox/lf_contract_gate_test/transversal_assets/full_regression/README.md",
        "sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py",
        "sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py",
    }

    points = [
        check(
            "P1",
            "FULL_REGRESSION consumes applicability; it does not decide it.",
            ["plan.applicability_authority", "plan.local_applicability_decisions=0", "consumer validates canonical plan"],
            '"local_applicability_decisions": 0' in plan
            and "PLAN.validate_plan_contract(plan)" in impl
            and "CHANGESET_GOVERNANCE_LF_V1+LF_CI_EXECUTION_PLAN_V2" in plan,
            "local applicability ownership remains",
        ),
        check(
            "P2",
            "No run-everything expansion; planned controls are the only executable controls.",
            ["plan.run_everything=False", "consumer exact planned/executed equality"],
            '"run_everything": False' in plan
            and "actual != planned_controls" in impl
            and "sorted(executed) != required" in impl,
            "run-everything or loose execution remains",
        ),
        check(
            "P3",
            "One canonical carrier per control and receipt consumption without re-execution.",
            ["carrier partition validation", "duplicate carrier receipt block", "duplicate control block"],
            "FAIL_CI_PLAN_DUPLICATE_CONTROL_CARRIER" in plan
            and "BLOCK_FULL_REGRESSION_DUPLICATE_CARRIER_RECEIPT" in impl
            and "BLOCK_FULL_REGRESSION_DUPLICATE_CONTROL_EXECUTION" in impl,
            "duplicate carrier/control execution not blocked",
        ),
        check(
            "P4",
            "Retired controls cannot be planned or executed by FULL_REGRESSION.",
            ["retired_controls input", "planned and executed retirement blocks"],
            "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_PLANNED" in impl
            and "BLOCK_FULL_REGRESSION_RETIRED_CONTROL_EXECUTED" in impl,
            "retired control execution remains possible",
        ),
        check(
            "P5",
            "No parallel applicability engine; legacy full_regression_controls is non-authoritative.",
            ["legacy registry semantics explicitly ignored", "no required.update(full_regression_controls)"],
            "HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY" in plan
            and "required.update(full_regression_controls)" not in plan
            and "full_regression_controls" not in emitter,
            "legacy full-regression list still expands applicability",
        ),
        check(
            "P6",
            "Missing, invalid, stale or incompatible plan/receipt fails closed.",
            ["unresolved applicability PlanError", "plan SHA validation", "receipt SHA/source/plan checks"],
            "FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED" in plan
            and "FAIL_CI_PLAN_SHA256" in plan
            and "BLOCK_FULL_REGRESSION_PLAN_STALE_OR_UNREADY" in impl
            and "BLOCK_FULL_REGRESSION_RECEIPT_SHA" in impl,
            "fail-open path remains",
        ),
        check(
            "P7",
            "No applicable controls yields NOT_APPLICABLE and zero execution.",
            ["plan applicability_decision", "consumer NOT_APPLICABLE branch"],
            '"NOT_APPLICABLE" if not required_sorted else "APPLY"' in plan
            and '_base_output(plan, "NOT_APPLICABLE")' in impl
            and '"executed_controls": []' in impl,
            "N/A still requires synthetic execution",
        ),
        check(
            "P8",
            "No second FULL_REGRESSION/router/registry/carrier path.",
            ["single AST-declared FULL_REGRESSION asset identity", "existing shared/impact registries reused", "same three canonical workflows"],
            len(executable_identities) == 1
            and executable_identities[0].endswith("transversal_assets/full_regression/full_regression_v1.py")
            and required_asset_paths.issubset(registered_paths)
            and impact.get("schema_version") == "lf-ci-control-impact-registry/v2"
            and all(path.is_file() for path in WORKFLOWS),
            f"parallel identity/path detected: {executable_identities}",
        ),
    ]

    readme_tokens = [
        "FULL_REGRESSION",
        "TRANSVERSAL_FULL_REGRESSION",
        "Owner",
        "Authority",
        "Inputs",
        "Outputs",
        "Consumers",
        "Dependencies",
        "Applicability",
        "Canonical carriers",
        "Receipts",
        "NOT_APPLICABLE",
        "Fail-closed",
        "Lifecycle",
        "Observability",
        "Registries",
        "Código físico",
        "Tests",
        "Deterministic",
        "Semantic",
        "COMPROBADO",
        "CHANGESET_GOVERNANCE_LF_V1",
    ]
    readme_ok = all(token in asset_readme for token in readme_tokens)
    router_ok = "FULL_REGRESSION consumes the governed plan" in router_readme
    identity_ok = 'CANONICAL_NAME = "TRANSVERSAL_FULL_REGRESSION"' in impl
    owner_ok = "LF_GOVERNANCE" in asset_readme
    extra = {
        "identity_coherent": identity_ok,
        "owner_coherent": owner_ok,
        "no_duplicate_execution": points[2]["semantic_verdict"] == "PASS",
        "no_orphan_responsibility": points[3]["semantic_verdict"] == "PASS",
        "no_parallel_paths": points[7]["semantic_verdict"] == "PASS",
        "readme_faithful": readme_ok and router_ok,
        "asset_metadata_contract_faithful": "public.lf_activos" in asset_readme,
        "registry_faithful": required_asset_paths.issubset(registered_paths),
        "implementation_faithful": all(p["semantic_verdict"] == "PASS" for p in points),
        "execution_faithful": "CANONICAL_CARRIERS_ONLY" in impl,
    }

    verdict = "PASS" if all(p["semantic_verdict"] == "PASS" for p in points) and all(extra.values()) else "FAIL"
    result = {
        "schema_version": "lf-full-regression-semantic-judge/v1",
        "asset_code": "FULL_REGRESSION",
        "verdict": verdict,
        "points": points,
        "additional_checks": extra,
        "executable_identities": executable_identities,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    if verdict == "PASS":
        print("FULL_REGRESSION_SEMANTIC_JUDGE_PASS P1-P8=8/8")
        return 0
    print("FULL_REGRESSION_SEMANTIC_JUDGE_FAIL")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
