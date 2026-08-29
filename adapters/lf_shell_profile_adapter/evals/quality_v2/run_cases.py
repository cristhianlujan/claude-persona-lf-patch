#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "validators" / "validate_adapter_package.py"
spec = importlib.util.spec_from_file_location("validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

H64 = "a" * 64
C64 = "b" * 64

VALID = {
    "state": "BOUND",
    "shell_binding": {
        "profile_id": "PERFIL-UI-ARCHITECT",
        "screen_code": "CHECKOUT",
        "canonical_refs": ["lf_ops.pantallas:CHECKOUT", "lf_ops.app_shells:CLIENT_APP_SHELL"],
        "protected_targets": ["global_header", "global_footer"],
        "writable_targets": ["payment_summary"],
        "normalized_delta": {"remove": ["top_amount_strip"]},
        "precision_basis": "UPSTREAM_VALUE",
        "blockers": [],
        "handoff": "UI_ARCHITECT"
    },
    "lf_adapter_invocations": [{
        "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
        "adapter_version": "v0.2-candidate",
        "invocation_id": "inv-000001",
        "activation_reason": "LF screen remediation bound to UI profile",
        "source_sha256": H64,
        "capsule_sha256": C64,
        "verdict": "APPLIED"
    }]
}


def expect_pass(name, doc):
    validator.validate_result(doc)
    print(f"PASS expected-pass {name}")


def expect_fail(name, doc):
    try:
        validator.validate_result(doc)
    except ValueError:
        print(f"PASS expected-fail {name}")
        return
    raise AssertionError(f"case should fail: {name}")


def main():
    expect_pass("bound_valid", VALID)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"] = []
    expect_fail("missing_invocation_receipt", x)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"].append(deepcopy(x["lf_adapter_invocations"][0]))
    expect_fail("duplicate_invocation", x)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"][0]["adapter_code"] = "OTHER_ADAPTER"
    expect_fail("wrong_adapter_identity", x)

    x = deepcopy(VALID)
    x["shell_binding"]["protected_targets"].append("payment_summary")
    expect_fail("protected_writable_overlap", x)

    x = deepcopy(VALID)
    x["state"] = "RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED"
    x["shell_binding"]["blockers"] = ["requested target is SHELL_LOCKED"]
    x["lf_adapter_invocations"][0]["verdict"] = "BLOCKED"
    expect_pass("shell_locked_return", x)

    x = deepcopy(VALID)
    x["state"] = "BLOCKED_SOURCE_CONFLICT"
    expect_fail("blocked_without_blocker_evidence", x)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"][0]["source_sha256"] = "not-a-hash"
    expect_fail("invalid_source_hash", x)

    print("QUALITY_V2_PASS")


if __name__ == "__main__":
    main()
