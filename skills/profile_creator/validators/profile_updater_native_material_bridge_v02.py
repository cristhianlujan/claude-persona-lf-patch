"""C5/C6: verify material authored in the *existing* native chat before admission.

This is NOT a provider attestation or qualification of external method engines.
A host-owned resolver, not the LLM's output, supplies the independent review.
Only pre-admission candidate evidence is returned; no operation step is written.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Callable

SHA256 = re.compile(r"^[0-9a-f]{64}$")
SURFACES = {"GPT_NATIVE": "CHATGPT_CURRENT_CONVERSATION",
            "CLAUDE_NATIVE": "CLAUDE_CURRENT_CONVERSATION"}


class MaterialBridgeBlocked(ValueError):
    pass


def _sha(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
        separators=(",", ":")).encode("utf-8")).hexdigest()


def _check(ok: bool, code: str) -> None:
    if not ok:
        raise MaterialBridgeBlocked(code)


def verify_native_material_candidate(*, handoff: dict[str, Any],
                                     capture: dict[str, Any],
                                     expected_current_surface: str,
                                     trusted_source_readback: Callable[[str], bytes | None],
                                     trusted_review_readback: Callable[[str], dict[str, Any] | None],
                                     review_receipt_id: str) -> dict[str, Any]:
    """Join frozen handoff, source HEAD, raw material and independent review.

    Both callbacks must be implemented by a trusted host using current authority
    reads. They are never fed by the generated answer or its declared metadata.
    """
    _check(isinstance(handoff, dict) and isinstance(capture, dict), "MATERIAL_ENVELOPE_INVALID")
    _check(handoff.get("schema") == "LF_PE10_V02_SAME_CHAT_NATIVE_HANDOFF_V1"
           and capture.get("schema") == "LF_PE10_V02_SAME_CHAT_RAW_CAPTURE_V1",
           "MATERIAL_SCHEMA_MISMATCH")
    _check(handoff.get("handoff_sha256") == _sha({k: v for k, v in handoff.items()
                if k != "handoff_sha256"}), "HANDOFF_DIGEST_INVALID")
    _check(capture.get("capture_sha256") == _sha({k: v for k, v in capture.items()
                if k != "capture_sha256"}), "CAPTURE_DIGEST_INVALID")
    raw = capture.get("raw_output")
    _check(isinstance(raw, dict) and capture.get("raw_output_sha256") == _sha(raw),
           "RAW_DIGEST_INVALID")
    mode = handoff.get("executor_mode")
    _check(mode in SURFACES and expected_current_surface == SURFACES[mode]
           and handoff.get("current_chat_surface") == expected_current_surface
           and capture.get("executor_mode") == mode
           and handoff.get("conversation_scope") == "EXISTING_CONVERSATION_ONLY"
           and capture.get("conversation_scope") == "EXISTING_CONVERSATION_ONLY"
           and handoff.get("session_creation") is False
           and handoff.get("api_invocation") is False,
           "NATIVE_CHAT_CONTEXT_INVALID")
    _check(capture.get("handoff_sha256") == handoff["handoff_sha256"]
           and capture.get("run_id") == handoff.get("run_id")
           and raw.get("run_id") == handoff.get("run_id")
           and raw.get("evolution_mode") == handoff.get("evolution_mode"),
           "EXECUTION_BINDING_MISMATCH")
    selected = handoff.get("selected_method_ids")
    _check(isinstance(selected, list) and all(isinstance(m, str) and m for m in selected)
           and len(selected) == len(set(selected))
           and raw.get("methods_applied") == selected
           and isinstance(raw.get("deliverable"), dict) and bool(raw["deliverable"]),
           "MATERIAL_METHOD_OR_CONTENT_MISMATCH")
    _check(capture.get("runtime_provider_attested") is False
           and capture.get("method_execution_certified") is False
           and capture.get("cutover_eligible") is False
           and capture.get("production_activated") is False
           and handoff.get("cutover_eligible") is False,
           "FORGED_EXECUTION_AUTHORITY")
    manifest = handoff.get("source_manifest")
    _check(isinstance(manifest, list) and bool(manifest)
           and handoff.get("source_manifest_sha256") == _sha(manifest)
           and callable(trusted_source_readback), "SOURCE_PROVENANCE_INVALID")
    for item in manifest:
        _check(isinstance(item, dict) and isinstance(item.get("ref"), str)
               and isinstance(item.get("sha256"), str)
               and SHA256.fullmatch(item["sha256"]) is not None,
               "SOURCE_MANIFEST_ENTRY_INVALID")
        content = trusted_source_readback(item["ref"])
        _check(isinstance(content, bytes)
               and hashlib.sha256(content).hexdigest() == item["sha256"],
               "SOURCE_CURRENTNESS_UNVERIFIED")
    profile_slug = handoff.get("profile_slug")
    _check(isinstance(profile_slug, str) and bool(profile_slug.strip()),
           "PROFILE_SOURCE_UNBOUND")
    _check(any(x["ref"] == "profiles/" + profile_slug + "/SKILL.md"
               for x in manifest), "PROFILE_SOURCE_UNBOUND")
    _check(isinstance(review_receipt_id, str) and bool(review_receipt_id.strip())
           and callable(trusted_review_readback), "INDEPENDENT_REVIEW_MISSING")
    reviewed = trusted_review_readback(review_receipt_id)
    _check(isinstance(reviewed, dict)
           and reviewed.get("receipt_id") == review_receipt_id
           and reviewed.get("verification_state") == "VERIFIED"
           and reviewed.get("verdict") == "PASS"
           and reviewed.get("subject_raw_sha256") == capture["raw_output_sha256"]
           and reviewed.get("handoff_sha256") == handoff["handoff_sha256"]
           and reviewed.get("profile_slug") == handoff["profile_slug"]
           and reviewed.get("run_id") == handoff["run_id"]
           and reviewed.get("capture_sha256") == capture["capture_sha256"]
           and reviewed.get("source_manifest_sha256") == handoff["source_manifest_sha256"]
           and reviewed.get("reviewer_execution_id") != handoff["run_id"]
           and isinstance(reviewed.get("reviewer_execution_id"), str)
           and bool(reviewed["reviewer_execution_id"])
           and reviewed.get("positive_controls_passed") is True
           and reviewed.get("negative_controls_passed") is True,
           "INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED")
    return {
        "status": "NATIVE_MATERIAL_REVIEWED_PRE_ADMISSION",
        "run_id": handoff["run_id"],
        "profile_slug": handoff["profile_slug"],
        "native_executor_mode": mode,
        "raw_output_sha256": capture["raw_output_sha256"],
        "capture_sha256": capture["capture_sha256"],
        "handoff_sha256": handoff["handoff_sha256"],
        "independent_review_receipt_id": review_receipt_id,
        "techniques_authored_in_chat": selected,
        "external_method_execution_certified": False,
        "canonical_steps_recorded": False,
        "cutover_eligible": False,
        "production_activated": False,
    }
