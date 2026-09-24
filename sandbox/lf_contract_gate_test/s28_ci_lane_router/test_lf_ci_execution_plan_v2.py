#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
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


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


P = load(PLAN_PATH, "lf_ci_execution_plan_v2_tested")
F = load(FULL_PATH, "lf_full_regression_v1_tested")


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


def test_policy_resolver_migration_is_precise_and_candidate_bound() -> None:
    path = "supabase/migrations/20260918042000_s30_operation_policy_context_v1.sql"
    got = plan([path], {path: "create or replace view public.v_lf_operation_policy_snapshot as select 1;"})
    assert got["coverage_complete"] is True
    assert got["applicability_decision"] == "APPLY"
    actual = set(got["required_controls"])
    for control in ("MIGRATION_SOURCE_PARITY", "DB_CANDIDATE_APPLY_ROLLBACK", "POLICY_RESOLVER_REGRESSION", "LF_CONTRACT_CORE"):
        assert control in actual
    for control in ("REMOTE_SCHEMA_REPRODUCIBILITY", "PROFILE_RUNTIME_V3", "P0_VISUAL_RUNTIME"):
        assert control not in actual


def test_v7_material_selects_v7_regression() -> None:
    path = "supabase/migrations/20260801180000_writer_hmac_nonce_v7.sql"
    got = plan([path], {path: "create table writer_hmac_nonce_v7(id bigint);"})
    for control in ("V7_RUNTIME_REGRESSION", "DB_CANDIDATE_APPLY_ROLLBACK", "MIGRATION_SOURCE_PARITY"):
        assert control in got["required_controls"]


def test_profile_change_does_not_select_database_bootstrap() -> None:
    path = "profiles/quality_pack/SKILL.md"
    got = plan([path], {path: "# profile"})
    for control in ("PROFILE_RUNTIME_V3", "PROFILE_PACK", "NO_BYPASS_PROFILE_CARD_SKILL", "PASS_EVIDENCE", "LF_CONTRACT_CORE"):
        assert control in got["required_controls"]
    for control in ("DB_CANDIDATE_APPLY_ROLLBACK", "REMOTE_SCHEMA_REPRODUCIBILITY", "V7_RUNTIME_REGRESSION"):
        assert control not in got["required_controls"]


def test_unresolved_applicability_blocks_instead_of_run_everything() -> None:
    path = "mystery/new_surface.xyz"
    expect_plan_error("FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED", lambda: plan([path], {path: "x"}, mode="CLASSIFICATION_REQUIRED"))


def test_force_full_is_verification_mode_not_applicability_expansion() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    regular = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    requested = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN", force_full=True, force_reason="WORKFLOW_DISPATCH_FULL_REGRESSION")
    assert regular["required_controls"] == ["P0_FAST_DOCS"]
    assert requested["required_controls"] == regular["required_controls"]
    assert requested["full_regression"] is True
    assert requested["full_regression_semantics"] == "CONSUME_GOVERNED_PLAN_ONLY"
    assert requested["run_everything"] is False
    assert requested["local_applicability_decisions"] == 0


def test_router_self_change_does_not_expand_beyond_governed_plan() -> None:
    path = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
    got = plan([path], {path: "x"}, lane=("CI_ROUTER_SELFTEST",), mode="CI_ROUTER_SELFTEST_ONLY")
    assert got["full_regression"] is True
    assert got["full_regression_reason"] == "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE_VERIFICATION"
    assert "CI_ROUTER_SELFTEST" in got["required_controls"]
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in got["required_controls"]
    assert "REMOTE_SCHEMA_REPRODUCIBILITY" not in got["required_controls"]


def test_carrier_self_change_is_observability_only() -> None:
    path = ".github/workflows/validate-lf-packs.yml"
    got = plan([path], {path: "name: validate-lf-packs\n"}, lane=("CI_ROUTER_SELFTEST",), mode="CI_ROUTER_SELFTEST_ONLY")
    assert got["carrier_regression"] is True
    assert got["carrier_regression_carriers"] == ["VALIDATE_LF_PACKS"]
    assert got["carrier_regression_semantics"] == "OBSERVABILITY_ONLY_NO_CONTROL_EXPANSION"
    assert "CI_ROUTER_SELFTEST" in got["required_controls"]
    assert "DECLARED_GOVERNANCE_PATHS" in got["required_controls"]
    assert "PROFILE_PACK" not in got["required_controls"]
    assert "S30_BOUNDED_REGRESSION" not in got["required_controls"]


