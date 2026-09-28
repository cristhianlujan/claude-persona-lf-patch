#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from lf_contract_check_resolution_handoff_v1 import (
    ContractCheckHandoffError,
    build_resolution_request,
)

MANIFEST = "sandbox/lf_contract_gate_test/changesets/SOL-CC-1.json"
TARGET = "custom/contract_surface.py"


class Lane:
    def __init__(self, *, mode="DEEP_SHARED_KNOWN", reasons=()):
        self.mode = mode
        self.reasons = tuple(reasons)


def plan(*, applicable=True, changed=None):
    changed = sorted(changed or [MANIFEST, TARGET])
    controls = ["LF_CONTRACT_CORE"] if applicable else ["CI_ROUTER_SELFTEST"]
    reasons = {"LF_CONTRACT_CORE": [f"PATH:{TARGET}"]} if applicable else {"CI_ROUTER_SELFTEST": [f"PATH:{TARGET}"]}
    return {
        "schema_version": "lf-ci-execution-plan/v2",
        "plan_sha256": "a" * 64,
        "changed_paths": changed,
        "required_controls": controls,
        "required_control_reasons": reasons,
    }


def write_manifest(root: Path, *, solution_ref="SOL-CC-1") -> None:
    target = root / MANIFEST
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(
            {
                "solution_ref": solution_ref,
                "paths": {TARGET: "CUSTOM"},
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )


def expect_error(code: str, fn) -> None:
    try:
        fn()
    except ContractCheckHandoffError as exc:
        assert str(exc).startswith(code), (str(exc), code)
    else:
        raise AssertionError(code)


def main() -> None:
    checks = 0
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        write_manifest(root)
        lane = Lane(
            reasons=(
                f"CHANGE_FAMILY:CHANGESET_MANIFEST:{MANIFEST}",
                f"CHANGE_FAMILY:CUSTOM:{TARGET}",
            )
        )
        request = build_resolution_request(lane=lane, plan=plan(), repo_root=root)
        assert request["applicability"] == "APPLICABLE"
        assert request["handoff_state"] == "READY_FOR_OPERATION_CONTEXT_BINDING"
        assert request["changeset"]["solution_ref"] == "SOL-CC-1"
        assert request["changeset"]["families"] == {MANIFEST: "CHANGESET_MANIFEST", TARGET: "CUSTOM"}
        checks += 4

        assert request["resolution_request"] == {
            "owner": "CONTRACT_RESOLUTION",
            "required": True,
            "invocation_ready": False,
            "selection_performed": False,
            "operation_code_source": "CALLER_OPERATION_CONTEXT",
            "required_inputs": ["operation_code", "authority_contracts"],
            "required_outputs": ["resolved_contracts"],
        }
        assert request["contract_check_boundary"]["owner"] == "CONTRACT_CHECK"
        assert request["contract_check_boundary"]["contract_selection_allowed"] is False
        assert request["contract_check_boundary"]["upstream_term_verdicts_allowed"] is False
        checks += 4

        request2 = build_resolution_request(lane=lane, plan=plan(), repo_root=root)
        assert request2["request_sha256"] == request["request_sha256"]
        assert len(request["request_sha256"]) == 64
        checks += 2

        no_manifest_lane = Lane(reasons=(f"CHANGE_FAMILY:CUSTOM:{TARGET}",))
        pending = build_resolution_request(
            lane=no_manifest_lane,
            plan=plan(changed=[TARGET]),
            repo_root=root,
        )
        assert pending["handoff_state"] == "IDENTITY_PENDING_REPORT_ONLY"
        assert pending["changeset"]["solution_ref"] is None
        checks += 2

        classification_pending = build_resolution_request(
            lane=Lane(mode="CLASSIFICATION_REQUIRED", reasons=()),
            plan=plan(changed=[TARGET]),
            repo_root=root,
        )
        assert classification_pending["handoff_state"] == "CLASSIFICATION_PENDING_REPORT_ONLY"
        checks += 1

        na = build_resolution_request(
            lane=no_manifest_lane,
            plan=plan(applicable=False, changed=[TARGET]),
            repo_root=root,
        )
        assert na["handoff_state"] == "NOT_APPLICABLE"
        assert na["resolution_request"]["required"] is False
        checks += 2

        conflict_lane = Lane(
            reasons=(
                f"CHANGE_FAMILY:CUSTOM:{TARGET}",
                f"CHANGE_FAMILY:OTHER:{TARGET}",
            )
        )
        expect_error(
            "FAIL_CONTRACT_CHECK_HANDOFF_FAMILY_CONFLICT",
            lambda: build_resolution_request(
                lane=conflict_lane,
                plan=plan(changed=[TARGET]),
                repo_root=root,
            ),
        )
        checks += 1

        missing_manifest_root = root / "missing"
        missing_manifest_lane = Lane(
            reasons=(f"CHANGE_FAMILY:CHANGESET_MANIFEST:{MANIFEST}",)
        )
        expect_error(
            "FAIL_CONTRACT_CHECK_HANDOFF_MANIFEST_MISSING",
            lambda: build_resolution_request(
                lane=missing_manifest_lane,
                plan=plan(changed=[MANIFEST]),
                repo_root=missing_manifest_root,
            ),
        )
        checks += 1

        assert "operation_code" not in request
        assert "resolved_contracts" not in request
        assert "evaluations" not in request
        checks += 3

    assert checks == 20, checks
    print("PASS_CONTRACT_CHECK_RESOLUTION_HANDOFF_V1=20/20")


if __name__ == "__main__":
    main()
