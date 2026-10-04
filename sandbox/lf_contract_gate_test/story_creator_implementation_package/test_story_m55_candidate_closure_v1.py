#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLOSURE_PATH = HERE / "story_m55_candidate_closure_v1.json"
BINDING_PATH = HERE / "programming_agent_story_consumer_binding_v1.json"
PACKAGE_PATH = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"
JUDGE_PATH = HERE / "programming_utility_judge_contract_v1.json"

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_REPO = "cristhianlujan/libertad-financiera"
EXPECTED_ROUTE = "/onboarding/completar-datos"
EXPECTED_TYPED_BLOCKERS = {
    "ONB004_EMAIL_REQUIREMENT_CONFLICT",
    "ONB004_LEGAL_ROUTES_PENDING",
}


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("utf-8")
    return hashlib.sha1(header + data).hexdigest()


def validate() -> list[str]:
    closure = json.loads(CLOSURE_PATH.read_text(encoding="utf-8"))
    binding = json.loads(BINDING_PATH.read_text(encoding="utf-8"))
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))
    judge_bytes = JUDGE_PATH.read_bytes()
    judge = json.loads(judge_bytes.decode("utf-8"))
    errors: list[str] = []

    if closure.get("schema_version") != "STORY_M55_CANDIDATE_CLOSURE_V1":
        errors.append("M55_SCHEMA_INVALID")
    if closure.get("unit_code") != "SC-M5.5" or closure.get("work_code") != "SC-IMP-029":
        errors.append("M55_IDENTITY_INVALID")
    if closure.get("owner_scope") != "SUPER_ADMIN":
        errors.append("OWNER_SCOPE_NOT_SUPER_ADMIN")

    terminal = closure.get("closure", {})
    if terminal.get("candidate_state") != "CANDIDATE_CLOSED_PENDING_ACTIVATION":
        errors.append("CANDIDATE_TERMINAL_STATE_INVALID")
    if terminal.get("ready") is not False:
        errors.append("FALSE_READY_TERMINAL_STATE")
    if terminal.get("implementation_readiness") != "BLOCKED_BY_TYPED_SOURCE_ITEMS":
        errors.append("TYPED_SOURCE_BLOCKERS_NOT_RETAINED")
    if terminal.get("terminal_state_coherent") is not True:
        errors.append("TERMINAL_STATE_NOT_COHERENT")
    if terminal.get("pending_activation_explicit") is not True:
        errors.append("PENDING_ACTIVATION_NOT_EXPLICIT")

    activation = closure.get("activation_guard", {})
    forbidden_true = [
        "runtime_activation_performed",
        "production_activation_performed",
        "promotion_performed",
        "deploy_performed",
    ]
    for key in forbidden_true:
        if activation.get(key) is not False:
            errors.append(f"FORBIDDEN_ACTIVATION_EFFECT:{key}")
    if activation.get("future_activation_requires_separate_authority") is not True:
        errors.append("FUTURE_ACTIVATION_AUTHORITY_GUARD_MISSING")

    capability = closure.get("capability_first", {})
    if capability.get("final_evidence") != "REUSE_AS_IS" or capability.get("authority_readback") != "REUSE_AS_IS":
        errors.append("TRANSVERSAL_EVIDENCE_CAPABILITY_NOT_REUSED")
    if capability.get("programming_target_binding") != "DOMAIN_SPECIALIZATION":
        errors.append("TARGET_BINDING_CLASSIFICATION_INVALID")
    for key in (
        "new_transversal_engine_created",
        "new_programming_runtime_created",
        "new_task_store_created",
        "new_context_store_created",
    ):
        if capability.get(key) is not False:
            errors.append(f"PARALLEL_ENGINE_OR_STORE_CREATED:{key}")

    currentness = closure.get("governed_judge_currentness", {})
    actual_judge_blob = git_blob_sha(judge_bytes)
    if currentness.get("m44_evidence_blob_sha") != actual_judge_blob:
        errors.append("M44_JUDGE_BLOB_NOT_CURRENT")
    if currentness.get("m55_readback_blob_sha") != actual_judge_blob:
        errors.append("M55_JUDGE_READBACK_BLOB_MISMATCH")
    if currentness.get("currentness_result") != "CURRENT_UNCHANGED":
        errors.append("JUDGE_CURRENTNESS_NOT_PROVEN")
    if judge.get("governance", {}).get("validation_model") != "GOVERNED_SINGLE_JUDGE":
        errors.append("GOVERNED_SINGLE_JUDGE_DRIFT")
    if judge.get("governance", {}).get("second_semantic_review_required") is not False:
        errors.append("DUPLICATE_SEMANTIC_REVIEW_REINTRODUCED")

    target = closure.get("programming_target_binding", {})
    required_fields = set(binding.get("implementation_target_binding", {}).get("required_fields", []))
    missing = sorted(k for k in required_fields if not target.get(k))
    if missing:
        errors.append("TARGET_BINDING_REQUIRED_FIELDS_MISSING:" + ",".join(missing))
    if target.get("status") != "RESOLVED_CANDIDATE_BINDING":
        errors.append("PROGRAMMING_TARGET_NOT_RESOLVED")
    if target.get("binding_origin") != "SC-M5.5_SUPER_ADMIN_DOMAIN_SPECIALIZATION":
        errors.append("TARGET_BINDING_ORIGIN_INVALID")
    if target.get("preexisting_binding") is not False or target.get("silent_inference_used") is not False:
        errors.append("TARGET_BINDING_FALSE_PREEXISTENCE_OR_INFERENCE")
    if target.get("repo_full_name") != EXPECTED_REPO:
        errors.append("TARGET_REPO_DRIFT")
    if not HEX40.match(str(target.get("base_head_sha", ""))):
        errors.append("TARGET_HEAD_INVALID")
    if not HEX64.match(str(target.get("source_snapshot_sha256", ""))):
        errors.append("SOURCE_SNAPSHOT_INVALID")
    if target.get("source_snapshot_sha256") != package.get("canonical_story_sha256"):
        errors.append("SOURCE_SNAPSHOT_NOT_CANONICAL_STORY")
    if target.get("route_authority", {}).get("route_pattern") != EXPECTED_ROUTE:
        errors.append("TARGET_ROUTE_AUTHORITY_DRIFT")
    if target.get("route_authority", {}).get("screen_code") != "ONB_004":
        errors.append("TARGET_SCREEN_AUTHORITY_DRIFT")
    if target.get("target_repo_write_performed_by_this_unit") is not False:
        errors.append("M55_WROTE_TARGET_REPO")

    write_paths = target.get("write_path_patterns", [])
    if not write_paths or any(p in {"*", "**", "src/**"} for p in write_paths):
        errors.append("WRITE_SCOPE_NOT_BOUNDED")
    if "src/app/onboarding/completar-datos/**" not in write_paths:
        errors.append("CANONICAL_ROUTE_WRITE_SCOPE_MISSING")
    protected = set(target.get("protected_path_patterns", []))
    if "src/lib/auth/**" not in protected or ".github/**" not in protected:
        errors.append("PROTECTED_SCOPE_INCOMPLETE")

    retained = {x.get("code") for x in closure.get("retained_typed_source_items", [])}
    if retained != EXPECTED_TYPED_BLOCKERS:
        errors.append("RETAINED_TYPED_BLOCKERS_DRIFT")
    package_blockers = {x.get("code") for x in package.get("blocked_if", [])}
    if not EXPECTED_TYPED_BLOCKERS.issubset(package_blockers):
        errors.append("LEGACY_CARRIER_TYPED_BLOCKERS_MISSING")
    if package.get("decision_closure", {}).get("ready") is not False:
        errors.append("LEGACY_CARRIER_FALSE_READY")

    resolved = closure.get("resolved_candidate_item", {})
    if resolved.get("code") != "PROGRAMMING_TARGET_SCOPE_UNRESOLVED":
        errors.append("TARGET_BLOCKER_RESOLUTION_IDENTITY_INVALID")
    if resolved.get("candidate_state") != "RESOLVED_BY_GOVERNED_TARGET_BINDING":
        errors.append("TARGET_BLOCKER_NOT_RESOLVED_BY_BINDING")
    if resolved.get("does_not_override_other_typed_blockers") is not True:
        errors.append("TARGET_BINDING_OVERRIDES_OTHER_BLOCKERS")

    return errors


def main() -> int:
    errors = validate()
    out = {
        "schema": "SC_M5_5_CANDIDATE_CLOSURE_SELF_TEST_V1",
        "result": "PASS" if not errors else "FAIL",
        "errors": errors,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
