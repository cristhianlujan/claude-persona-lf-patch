#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "visual_evidence_gate_v1.py"
spec = importlib.util.spec_from_file_location("visual_evidence_gate_v1_test_subject", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_VISUAL_EVIDENCE_GATE_TEST_LOAD")
M = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = M
spec.loader.exec_module(M)


def materialize(root: Path) -> None:
    for _, relative in M.CANONICAL_HELPERS:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("#!/usr/bin/env python3\n", encoding="utf-8")


def check(condition: bool, code: str) -> None:
    if not condition:
        raise AssertionError(code)


def test_identity_and_boundary() -> None:
    check(M.CONTROL_ID == "VISUAL_EVIDENCE_GATE", "ID_NOT_DURABLE")
    check(M.LEGACY_ORCHESTRATION_ALIAS == "P0_VISUAL_RUNTIME", "LEGACY_ALIAS_MISSING")
    check(M.CONTROL_ID != M.LEGACY_ORCHESTRATION_ALIAS, "RENAMING_NOT_REAL")
    result = M.self_test(M.REPO_ROOT)
    check(result["ownership"]["visual_evidence_validation"] is True, "VISUAL_OWNER_MISSING")
    for foreign in (
        "applicability",
        "path_admission",
        "exact_head_transport",
        "human_decision_persistence",
        "runtime_or_production_authorization",
    ):
        check(result["ownership"][foreign] is False, f"FOREIGN_OWNERSHIP:{foreign}")


def test_clean_execution_preserves_order() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        materialize(root)
        calls: list[str] = []

        def runner(argv, **kwargs):
            calls.append(Path(argv[1]).name)
            return SimpleNamespace(returncode=0)

        result = M.run_gate(root, runner=runner, executable="python3", environment={})
        expected_names = [Path(path).name for _, path in M.CANONICAL_HELPERS]
        check(calls == expected_names, "HELPER_ORDER_DRIFT")
        check(result["result"] == "PASS", "CLEAN_RESULT_NOT_PASS")
        check(result["executed_checks"] == [name for name, _ in M.CANONICAL_HELPERS], "CHECK_ORDER_DRIFT")


def test_missing_helper_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        materialize(root)
        missing = root / M.CANONICAL_HELPERS[-1][1]
        missing.unlink()
        try:
            M.resolve_helpers(root)
        except M.VisualEvidenceGateError as exc:
            check("HELPER_MISSING" in str(exc), "WRONG_MISSING_HELPER_ERROR")
        else:
            raise AssertionError("MISSING_HELPER_ALLOWED")


def test_failed_helper_stops_gate() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        materialize(root)
        calls: list[str] = []

        def runner(argv, **kwargs):
            name = Path(argv[1]).name
            calls.append(name)
            return SimpleNamespace(returncode=7 if len(calls) == 2 else 0)

        try:
            M.run_gate(root, runner=runner, executable="python3", environment={})
        except M.VisualEvidenceGateError as exc:
            check("FAIL_VISUAL_EVIDENCE_GATE_CHECK" in str(exc), "WRONG_HELPER_FAILURE_ERROR")
        else:
            raise AssertionError("FAILED_HELPER_ALLOWED")
        check(len(calls) == 2, "GATE_DID_NOT_STOP_ON_FIRST_FAILURE")


def test_foreign_responsibility_guard() -> None:
    original = M.CANONICAL_HELPERS
    try:
        M.CANONICAL_HELPERS = (
            ("BAD", "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v2.py"),
            *original[1:],
        )
        try:
            M._validate_contract_shape()
        except M.VisualEvidenceGateError as exc:
            check("FOREIGN_RESPONSIBILITY" in str(exc), "WRONG_FOREIGN_BOUNDARY_ERROR")
        else:
            raise AssertionError("FOREIGN_RESPONSIBILITY_ALLOWED")
    finally:
        M.CANONICAL_HELPERS = original


def main() -> int:
    tests = (
        test_identity_and_boundary,
        test_clean_execution_preserves_order,
        test_missing_helper_fails_closed,
        test_failed_helper_stops_gate,
        test_foreign_responsibility_guard,
    )
    for test in tests:
        test()
    print(f"PASS_VISUAL_EVIDENCE_GATE_TESTS={len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
