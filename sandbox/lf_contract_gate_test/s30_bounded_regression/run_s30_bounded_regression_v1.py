#!/usr/bin/env python3
"""Owner-local deterministic runner for S30 bounded regressions.

This runner owns only discovery/execution of existing S30 sandbox regression tests.
Applicability, pass routing, Git writes, database work, runtime, Pack Validation,
and deployment remain outside this surface.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[3]
SELF_DIR = "s30_bounded_regression"


class S30BoundedRegressionError(RuntimeError):
    pass


@dataclass(frozen=True)
class TestResult:
    path: str
    returncode: int


def discover_tests(root: Path = ROOT) -> list[Path]:
    base = root / "sandbox" / "lf_contract_gate_test"
    tests: list[Path] = []
    for path in base.glob("s30_*/test_*.py"):
        if path.parent.name == SELF_DIR:
            continue
        if path.is_file():
            tests.append(path)
    return sorted(tests, key=lambda p: p.as_posix())


def relative_paths(paths: Iterable[Path], root: Path = ROOT) -> list[str]:
    return [p.resolve().relative_to(root.resolve()).as_posix() for p in paths]


def run_tests(root: Path = ROOT) -> list[TestResult]:
    tests = discover_tests(root)
    if not tests:
        raise S30BoundedRegressionError("BLOCK_S30_SANDBOX_REGRESSION_MISSING")

    results: list[TestResult] = []
    print(f"S30_SANDBOX_TEST_COUNT={len(tests)}")
    for test_file in tests:
        rel = test_file.resolve().relative_to(root.resolve()).as_posix()
        print(f"S30_SANDBOX_TEST_RUN={rel}")
        completed = subprocess.run([sys.executable, str(test_file)], cwd=root, check=False)
        results.append(TestResult(rel, completed.returncode))
        if completed.returncode != 0:
            raise S30BoundedRegressionError(
                f"BLOCK_S30_SANDBOX_REGRESSION_FAILED:{rel}:rc={completed.returncode}"
            )
    return results


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--run", action="store_true")
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--output-json", type=Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = args.repo_root.resolve()
    tests = discover_tests(root)

    if args.list:
        payload = {
            "schema_version": "lf-s30-bounded-regression-runner/v1",
            "owner": "S30_BOUNDED_REGRESSION",
            "test_count": len(tests),
            "tests": relative_paths(tests, root),
            "executed": False,
        }
    else:
        try:
            results = run_tests(root)
        except S30BoundedRegressionError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        payload = {
            "schema_version": "lf-s30-bounded-regression-runner/v1",
            "owner": "S30_BOUNDED_REGRESSION",
            "test_count": len(results),
            "tests": [asdict(item) for item in results],
            "executed": True,
            "status": "PASS",
        }

    if args.output_json:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
