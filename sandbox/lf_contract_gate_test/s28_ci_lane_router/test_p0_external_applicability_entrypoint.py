#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_DIR = ROOT / "sandbox" / "lf_contract_gate_test"
sys.path.insert(0, str(CONTRACT_DIR))

import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as subject  # noqa: E402

S30 = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
P0_BROKER = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/index.ts"
UNKNOWN = "sandbox/lf_contract_gate_test/unbound_future_validator.py"


def exercise(paths: list[str], *, broker_rc: int, expected_calls: int, expected_exit: int | None) -> None:
    old_get_changed = subject.get_changed_files
    old_run = subject.subprocess.run
    old_event = os.environ.get("GITHUB_EVENT_NAME")
    old_ref = os.environ.get("GITHUB_REF")
    calls = []
    try:
        subject.get_changed_files = lambda: list(paths)

        def fake_run(*args, **kwargs):
            calls.append((args, kwargs))
            return SimpleNamespace(returncode=broker_rc)

        subject.subprocess.run = fake_run
        os.environ["GITHUB_EVENT_NAME"] = "push"
        os.environ["GITHUB_REF"] = "refs/heads/main"

        observed_exit = None
        try:
            subject._run_exact_head_real_source_if_required()
        except SystemExit as exc:
            observed_exit = int(exc.code) if isinstance(exc.code, int) else 1

        assert len(calls) == expected_calls, (paths, len(calls), expected_calls)
        assert observed_exit == expected_exit, (paths, observed_exit, expected_exit)
    finally:
        subject.get_changed_files = old_get_changed
        subject.subprocess.run = old_run
        if old_event is None:
            os.environ.pop("GITHUB_EVENT_NAME", None)
        else:
            os.environ["GITHUB_EVENT_NAME"] = old_event
        if old_ref is None:
            os.environ.pop("GITHUB_REF", None)
        else:
            os.environ["GITHUB_REF"] = old_ref


def main() -> None:
    # Unrelated S30 changes must not call the quota-bound external broker.
    exercise([S30], broker_rc=9, expected_calls=0, expected_exit=None)
    # Broker-owned changes still require the live probe.
    exercise([P0_BROKER], broker_rc=0, expected_calls=1, expected_exit=None)
    # A live broker failure remains fail-closed when the broker is required.
    exercise([P0_BROKER], broker_rc=7, expected_calls=1, expected_exit=7)
    # Unknown ownership also remains fail-closed and requires the live broker.
    exercise([UNKNOWN], broker_rc=8, expected_calls=1, expected_exit=8)
    print("PASS_P0_EXTERNAL_APPLICABILITY_ENTRYPOINT=4/4")


if __name__ == "__main__":
    main()