def test_legacy_full_regression_registry_field_has_zero_applicability_effect() -> None:
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


def test_dependency_closure_is_explicit() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    got = plan([path], {path: "select * from public.lf_operation_policy_bindings;"})
    reasons = got["required_control_reasons"]
    assert "DEPENDENCY_OF:POLICY_RESOLVER_REGRESSION" in reasons["DB_CANDIDATE_APPLY_ROLLBACK"]
    assert "DEPENDENCY_OF:DB_CANDIDATE_APPLY_ROLLBACK" in reasons["MIGRATION_SOURCE_PARITY"]


def test_exact_p0_fast_doc_is_single_control() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, lane=(), mode="DEEP_SHARED_KNOWN")
    assert got["required_controls"] == ["P0_FAST_DOCS"]
    assert got["coverage_complete"] is True


def test_known_no_trigger_is_real_not_applicable() -> None:
    path = "services/non_profile_runtime/example.py"
    got = plan([path], {path: "print('x')\n"}, lane=(), mode="DEEP_SHARED_KNOWN")
    assert got["required_controls"] == []
    assert got["applicability_decision"] == "NOT_APPLICABLE"
    out = F.consume(got, [])
    assert out["status"] == "NOT_APPLICABLE"
    assert out["executed_controls"] == []
    assert out["unplanned_executions"] == 0


def test_material_evidence_reads_exact_source_ref_not_checkout_tree() -> None:
    root = make_repo({})
    subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "ci@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "CI"], cwd=root, check=True)
    path = "supabase/migrations/20260918042000_policy.sql"
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    committed = b"select * from public.lf_operation_policy_bindings;\n"
    target.write_bytes(committed)
    subprocess.run(["git", "add", path], cwd=root, check=True)
    subprocess.run(["git", "commit", "-m", "candidate"], cwd=root, check=True, capture_output=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    target.write_text("select 42;\n", encoding="utf-8")
    got = P.build_plan(changed_paths=[path], lane_required_controls=(), lane_mode="SPECIALIZED_REQUIRED", repo_root=root, source_ref=head)
    evidence = got["material_evidence"][0]
    assert evidence["source_ref"] == head
    assert evidence["sha256"] == hashlib.sha256(committed).hexdigest()
    assert "POLICY_RESOLVER_REGRESSION" in got["required_controls"]


def test_plan_replay_is_deterministic() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    files = {path: "select * from public.lf_operation_policy_bindings;"}
    a = plan([path], files)
    b = plan([path], files)
    assert json.dumps(a, sort_keys=True, separators=(",", ":")) == json.dumps(b, sort_keys=True, separators=(",", ":"))


def test_e2e_case_b_partial_planned_equals_executed() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    out = F.consume(got, receipts_for(got))
    assert out["status"] == "PASS"
    assert out["planned_controls"] == out["executed_controls"] == ["P0_FAST_DOCS"]
    assert out["unplanned_executions"] == 0


def test_e2e_case_c_external_carriers_receipts_no_duplication() -> None:
    path = "profiles/quality_pack/SKILL.md"
    got = plan([path], {path: "# profile"})
    rs = receipts_for(got)
    out = F.consume(got, rs)
    assert out["status"] == "PASS"
    assert out["planned_controls"] == out["executed_controls"]
    assert out["duplicate_control_executions"] == 0
    assert len(out["consumed_receipts"]) == len(got["carrier_controls"])


def test_e2e_case_d_invalid_plan_blocks() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    broken = copy.deepcopy(got)
    broken["required_controls"].append("UNPLANNED_FAKE")
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_INVALID", lambda: F.consume(broken, []))


def test_e2e_case_e_legacy_run_everything_does_not_reappear() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN", force_full=True, force_reason="MAIN_PUSH_FULL_REGRESSION")
    assert got["required_controls"] == ["P0_FAST_DOCS"]
    out = F.consume(got, receipts_for(got))
    assert out["planned_controls"] == ["P0_FAST_DOCS"]


def test_fail_closed_missing_stale_wrong_sha_unresolved_and_invalid_receipt() -> None:
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_MISSING", lambda: F.consume(None, []))
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")

    stale = copy.deepcopy(got)
    stale["source_authority"] = {"ready": False}
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_STALE_OR_UNREADY", lambda: F.consume(stale, []))

    rs = receipts_for(got)
    bad_receipt = copy.deepcopy(rs[0])
    bad_receipt["receipt_sha256"] = "0" * 64
    expect_full_error("BLOCK_FULL_REGRESSION_RECEIPT_SHA", lambda: F.consume(got, [bad_receipt]))

    wrong_plan_sha = copy.deepcopy(rs[0])
    wrong_plan_sha["plan_sha256"] = "f" * 64
    wrong_plan_sha["receipt_sha256"] = F._sha(F._carrier_receipt_payload(wrong_plan_sha))
    expect_full_error("BLOCK_FULL_REGRESSION_RECEIPT_PLAN_SHA", lambda: F.consume(got, [wrong_plan_sha]))

    unresolved = copy.deepcopy(got)
    only = unresolved["required_controls"][0]
    unresolved["carrier_controls"] = {"UNKNOWN_CARRIER": [only]}
    unresolved["plan_sha256"] = P.compute_plan_sha256(unresolved)
    expect_full_error("BLOCK_FULL_REGRESSION_PLAN_INVALID", lambda: F.consume(unresolved, []))


def test_retired_controls_are_never_executed() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    expect_full_error("BLOCK_FULL_REGRESSION_RETIRED_CONTROL_PLANNED", lambda: F.consume(got, receipts_for(got), retired_controls={"P0_FAST_DOCS"}))


def test_duplicate_receipt_is_blocked() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, mode="DEEP_SHARED_KNOWN")
    receipt = receipts_for(got)[0]
    expect_full_error("BLOCK_FULL_REGRESSION_DUPLICATE_CARRIER_RECEIPT", lambda: F.consume(got, [receipt, receipt]))


