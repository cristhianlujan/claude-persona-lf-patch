#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLAN_PATH = HERE / "lf_ci_execution_plan_v2.py"
FULL_PATH = HERE.parent / "transversal_assets" / "full_regression" / "full_regression_v1.py"
JUDGE_PATH = HERE.parent / "transversal_assets" / "full_regression" / "judge_full_regression_semantics_v1.py"
SUPER_ADMIN_TEST_PATH = HERE / "test_lf_ci_super_admin_plan_binding_v1.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


P = load(PLAN_PATH, "lf_ci_execution_plan_v2_tested")
F = load(FULL_PATH, "lf_full_regression_v1_tested")
SUPER_ADMIN_TEST = load(SUPER_ADMIN_TEST_PATH, "lf_ci_super_admin_plan_binding_v1_tested")


def make_repo(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="lf-ci-plan-v2-"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def plan(paths: list[str], files: dict[str, str], lane=(), mode="SPECIALIZED_REQUIRED", *, force_full=False, force_reason=None, registry_path: Path | None = None):
    kwargs = {}
    if registry_path is not None:
        kwargs["registry_path"] = registry_path
    return P.build_plan(
        changed_paths=paths,
        lane_required_controls=lane,
        lane_mode=mode,
        repo_root=make_repo(files),
        force_full=force_full,
        force_full_reason=force_reason,
        **kwargs,
    )


def expect_plan_error(code: str, fn) -> None:
    try:
        fn()
    except P.PlanError as exc:
        assert str(exc).startswith(code), (str(exc), code)
    else:
        raise AssertionError(f"expected PlanError {code}")


def expect_full_error(code: str, fn) -> None:
    try:
        fn()
    except F.FullRegressionError as exc:
        assert exc.code == code, (exc.code, code, str(exc))
    else:
        raise AssertionError(f"expected FullRegressionError {code}")


def receipts_for(got: dict, source_revision: str = "a" * 40) -> list[dict]:
    return [
        F.build_carrier_receipt(
            carrier=carrier,
            plan_sha256=got["plan_sha256"],
            source_revision=source_revision,
            executed_controls=controls,
        )
        for carrier, controls in sorted(got["carrier_controls"].items())
    ]


def test_candidate_bound_migration() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    got = plan([path], {path: "select * from public.lf_operation_policy_bindings;"})
    required = set(got["required_controls"])
    assert {"MIGRATION_SOURCE_PARITY", "DB_CANDIDATE_APPLY_ROLLBACK", "POLICY_RESOLVER_REGRESSION", "LF_CONTRACT_CORE"}.issubset(required)
    assert got["applicability_decision"] == "APPLY"
    assert got["coverage_complete"] is True
    assert got["run_everything"] is False


def test_profile_change_does_not_select_database_regression() -> None:
    path = "profiles/quality_pack/SKILL.md"
    got = plan([path], {path: "# profile"})
    required = set(got["required_controls"])
    assert {"PROFILE_RUNTIME_V3", "PROFILE_PACK", "NO_BYPASS_PROFILE_CARD_SKILL", "PASS_EVIDENCE", "LF_CONTRACT_CORE"}.issubset(required)
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in required
    assert "REMOTE_SCHEMA_REPRODUCIBILITY" not in required


def test_unresolved_applicability_blocks() -> None:
    path = "mystery/new_surface.xyz"
    expect_plan_error("FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED", lambda: plan([path], {path: "x"}, mode="DEEP_SHARED_UNKNOWN"))


def test_force_full_is_verification_only() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    regular = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    requested = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN", force_full=True, force_reason="MANUAL_VERIFICATION")
    assert requested["required_controls"] == regular["required_controls"] == ["P0_FAST_DOCS"]
    assert requested["full_regression"] is True
    assert requested["full_regression_semantics"] == "CONSUME_GOVERNED_PLAN_ONLY"
    assert requested["local_applicability_decisions"] == 0
    assert requested["run_everything"] is False


def test_router_self_change_does_not_expand_applicability() -> None:
    path = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
    got = plan([path], {path: "x"}, lane=("CI_ROUTER_SELFTEST",), mode="CI_ROUTER_SELFTEST_ONLY")
    assert got["full_regression"] is True
    assert got["full_regression_reason"] == "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE_VERIFICATION"
    assert "CI_ROUTER_SELFTEST" in got["required_controls"]
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in got["required_controls"]


def test_carrier_self_change_is_observability_only() -> None:
    path = ".github/workflows/validate-lf-packs.yml"
    got = plan([path], {path: "name: validate-lf-packs\n"}, lane=("CI_ROUTER_SELFTEST",), mode="CI_ROUTER_SELFTEST_ONLY")
    assert got["carrier_regression"] is True
    assert got["carrier_regression_carriers"] == ["VALIDATE_LF_PACKS"]
    assert got["carrier_regression_semantics"] == "OBSERVABILITY_ONLY_NO_CONTROL_EXPANSION"
    assert "PROFILE_PACK" not in got["required_controls"]
    assert "S30_BOUNDED_REGRESSION" not in got["required_controls"]


def test_legacy_full_list_has_zero_applicability_effect() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    baseline = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    data = json.loads(P.REGISTRY_PATH.read_text(encoding="utf-8"))
    data["full_regression_controls"] = []
    with tempfile.TemporaryDirectory(prefix="lf-ci-registry-") as td:
        altered = Path(td) / "registry.json"
        altered.write_text(json.dumps(data), encoding="utf-8")
        got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN", registry_path=altered)
    assert got["required_controls"] == baseline["required_controls"]
    assert got["carrier_controls"] == baseline["carrier_controls"]
    assert got["legacy_full_regression_registry_semantics"] == "HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY"


def test_retired_control_and_carrier_reintroduction_block() -> None:
    data = json.loads(P.REGISTRY_PATH.read_text(encoding="utf-8"))
    data["controls"].append({
        "control_id": "REMOTE_SCHEMA_REPRODUCIBILITY",
        "carrier": "LF_DB_REGRESSION",
        "path_matchers": [],
        "material_matchers": [],
        "dependencies": [],
    })
    with tempfile.TemporaryDirectory(prefix="lf-retired-control-") as td:
        p = Path(td) / "registry.json"
        p.write_text(json.dumps(data), encoding="utf-8")
        expect_plan_error("FAIL_CI_RETIRED_CONTROL_REINTRODUCED", lambda: P.load_registry(p))


def test_dependency_closure_is_explicit() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    got = plan([path], {path: "select * from public.lf_operation_policy_bindings;"})
    reasons = got["required_control_reasons"]
    assert "DEPENDENCY_OF:POLICY_RESOLVER_REGRESSION" in reasons["DB_CANDIDATE_APPLY_ROLLBACK"]
    assert "DEPENDENCY_OF:DB_CANDIDATE_APPLY_ROLLBACK" in reasons["MIGRATION_SOURCE_PARITY"]


def test_known_no_trigger_is_not_applicable_zero_execution() -> None:
    path = "services/non_profile_runtime/example.py"
    got = plan([path], {path: "print('x')\n"}, lane=(), mode="DEEP_SHARED_KNOWN")
    assert got["required_controls"] == []
    assert got["applicability_decision"] == "NOT_APPLICABLE"
    out = F.consume(got, [])
    assert out["status"] == "NOT_APPLICABLE"
    assert out["executed_controls"] == []


def test_plan_replay_is_deterministic() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    files = {path: "# evidence"}
    a = plan([path], files, mode="DEEP_SHARED_KNOWN")
    b = plan([path], files, mode="DEEP_SHARED_KNOWN")
    assert json.dumps(a, sort_keys=True, separators=(",", ":")) == json.dumps(b, sort_keys=True, separators=(",", ":"))
    P.validate_plan_contract(a)


def test_partial_plan_receipts_match_exactly() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    out = F.consume(got, receipts_for(got))
    assert out["status"] == "PASS"
    assert out["planned_controls"] == out["executed_controls"] == ["P0_FAST_DOCS"]
    assert out["duplicate_control_executions"] == 0


def test_invalid_plan_and_bad_receipts_fail_closed() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    broken = copy.deepcopy(got)
    broken["required_controls"].append("UNPLANNED")
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_INVALID", lambda: F.consume(broken, []))
    receipt = receipts_for(got)[0]
    bad = copy.deepcopy(receipt)
    bad["receipt_sha256"] = "0" * 64
    expect_full_error("BLOCK_FULL_REGRESSION_RECEIPT_SHA", lambda: F.consume(got, [bad]))
    expect_full_error("BLOCK_FULL_REGRESSION_DUPLICATE_CARRIER_RECEIPT", lambda: F.consume(got, [receipt, receipt]))


def test_stale_source_authority_blocks() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    stale = copy.deepcopy(got)
    stale["source_authority"] = {"ready": False}
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_STALE_OR_UNREADY", lambda: F.consume(stale, []))


def test_super_admin_plan_binding_preserved() -> None:
    SUPER_ADMIN_TEST.main()


def test_semantic_judge_p1_p8() -> None:
    completed = subprocess.run(
        [sys.executable, str(JUDGE_PATH)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=30,
    )
    print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    assert completed.returncode == 0, completed.stdout[-4000:]
    assert "FULL_REGRESSION_SEMANTIC_JUDGE_PASS P1-P8=8/8" in completed.stdout


def main() -> None:
    tests = [
        test_candidate_bound_migration,
        test_profile_change_does_not_select_database_regression,
        test_unresolved_applicability_blocks,
        test_force_full_is_verification_only,
        test_router_self_change_does_not_expand_applicability,
        test_carrier_self_change_is_observability_only,
        test_legacy_full_list_has_zero_applicability_effect,
        test_retired_control_and_carrier_reintroduction_block,
        test_dependency_closure_is_explicit,
        test_known_no_trigger_is_not_applicable_zero_execution,
        test_plan_replay_is_deterministic,
        test_partial_plan_receipts_match_exactly,
        test_invalid_plan_and_bad_receipts_fail_closed,
        test_stale_source_authority_blocks,
        test_super_admin_plan_binding_preserved,
        test_semantic_judge_p1_p8,
    ]
    for test in tests:
        test()
    print(f"LF_CI_EXECUTION_PLAN_V2_PASS={len(tests)}/{len(tests)}")
    print("FULL_REGRESSION_DETERMINISTIC_PASS P1-P8=8/8")


if __name__ == "__main__":
    main()
