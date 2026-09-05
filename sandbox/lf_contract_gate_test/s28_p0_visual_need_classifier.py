#!/usr/bin/env python3
from __future__ import annotations

import statistics
import time
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as p0

REGULAR_MODES = {"100644", "100755"}
MIGRATION_PREFIX = "supabase/migrations/"


def needs_p0_visual(changed_files: list[str], mode_by_path: dict[str, str]) -> tuple[bool, str]:
    if not changed_files:
        return True, "NO_PATHS_FAIL_CLOSED"
    if any(not path.startswith(MIGRATION_PREFIX) for path in changed_files):
        return True, "NON_MIGRATION_OR_MIXED_FORCE_VISUAL"
    if any(mode_by_path.get(path) not in REGULAR_MODES for path in changed_files):
        return True, "MIGRATION_NONREGULAR_OR_DELETED_FORCE_VISUAL"
    if any(path in p0.CONTROLLED_RUNTIME_PATHS for path in changed_files):
        return True, "CONTROLLED_P0_RUNTIME_FORCE_VISUAL"
    return False, "MIGRATION_ONLY_NON_P0_VISUAL_NOT_MATERIAL"


def assert_case(name: str, expected: bool, changed: list[str], modes: dict[str, str]) -> None:
    observed, reason = needs_p0_visual(changed, modes)
    if observed is not expected:
        raise SystemExit(f"FAIL_{name}: expected={expected} observed={observed} reason={reason}")
    print(f"PASS_{name}: needs_p0_visual={observed} reason={reason}")


def main() -> int:
    controlled_migrations = sorted(path for path in p0.CONTROLLED_RUNTIME_PATHS if path.startswith(MIGRATION_PREFIX))
    if not controlled_migrations:
        raise SystemExit("FAIL_CONTROLLED_P0_MIGRATION_DENOMINATOR_EMPTY")
    controlled = controlled_migrations[0]
    safe_a = "supabase/migrations/20990101010101_example_non_p0_a.sql"
    safe_b = "supabase/migrations/20990101010102_example_non_p0_b.sql"

    cases = [
        ("EMPTY", True, [], {}),
        ("SAFE_MIGRATION", False, [safe_a], {safe_a: "100644"}),
        ("SAFE_MIGRATION_EXEC_MODE", False, [safe_a], {safe_a: "100755"}),
        ("SAFE_MULTI_MIGRATION", False, [safe_a, safe_b], {safe_a: "100644", safe_b: "100644"}),
        ("CONTROLLED_P0_MIGRATION", True, [controlled], {controlled: "100644"}),
        ("MIXED_DOC", True, [safe_a, "docs/p0/example.md"], {safe_a: "100644", "docs/p0/example.md": "100644"}),
        ("WORKFLOW", True, [".github/workflows/lf-contract-check.yml"], {".github/workflows/lf-contract-check.yml": "100644"}),
        ("DELETED_MIGRATION", True, [safe_a], {}),
        ("SYMLINK_MIGRATION", True, [safe_a], {safe_a: "120000"}),
    ]
    for case in cases:
        assert_case(*case)

    samples = []
    for _ in range(10000):
        start = time.perf_counter_ns()
        needs_p0_visual([safe_a], {safe_a: "100644"})
        samples.append((time.perf_counter_ns() - start) / 1000.0)
    samples.sort()
    median = statistics.median(samples)
    p95 = samples[int(len(samples) * 0.95) - 1]
    print(f"PASS_S28_P0_VISUAL_ROUTING_SELFTEST={len(cases)}/{len(cases)}")
    print(f"BENCH_S28_P0_VISUAL_ROUTING_US median={median:.3f} p95={p95:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
