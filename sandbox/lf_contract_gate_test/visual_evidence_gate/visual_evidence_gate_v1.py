#!/usr/bin/env python3
"""Standalone pass-level owner for visual evidence validation.

`VISUAL_EVIDENCE_GATE` is the durable logical identity that replaces the legacy
orchestration label `P0_VISUAL_RUNTIME`.  The existing historical P0 helpers are
reused as implementation dependencies; they are not copied or renamed here.

Boundary:
- owns execution of the visual completeness/fidelity regression bundle;
- does not decide applicability;
- does not own repository/path admission;
- does not own exact-head evidence transport or persistence;
- does not persist/authenticate human decisions;
- does not authorize runtime or production.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Callable, Mapping, Sequence

SCHEMA_VERSION = "lf-visual-evidence-gate/v1"
CONTROL_ID = "VISUAL_EVIDENCE_GATE"
LEGACY_ORCHESTRATION_ALIAS = "P0_VISUAL_RUNTIME"
REPO_ROOT = Path(__file__).resolve().parents[3]

CANONICAL_HELPERS: tuple[tuple[str, str], ...] = (
    (
        "HUMAN_REVIEW_CONVERGENCE_CONTRACT",
        "sandbox/lf_contract_gate_test/P0_HUMAN_REVIEW_CONVERGENCE_V1.py",
    ),
    (
        "DUAL_OCR_RECONCILIATION_CONTRACT",
        "sandbox/lf_contract_gate_test/P0_DUAL_OCR_RECONCILIATION_CONTRACT_V1.py",
    ),
    (
        "ICON_STRUCTURAL_ROLE_REGRESSION",
        "sandbox/lf_contract_gate_test/P0_ICON_STRUCTURAL_ROLE_REGRESSION_V1.py",
    ),
    (
        "MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION",
        "sandbox/lf_contract_gate_test/P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V3.py",
    ),
)


class VisualEvidenceGateError(RuntimeError):
    pass


def _safe_relative_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value:
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def _validate_contract_shape() -> None:
    if CONTROL_ID == LEGACY_ORCHESTRATION_ALIAS:
        raise VisualEvidenceGateError("FAIL_VISUAL_EVIDENCE_GATE_ID_NOT_RENAMED")
    if len(CANONICAL_HELPERS) != 4:
        raise VisualEvidenceGateError("FAIL_VISUAL_EVIDENCE_GATE_HELPER_COUNT")
    names = [name for name, _ in CANONICAL_HELPERS]
    paths = [path for _, path in CANONICAL_HELPERS]
    if len(names) != len(set(names)):
        raise VisualEvidenceGateError("FAIL_VISUAL_EVIDENCE_GATE_DUPLICATE_CHECK")
    if len(paths) != len(set(paths)):
        raise VisualEvidenceGateError("FAIL_VISUAL_EVIDENCE_GATE_DUPLICATE_HELPER")
    if any(not _safe_relative_path(path) for path in paths):
        raise VisualEvidenceGateError("FAIL_VISUAL_EVIDENCE_GATE_UNSAFE_HELPER_PATH")
    forbidden = ("exact_head", "migration_parity", "lf_contract_check.py")
    leaked = sorted(path for path in paths if any(token in path.lower() for token in forbidden))
    if leaked:
        raise VisualEvidenceGateError(
            "FAIL_VISUAL_EVIDENCE_GATE_FOREIGN_RESPONSIBILITY:" + ",".join(leaked)
        )


def resolve_helpers(repo_root: Path = REPO_ROOT) -> tuple[tuple[str, Path], ...]:
    _validate_contract_shape()
    root = repo_root.resolve()
    resolved: list[tuple[str, Path]] = []
    for check_id, relative in CANONICAL_HELPERS:
        target = (root / relative).resolve()
        try:
            target.relative_to(root)
        except ValueError as exc:
            raise VisualEvidenceGateError(
                f"FAIL_VISUAL_EVIDENCE_GATE_HELPER_ESCAPES_REPO:{check_id}"
            ) from exc
        if not target.is_file():
            raise VisualEvidenceGateError(
                f"FAIL_VISUAL_EVIDENCE_GATE_HELPER_MISSING:{check_id}:{relative}"
            )
        resolved.append((check_id, target))
    return tuple(resolved)


def self_test(repo_root: Path = REPO_ROOT) -> Mapping[str, object]:
    helpers = resolve_helpers(repo_root)
    result = {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "legacy_alias": LEGACY_ORCHESTRATION_ALIAS,
        "helper_count": len(helpers),
        "checks": [check_id for check_id, _ in helpers],
        "ownership": {
            "applicability": False,
            "path_admission": False,
            "exact_head_transport": False,
            "human_decision_persistence": False,
            "runtime_or_production_authorization": False,
            "visual_evidence_validation": True,
        },
    }
    print(f"PASS_VISUAL_EVIDENCE_GATE_SELFTEST={len(helpers)}/{len(CANONICAL_HELPERS)}")
    return result


def run_gate(
    repo_root: Path = REPO_ROOT,
    *,
    runner: Callable[..., object] = subprocess.run,
    environment: Mapping[str, str] | None = None,
    executable: str | None = None,
) -> Mapping[str, object]:
    helpers = resolve_helpers(repo_root)
    env = dict(os.environ if environment is None else environment)
    python = executable or sys.executable
    executed: list[str] = []

    for check_id, helper in helpers:
        completed = runner(
            [python, str(helper)],
            cwd=repo_root.resolve(),
            env=env,
            check=False,
        )
        returncode = getattr(completed, "returncode", None)
        if not isinstance(returncode, int):
            raise VisualEvidenceGateError(
                f"FAIL_VISUAL_EVIDENCE_GATE_RUNNER_RESULT:{check_id}"
            )
        if returncode != 0:
            raise VisualEvidenceGateError(
                f"FAIL_VISUAL_EVIDENCE_GATE_CHECK:{check_id}:exit={returncode}"
            )
        executed.append(check_id)

    print(f"PASS_VISUAL_EVIDENCE_GATE={len(executed)}/{len(helpers)}")
    return {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "result": "PASS",
        "executed_checks": executed,
        "legacy_alias": LEGACY_ORCHESTRATION_ALIAS,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repo-root", default=str(REPO_ROOT))
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    root = Path(args.repo_root)
    try:
        if args.self_test:
            self_test(root)
        else:
            run_gate(root)
    except VisualEvidenceGateError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
