#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path
from typing import Any

VERSION = "UI_PRODUCTION_SPEC_V6"
ENVELOPE_SCHEMA = "LF_UI_GOVERNANCE_ENVELOPE_V1"

COMPOSER_TOP_LEVEL_ALLOWLIST = [
    "screen_definition",
    "component_tree",
    "layout_grid",
    "visual_hierarchy",
    "state_map",
    "token_map",
    "spacing_typography",
    "density_rules",
    "risk_controls",
    "remediation_actions",
]

FORBIDDEN_KEYS = {
    "governance_context",
    "governance_envelope",
    "source_refs",
    "execution_id",
    "execution_contract_sha256",
    "prebound_commit_sha",
    "artifact_sha256",
    "receipt_sha256",
    "binding_sha256",
    "score",
    "self_verdict",
    "routing",
    "worker",
    "evidence_map",
}

FORBIDDEN_VALUE_FRAGMENTS = (
    "github://",
    "sandbox/lf_contract_gate_test",
    "supabase://",
    "PASS_TO_COMPOSER",
    "PASS_TO_QUALITY_PACK",
    "INDEPENDENT_CHAT_CONTEXT",
)


def _fail(code: str, detail: str, errors: list[dict[str, str]]) -> None:
    errors.append({"code": code, "detail": detail})


def _strip_action_internal_refs(action: Any) -> Any:
    if not isinstance(action, dict):
        return copy.deepcopy(action)
    out = copy.deepcopy(action)
    for key in ("semantic_authority", "precision_basis"):
        block = out.get(key)
        if isinstance(block, dict):
            block.pop("source_refs", None)
    return out


def build_composer_payload(deliverable: Any) -> dict[str, Any]:
    if not isinstance(deliverable, dict):
        return {}
    projected: dict[str, Any] = {}
    for key in COMPOSER_TOP_LEVEL_ALLOWLIST:
        if key not in deliverable:
            continue
        value = deliverable[key]
        if key == "screen_definition" and isinstance(value, dict):
            value = copy.deepcopy(value)
            value.pop("artifact_sha256", None)
        elif key == "remediation_actions" and isinstance(value, list):
            value = [_strip_action_internal_refs(item) for item in value]
        else:
            value = copy.deepcopy(value)
        projected[key] = value
    return projected


def _scan_forbidden(value: Any, path: str, errors: list[dict[str, str]]) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            key_text = str(key)
            child = f"{path}.{key_text}" if path else key_text
            if key_text in FORBIDDEN_KEYS or key_text.endswith("_sha256"):
                _fail("COMPOSER_INTERNAL_KEY_LEAK", child, errors)
            _scan_forbidden(item, child, errors)
    elif isinstance(value, list):
        for idx, item in enumerate(value):
            _scan_forbidden(item, f"{path}[{idx}]", errors)
    elif isinstance(value, str):
        for fragment in FORBIDDEN_VALUE_FRAGMENTS:
            if fragment in value:
                _fail("COMPOSER_INTERNAL_VALUE_LEAK", f"{path}: contains {fragment}", errors)


def validate(data: Any) -> list[dict[str, str]]:
    errors: list[dict[str, str]] = []
    if not isinstance(data, dict):
        return [{"code": "ROOT_NOT_OBJECT", "detail": "root must be object"}]

    if data.get("output_contract_version") != VERSION:
        _fail("COMPOSER_BOUNDARY_VERSION_INVALID", f"expected {VERSION}", errors)

    envelope = data.get("governance_envelope")
    if not isinstance(envelope, dict):
        _fail("GOVERNANCE_ENVELOPE_MISSING", "governance_envelope object required", errors)
    else:
        if envelope.get("schema") != ENVELOPE_SCHEMA:
            _fail("GOVERNANCE_ENVELOPE_SCHEMA_INVALID", str(envelope.get("schema")), errors)
        if envelope.get("render_policy") != "NON_RENDER":
            _fail("GOVERNANCE_ENVELOPE_RENDER_POLICY_INVALID", str(envelope.get("render_policy")), errors)
        if not isinstance(envelope.get("context"), dict) or not envelope.get("context"):
            _fail("GOVERNANCE_ENVELOPE_CONTEXT_MISSING", "context object required", errors)

    deliverable = data.get("deliverable_created")
    if not isinstance(deliverable, dict):
        _fail("DELIVERABLE_NOT_OBJECT", "deliverable_created object required", errors)
        return errors
    if "governance_context" in deliverable:
        _fail("DELIVERABLE_GOVERNANCE_CONTEXT_FORBIDDEN_V6", "move governance_context to root governance_envelope.context", errors)

    expected = build_composer_payload(deliverable)
    composer = data.get("composer_payload")
    if not isinstance(composer, dict):
        _fail("COMPOSER_PAYLOAD_MISSING", "composer_payload object required", errors)
    else:
        if composer != expected:
            _fail("COMPOSER_PAYLOAD_PROJECTION_MISMATCH", "composer_payload must equal deterministic projection of deliverable_created", errors)
        _scan_forbidden(composer, "composer_payload", errors)

    handoff = data.get("handoff_to_next")
    if not isinstance(handoff, dict) or handoff.get("payload_ref") != "composer_payload":
        _fail("COMPOSER_HANDOFF_PAYLOAD_REF_INVALID", "handoff_to_next.payload_ref must equal composer_payload", errors)

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"valid": False, "errors": [{"code": "USAGE", "detail": "validate_composer_payload_boundary.py <json>"}]}))
        return 2
    try:
        data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except Exception as exc:
        print(json.dumps({"valid": False, "errors": [{"code": "INPUT_PARSE_ERROR", "detail": str(exc)}]}, ensure_ascii=False, indent=2))
        return 1
    errors = validate(data)
    print(json.dumps({"valid": not errors, "errors": errors}, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
