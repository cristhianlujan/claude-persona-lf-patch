#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

HEX64 = re.compile(r"^[a-f0-9]{64}$")
ALLOWED_STATES = {
    "BOUND",
    "BOUND_CANDIDATE_ONLY",
    "RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY",
    "BLOCKED_VISUAL_SOURCE_CONFLICT",
    "BLOCKED_TARGET_UNRESOLVED"
}


def fail(message: str) -> None:
    raise ValueError(message)


def validate_invocation(inv: dict) -> None:
    required = {
        "adapter_code", "adapter_version", "invocation_id", "activation_reason",
        "source_sha256", "capsule_sha256", "verdict"
    }
    if set(inv) != required:
        fail("invocation keys mismatch")
    if inv["adapter_code"] != "ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF":
        fail("wrong adapter_code")
    if not isinstance(inv["adapter_version"], str) or not inv["adapter_version"]:
        fail("missing adapter_version")
    if not isinstance(inv["invocation_id"], str) or len(inv["invocation_id"]) < 8:
        fail("invalid invocation_id")
    if not isinstance(inv["activation_reason"], str) or not inv["activation_reason"]:
        fail("missing activation_reason")
    if not HEX64.fullmatch(str(inv["source_sha256"])) or not HEX64.fullmatch(str(inv["capsule_sha256"])):
        fail("invalid source hash")
    if inv["verdict"] not in {"APPLIED", "BLOCKED"}:
        fail("invalid invocation verdict")


def validate_result(doc: dict) -> None:
    if set(doc) != {"state", "render_binding", "lf_adapter_invocations"}:
        fail("root keys mismatch")
    if doc["state"] not in ALLOWED_STATES:
        fail("invalid state")
    invocations = doc["lf_adapter_invocations"]
    if not isinstance(invocations, list) or len(invocations) != 1:
        fail("applicable brand adapter must have exactly one invocation receipt")
    validate_invocation(invocations[0])
    binding = doc["render_binding"]
    if not isinstance(binding, dict):
        fail("render_binding must be object")
    required = {
        "project_code", "output_target", "canonical_refs", "resolved_tokens",
        "screen_frame_policy", "mockup_template", "qa_checks", "blockers"
    }
    if set(binding) != required:
        fail("render_binding keys mismatch")
    if binding["output_target"] not in {"PDF", "PPTX", "HTML", "BRANDBOOK"}:
        fail("invalid output_target")
    if not isinstance(binding["canonical_refs"], list) or not binding["canonical_refs"]:
        fail("canonical_refs required")
    if not isinstance(binding["qa_checks"], list) or not binding["qa_checks"]:
        fail("qa_checks required")
    blocked = doc["state"].startswith("BLOCKED") or doc["state"].startswith("RETURN_TO_ORCHESTRATOR")
    if blocked and not binding["blockers"]:
        fail("blocked state requires blocker evidence")
    if not blocked and binding["blockers"]:
        fail("bound state cannot contain blockers")
    if not blocked and not binding["resolved_tokens"]:
        fail("bound render requires governed resolved_tokens")
    if not blocked and not binding["screen_frame_policy"]:
        fail("bound render requires screen_frame_policy")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_adapter_package.py RESULT.json", file=sys.stderr)
        return 2
    try:
        validate_result(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
