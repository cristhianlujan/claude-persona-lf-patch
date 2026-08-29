#!/usr/bin/env python3
import hashlib
import json
import re
import sys
from pathlib import Path

HEX64 = re.compile(r"^[a-f0-9]{64}$")
ALLOWED_STATES = {
    "BOUND",
    "BOUND_CANDIDATE_ONLY",
    "RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY",
    "RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED",
    "BLOCKED_SOURCE_CONFLICT",
    "BLOCKED_SCREEN_UNRESOLVED",
}


def fail(message: str) -> None:
    raise ValueError(message)


def validate_invocation(inv: dict) -> None:
    required = {
        "adapter_code",
        "adapter_version",
        "invocation_id",
        "activation_reason",
        "source_sha256",
        "capsule_sha256",
        "verdict",
    }
    if set(inv) != required:
        fail("invocation keys mismatch")
    if inv["adapter_code"] != "ADAPTER_LF_SHELL_PROFILE":
        fail("wrong adapter_code")
    if not isinstance(inv["adapter_version"], str) or not inv["adapter_version"]:
        fail("missing adapter_version")
    if not isinstance(inv["invocation_id"], str) or len(inv["invocation_id"]) < 8:
        fail("invalid invocation_id")
    if not isinstance(inv["activation_reason"], str) or not inv["activation_reason"]:
        fail("missing activation_reason")
    if not HEX64.fullmatch(str(inv["source_sha256"])):
        fail("invalid source_sha256")
    if not HEX64.fullmatch(str(inv["capsule_sha256"])):
        fail("invalid capsule_sha256")
    if inv["verdict"] not in {"APPLIED", "BLOCKED"}:
        fail("invalid invocation verdict")


def validate_result(doc: dict) -> None:
    required = {"state", "shell_binding", "lf_adapter_invocations"}
    if set(doc) != required:
        fail("root keys mismatch")
    if doc["state"] not in ALLOWED_STATES:
        fail("invalid state")
    invocations = doc["lf_adapter_invocations"]
    if not isinstance(invocations, list) or len(invocations) != 1:
        fail("applicable shell adapter must have exactly one invocation receipt")
    validate_invocation(invocations[0])
    binding = doc["shell_binding"]
    if not isinstance(binding, dict):
        fail("shell_binding must be object")
    for key in ["profile_id", "screen_code", "canonical_refs", "protected_targets", "writable_targets", "normalized_delta", "precision_basis", "blockers", "handoff"]:
        if key not in binding:
            fail(f"missing shell_binding.{key}")
    if not isinstance(binding["canonical_refs"], list) or not binding["canonical_refs"]:
        fail("canonical_refs required")
    if set(binding["protected_targets"]) & set(binding["writable_targets"]):
        fail("protected and writable targets overlap")
    if doc["state"] in {"BOUND", "BOUND_CANDIDATE_ONLY"} and binding["blockers"]:
        fail("bound state cannot contain blockers")
    if doc["state"].startswith("BLOCKED") or doc["state"].startswith("RETURN_TO_ORCHESTRATOR"):
        if not binding["blockers"]:
            fail("blocked/return state requires blocker evidence")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_adapter_package.py RESULT.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        validate_result(doc)
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
