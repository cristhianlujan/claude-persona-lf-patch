#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLAN_PATH = HERE / "lf_ci_execution_plan_v2.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


P = load(PLAN_PATH, "lf_ci_execution_plan_v2_tested")


def make_repo(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="lf-ci-plan-v2-"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def plan(paths: list[str], files: dict[str, str], lane=(), mode="SPECIALIZED_REQUIRED"):
    return P.build_plan(
        changed_paths=paths,
        lane_required_controls=lane,
        lane_mode=mode,
        repo_root=make_repo(files),
    )


def assert_has(got: dict, *controls: str) -> None:
    actual = set(got["required_controls"])
    for control in controls:
        assert control in actual, (control, sorted(actual))


def assert_not(got: dict, *controls: str) -> None:
    actual = set(got["required_controls"])
    for control in controls:
        assert control not in actual, (control, sorted(actual))


def test_policy_resolver_migration_is_precise_and_candidate_bound() -> None:
    path = "supabase/migrations/20260918042000_s30_operation_policy_context_v1.sql"
    got = plan([path], {path: "create or replace view public.v_lf_operation_policy_snapshot as select 1;"})
    assert got["coverage_complete"] is True
    assert got["full_regression"] is False
    assert_has(
        got,
        "MIGRATION_SOURCE_PARITY",
        "DB_CANDIDATE_APPLY_ROLLBACK",
        "POLICY_RESOLVER_REGRESSION",
        "LF_CONTRACT_CORE",
    )
    assert_not(
        got,
        "INPUT_GOVERNANCE_MIGRATION_PARITY",
        "V7_RUNTIME_REGRESSION",
        "REMOTE_SCHEMA_REPRODUCIBILITY",
        "PROFILE_RUNTIME_V3",
        "P0_VISUAL_RUNTIME",
        "S36_ASSURANCE",
        "R8_USER_STORY_AUDIT",
    )
    evidence = got["material_evidence"][0]
    assert evidence["kind"] == "SQL_MIGRATION"
    assert evidence["sha256"]
    assert "POLICY_RESOLVER_REGRESSION" in evidence["matched_controls"]


def test_v7_material_selects_v7_regression() -> None:
    path = "supabase/migrations/20260801180000_writer_hmac_nonce_v7.sql"
    got = plan([path], {path: "create table writer_hmac_nonce_v7(id bigint);"})
    assert_has(got, "V7_RUNTIME_REGRESSION", "DB_CANDIDATE_APPLY_ROLLBACK", "MIGRATION_SOURCE_PARITY")


def test_profile_change_does_not_select_database_bootstrap() -> None:
    path = "profiles/quality_pack/SKILL.md"
    got = plan([path], {path: "# profile"})
    assert_has(got, "PROFILE_RUNTIME_V3", "PROFILE_PACK", "NO_BYPASS_PROFILE_CARD_SKILL", "PASS_EVIDENCE", "LF_CONTRACT_CORE")
    assert_not(got, "DB_CANDIDATE_APPLY_ROLLBACK", "REMOTE_SCHEMA_REPRODUCIBILITY", "V7_RUNTIME_REGRESSION")


def test_unknown_surface_fails_closed_to_full_regression() -> None:
    path = "mystery/new_surface.xyz"
    got = plan([path], {path: "x"}, mode="DEEP_SHARED_UNKNOWN")
    assert got["full_regression"] is True
    assert got["full_regression_reason"] == "UNKNOWN_SCOPE_FAIL_CLOSED"
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in got["required_controls"]
    assert "POLICY_RESOLVER_REGRESSION" not in got["required_controls"]
    assert "P0_FAST_DOCS" not in got["required_controls"]
    assert len(got["required_controls"]) + len(got["not_applicable_controls"]) == len(got["control_universe"])


def test_router_self_change_forces_full_regression() -> None:
    path = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
    got = plan([path], {path: "x"}, lane=("CI_ROUTER_SELFTEST",), mode="CI_ROUTER_SELFTEST_ONLY")
    assert got["full_regression"] is True
    assert got["full_regression_reason"] == "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE"
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in got["required_controls"]
    assert "POLICY_RESOLVER_REGRESSION" not in got["required_controls"]
    assert "P0_FAST_DOCS" not in got["required_controls"]
    assert len(got["required_controls"]) + len(got["not_applicable_controls"]) == len(got["control_universe"])


def test_dependency_closure_is_explicit() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    got = plan([path], {path: "select * from public.lf_operation_policy_bindings;"})
    reasons = got["required_control_reasons"]
    assert "DEPENDENCY_OF:POLICY_RESOLVER_REGRESSION" in reasons["DB_CANDIDATE_APPLY_ROLLBACK"]
    assert "DEPENDENCY_OF:DB_CANDIDATE_APPLY_ROLLBACK" in reasons["MIGRATION_SOURCE_PARITY"]



def test_exact_p0_fast_doc_is_single_control() -> None:
    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    got = plan([path], {path: "# evidence"}, lane=(), mode="DEEP_SHARED_KNOWN")
    assert got["full_regression"] is False
    assert got["required_controls"] == ["P0_FAST_DOCS"], got["required_controls"]
    assert got["coverage_complete"] is True



def test_material_evidence_reads_exact_source_ref_not_checkout_tree() -> None:
    root = make_repo({})
    subprocess.run(["git","init"],cwd=root,check=True,capture_output=True)
    subprocess.run(["git","config","user.email","ci@example.invalid"],cwd=root,check=True)
    subprocess.run(["git","config","user.name","CI"],cwd=root,check=True)
    path = "supabase/migrations/20260918042000_policy.sql"
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    committed = b"select * from public.lf_operation_policy_bindings;\n"
    target.write_bytes(committed)
    subprocess.run(["git","add",path],cwd=root,check=True)
    subprocess.run(["git","commit","-m","candidate"],cwd=root,check=True,capture_output=True)
    head = subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip()
    target.write_text("select 42;\n",encoding="utf-8")
    got = P.build_plan(
        changed_paths=[path],
        lane_required_controls=(),
        lane_mode="SPECIALIZED_REQUIRED",
        repo_root=root,
        source_ref=head,
    )
    evidence = got["material_evidence"][0]
    assert evidence["source_ref"] == head
    assert evidence["sha256"] == hashlib.sha256(committed).hexdigest()
    assert "POLICY_RESOLVER_REGRESSION" in got["required_controls"]



def test_full_regression_keeps_candidate_bound_migration_controls() -> None:
    workflow = ".github/workflows/lf-contract-check.yml"
    migration = "supabase/migrations/20260918042000_policy.sql"
    files = {
        workflow: "name: lf-contract-check\n",
        migration: "select * from public.lf_operation_policy_bindings;\n",
    }
    got = plan(
        [workflow, migration],
        files,
        lane=("CI_ROUTER_SELFTEST","MIGRATION_SOURCE_PARITY"),
        mode="SPECIALIZED_REQUIRED",
    )
    assert got["full_regression"] is True
    assert got["full_regression_reason"] == "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE"
    assert_has(
        got,
        "CI_ROUTER_SELFTEST",
        "MIGRATION_SOURCE_PARITY",
        "DB_CANDIDATE_APPLY_ROLLBACK",
        "POLICY_RESOLVER_REGRESSION",
    )


def test_plan_replay_is_deterministic() -> None:
    path = "supabase/migrations/20260918042000_policy.sql"
    files = {path: "select * from public.lf_operation_policy_bindings;"}
    a = plan([path], files)
    b = plan([path], files)
    assert json.dumps(a, sort_keys=True, separators=(",", ":")) == json.dumps(b, sort_keys=True, separators=(",", ":"))


def main() -> None:
    tests = [
        test_policy_resolver_migration_is_precise_and_candidate_bound,
        test_v7_material_selects_v7_regression,
        test_profile_change_does_not_select_database_bootstrap,
        test_unknown_surface_fails_closed_to_full_regression,
        test_router_self_change_forces_full_regression,
        test_dependency_closure_is_explicit,
        test_exact_p0_fast_doc_is_single_control,
        test_material_evidence_reads_exact_source_ref_not_checkout_tree,
        test_full_regression_keeps_candidate_bound_migration_controls,
        test_plan_replay_is_deterministic,
    ]
    for test in tests:
        test()
    print(f"LF_CI_EXECUTION_PLAN_V2_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
