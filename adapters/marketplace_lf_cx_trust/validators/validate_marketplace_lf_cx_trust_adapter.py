#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ADAPTER_CODE = "ADAPTER_MARKETPLACE_LF_CX_TRUST"
PROFILE_CODE = "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531"
CAPSULE_REF = "adapters/marketplace_lf_cx_trust/runtime/runtime_capsule.yaml"
MAX_CAPSULE_CHARS = 1600
STATES = {
    "BOUND", "BOUND_CANDIDATE_ONLY", "RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY",
    "BLOCKED_SOURCE_CONFLICT", "BLOCKED_TARGET_UNRESOLVED",
}


def fail(code: str) -> None:
    raise ValueError(code)


def _scalar(text: str, key: str) -> str | None:
    prefix = f"{key}:"
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith(prefix):
            value = line[len(prefix):].strip().strip("'\"")
            return value or None
    return None


def validate_package(root: Path = ROOT) -> None:
    required = [
        "ADAPTER.md", "manifest.yaml", "runtime/runtime_capsule.yaml",
        "schemas/lf_adapter_invocation.schema.json", "schemas/marketplace_cx_trust_binding.schema.json",
        "validators/validate_marketplace_lf_cx_trust_adapter.py", "evals/run_cases.py",
        "judges/judge_marketplace_lf_cx_trust_adapter.yaml",
    ]
    for rel in required:
        if not (root / rel).is_file():
            fail(f"PACKAGE_FILE_MISSING:{rel}")
    manifest = (root / "manifest.yaml").read_text(encoding="utf-8")
    for literal in (
        "assurance_revision: v2", "invocation_policy: ROUTER_BOUND_ONLY",
        "separate_llm_call: FORBIDDEN", "runtime_enabled: false",
        f"binds_profile: {PROFILE_CODE}",
    ):
        if literal not in manifest:
            fail(f"MANIFEST_INVARIANT_MISSING:{literal}")
    capsule_path = root / "runtime/runtime_capsule.yaml"
    capsule = capsule_path.read_text(encoding="utf-8")
    if not capsule or len(capsule) > MAX_CAPSULE_CHARS:
        fail("CAPSULE_BUDGET_INVALID")
    if _scalar(capsule, "adapter") != ADAPTER_CODE:
        fail("CAPSULE_ADAPTER_ID_MISMATCH")
    if _scalar(capsule, "assurance_revision") != "v2":
        fail("CAPSULE_ASSURANCE_REVISION_INVALID")
    if _scalar(capsule, "activation") != "ROUTER_BOUND_ONLY":
        fail("CAPSULE_ACTIVATION_INVALID")
    for rel in ("schemas/lf_adapter_invocation.schema.json", "schemas/marketplace_cx_trust_binding.schema.json"):
        json.loads((root / rel).read_text(encoding="utf-8"))


def validate_invocation(invocation: Any) -> None:
    required = {
        "invocation_id", "adapter_code", "assurance_revision", "activation_source",
        "binding_ref", "profile_id", "target_ref", "capsule_ref", "capsule_char_count",
        "source_refs", "verdict",
    }
    if not isinstance(invocation, dict) or set(invocation) != required:
        fail("INVOCATION_SHAPE_INVALID")
    if invocation["adapter_code"] != ADAPTER_CODE or invocation["assurance_revision"] != "v2":
        fail("INVOCATION_IDENTITY_INVALID")
    if invocation["activation_source"] != "ROUTER":
        fail("BLOCK_UNBOUND_ADAPTER_INVOCATION")
    if invocation["profile_id"] != PROFILE_CODE or invocation["target_ref"] != PROFILE_CODE:
        fail("INVOCATION_TARGET_MISMATCH")
    if invocation["capsule_ref"] != CAPSULE_REF:
        fail("INVOCATION_CAPSULE_REF_INVALID")
    chars = invocation["capsule_char_count"]
    if not isinstance(chars, int) or chars < 1 or chars > MAX_CAPSULE_CHARS:
        fail("BLOCK_CONTEXT_BUDGET_EXCEEDED")
    refs = invocation["source_refs"]
    if not isinstance(refs, list) or not refs or len(refs) != len(set(refs)):
        fail("INVOCATION_SOURCE_REFS_INVALID")
    if invocation["verdict"] not in {"APPLIED", "BLOCKED"}:
        fail("INVOCATION_VERDICT_INVALID")


def validate_result(result: Any) -> None:
    if not isinstance(result, dict) or set(result) != {"state", "marketplace_cx_trust_binding", "lf_adapter_invocations"}:
        fail("RESULT_ROOT_INVALID")
    if result["state"] not in STATES:
        fail("RESULT_STATE_INVALID")
    invocations = result["lf_adapter_invocations"]
    if not isinstance(invocations, list) or len(invocations) != 1:
        fail("EXACTLY_ONE_INVOCATION_REQUIRED")
    validate_invocation(invocations[0])
    binding = result["marketplace_cx_trust_binding"]
    required = {
        "source_refs", "claim_boundaries", "trust_risks", "improvements",
        "protected_qualifiers", "support_dependencies", "blockers",
    }
    if not isinstance(binding, dict) or set(binding) != required:
        fail("BINDING_SHAPE_INVALID")
    if not isinstance(binding["source_refs"], list) or not binding["source_refs"]:
        fail("BINDING_SOURCE_REFS_REQUIRED")
    if not isinstance(binding["claim_boundaries"], list) or not binding["claim_boundaries"]:
        fail("CLAIM_BOUNDARIES_REQUIRED")
    if not isinstance(binding["protected_qualifiers"], list) or not binding["protected_qualifiers"]:
        fail("PROTECTED_QUALIFIERS_REQUIRED")
    blocked = result["state"].startswith("BLOCKED") or result["state"].startswith("RETURN_TO_ORCHESTRATOR")
    if blocked != bool(binding["blockers"]):
        fail("BLOCKER_STATE_INCONSISTENT")


def main() -> int:
    validate_package()
    if len(sys.argv) > 1:
        payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        validate_result(payload)
    print("MARKETPLACE_LF_CX_TRUST_ADAPTER_VALIDATOR_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