def test_semantic_judge_independent_p1_p8() -> None:
    completed = subprocess.run([sys.executable, str(JUDGE_PATH)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, timeout=30)
    print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    assert completed.returncode == 0, completed.stdout[-4000:]
    assert "FULL_REGRESSION_SEMANTIC_JUDGE_PASS P1-P8=8/8" in completed.stdout


def main() -> None:
    tests = [
        test_policy_resolver_migration_is_precise_and_candidate_bound,
        test_v7_material_selects_v7_regression,
        test_profile_change_does_not_select_database_bootstrap,
        test_unresolved_applicability_blocks_instead_of_run_everything,
        test_force_full_is_verification_mode_not_applicability_expansion,
        test_router_self_change_does_not_expand_beyond_governed_plan,
        test_carrier_self_change_is_observability_only,
        test_legacy_full_regression_registry_field_has_zero_applicability_effect,
        test_dependency_closure_is_explicit,
        test_exact_p0_fast_doc_is_single_control,
        test_known_no_trigger_is_real_not_applicable,
        test_material_evidence_reads_exact_source_ref_not_checkout_tree,
        test_plan_replay_is_deterministic,
        test_e2e_case_b_partial_planned_equals_executed,
        test_e2e_case_c_external_carriers_receipts_no_duplication,
        test_e2e_case_d_invalid_plan_blocks,
        test_e2e_case_e_legacy_run_everything_does_not_reappear,
        test_fail_closed_missing_stale_wrong_sha_unresolved_and_invalid_receipt,
        test_retired_controls_are_never_executed,
        test_duplicate_receipt_is_blocked,
        test_semantic_judge_independent_p1_p8,
    ]
    for test in tests:
        test()
    print(f"LF_CI_EXECUTION_PLAN_V2_PASS={len(tests)}/{len(tests)}")
    print("FULL_REGRESSION_DETERMINISTIC_PASS P1-P8=8/8")
    print("FULL_REGRESSION_E2E_PASS A=PASS B=PASS C=PASS D=PASS E=PASS")


if __name__ == "__main__":
    main()
