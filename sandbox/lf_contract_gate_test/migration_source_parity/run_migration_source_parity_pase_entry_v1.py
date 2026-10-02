#!/usr/bin/env python3
"""PASE entry adapter for context-aware MIGRATION_SOURCE_PARITY.

This adapter does not implement parity. It preserves the focal capability runner
and only supplies event-correct exact-context currentness semantics:
- pull_request: live base ref must still equal base_sha;
- push: live base ref must already equal head_sha;
- workflow_dispatch: live base ref must equal base_sha.

Both paths still require exact checkout head and base->head ancestry.
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
FOCAL_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_focal_v1.py"
_ALLOWED_EVENTS = {"pull_request", "push", "workflow_dispatch"}


def _load_focal():
    spec = importlib.util.spec_from_file_location("lf_migration_source_parity_focal_pase_entry", FOCAL_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_PASE_ENTRY_FOCAL_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


FOCAL = _load_focal()


def _expected_live_ref_sha(event_name: str, base_sha: str, head_sha: str) -> str:
    event_name = event_name.strip()
    if event_name not in _ALLOWED_EVENTS:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_PASE_ENTRY_EVENT:{event_name!r}")
    return head_sha if event_name == "push" else base_sha


def _verify_exact_context_event_aware(
    base_sha: str,
    head_sha: str,
    base_ref: str,
    event_name: str,
) -> None:
    git = FOCAL.FULL._git
    git("fetch", "--no-tags", "origin", base_sha, head_sha)
    actual_head = git("rev-parse", "HEAD").stdout.strip().lower()
    if actual_head != head_sha:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_EXACT_HEAD expected={head_sha} actual={actual_head}"
        )

    git(
        "fetch",
        "--no-tags",
        "origin",
        f"+refs/heads/{base_ref}:refs/remotes/origin/{base_ref}",
    )
    live_ref = git("rev-parse", f"refs/remotes/origin/{base_ref}").stdout.strip().lower()
    expected_live = _expected_live_ref_sha(event_name, base_sha, head_sha)
    if live_ref != expected_live:
        raise RuntimeError(
            "FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS "
            f"event={event_name} ref={base_ref} expected={expected_live} live={live_ref}"
        )

    merge_base = git("merge-base", base_sha, head_sha).stdout.strip().lower()
    if merge_base != base_sha:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_BASE_NOT_ANCESTOR base={base_sha} merge_base={merge_base}"
        )


def _event_from_argv(argv: list[str]) -> str:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--event-name", required=True)
    args, _unknown = parser.parse_known_args(argv[1:])
    if args.event_name not in _ALLOWED_EVENTS:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_PASE_ENTRY_EVENT:{args.event_name!r}")
    return args.event_name


def self_test() -> int:
    base = "a" * 40
    head = "b" * 40
    checks = 0
    if _expected_live_ref_sha("pull_request", base, head) != base:
        raise RuntimeError("FAIL_MIGRATION_PARITY_PASE_ENTRY_SELFTEST_PR")
    checks += 1
    if _expected_live_ref_sha("push", base, head) != head:
        raise RuntimeError("FAIL_MIGRATION_PARITY_PASE_ENTRY_SELFTEST_PUSH")
    checks += 1
    if _expected_live_ref_sha("workflow_dispatch", base, head) != base:
        raise RuntimeError("FAIL_MIGRATION_PARITY_PASE_ENTRY_SELFTEST_DISPATCH")
    checks += 1
    try:
        _expected_live_ref_sha("schedule", base, head)
    except RuntimeError as exc:
        if not str(exc).startswith("FAIL_MIGRATION_PARITY_PASE_ENTRY_EVENT"):
            raise
    else:
        raise RuntimeError("FAIL_MIGRATION_PARITY_PASE_ENTRY_SELFTEST_UNKNOWN_EVENT")
    checks += 1
    print(f"PASS_MIGRATION_SOURCE_PARITY_PASE_ENTRY_SELFTEST={checks}/4")
    return 0


def main() -> int:
    if "--self-test-pase-entry" in sys.argv:
        return self_test()

    event_name = _event_from_argv(sys.argv)

    # The focal runner calls FULL._verify_exact_context(base, head, ref).
    # Bind that seam to event-aware currentness without duplicating parity logic.
    FOCAL.FULL._verify_exact_context = (
        lambda base_sha, head_sha, base_ref: _verify_exact_context_event_aware(
            base_sha, head_sha, base_ref, event_name
        )
    )
    return FOCAL.main()


if __name__ == "__main__":
    raise SystemExit(main())
