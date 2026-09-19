#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

M = importlib.import_module("PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT")

VISUAL_NAMES = (
    "_run_human_review_convergence_contract",
    "_run_dual_ocr_reconciliation_contract",
    "_run_icon_structural_role_contract",
    "_run_multiscreen_structural_generalization_contract",
)


def write_plan(path: Path, controls) -> None:
    path.write_text(json.dumps({"required_controls": controls}), encoding="utf-8")


def with_spies():
    called = []
    original = {}
    for name in VISUAL_NAMES:
        original[name] = getattr(M, name)
        setattr(M, name, lambda name=name: called.append(name))
    return called, original


def restore(original) -> None:
    for name, value in original.items():
        setattr(M, name, value)


def test_not_applicable_skips_all_visual_contracts() -> None:
    with tempfile.TemporaryDirectory() as td:
        plan = Path(td) / "plan.json"
        write_plan(plan, ["LF_CONTRACT_CORE", "MIGRATION_SOURCE_PARITY"])
        called, original = with_spies()
        try:
            ran = M._run_p0_visual_runtime_contracts_if_required(plan)
        finally:
            restore(original)
        assert ran is False
        assert called == []


def test_required_runs_all_visual_contracts() -> None:
    with tempfile.TemporaryDirectory() as td:
        plan = Path(td) / "plan.json"
        write_plan(plan, ["LF_CONTRACT_CORE", "P0_VISUAL_RUNTIME"])
        called, original = with_spies()
        try:
            ran = M._run_p0_visual_runtime_contracts_if_required(plan)
        finally:
            restore(original)
        assert ran is True
        assert called == list(VISUAL_NAMES)


def test_missing_plan_is_fail_closed_and_runs_visual_contracts() -> None:
    with tempfile.TemporaryDirectory() as td:
        plan = Path(td) / "missing.json"
        called, original = with_spies()
        try:
            ran = M._run_p0_visual_runtime_contracts_if_required(plan)
        finally:
            restore(original)
        assert ran is True
        assert called == list(VISUAL_NAMES)


def test_malformed_plan_blocks_instead_of_skipping() -> None:
    with tempfile.TemporaryDirectory() as td:
        plan = Path(td) / "plan.json"
        plan.write_text('{"required_controls":"not-a-list"}', encoding="utf-8")
        called, original = with_spies()
        try:
            try:
                M._run_p0_visual_runtime_contracts_if_required(plan)
            except SystemExit as exc:
                assert str(exc) == "FAIL_P0_VISUAL_APPLICABILITY_REQUIRED_CONTROLS_INVALID"
            else:
                raise AssertionError("malformed plan must block")
        finally:
            restore(original)
        assert called == []


def main() -> None:
    tests = [
        test_not_applicable_skips_all_visual_contracts,
        test_required_runs_all_visual_contracts,
        test_missing_plan_is_fail_closed_and_runs_visual_contracts,
        test_malformed_plan_blocks_instead_of_skipping,
    ]
    for test in tests:
        test()
    print(f"PASS_P0_VISUAL_WRAPPER_APPLICABILITY={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
