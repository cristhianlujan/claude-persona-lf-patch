#!/usr/bin/env python3
"""Deterministic provenance + semantic-quality gate for governed LF profile execution."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from validate_semantic_judge import validate_semantic_judge_receipt

RECEIPT_TYPE = "PROFILE_EXECUTION_RECEIPT_V1"
OPERATION_CODE = "EJECUCION_PERFIL_LF"
ALLOWED_RUNTIME_ORIGINS = {"MODEL_RUNTIME"}
PROVENANCE_ONLY_RECIPIENTS = {"SEMANTIC_JUDGE"}
FINAL_DOWNSTREAM_RECIPIENTS = {"COMPOSER", "IMAGE_GENERATOR", "TOOL_PAYLOAD", "FINAL_USER", "INTERNAL_AGENT"}
DOWNSTREAM_RECIPIENTS = PROVENANCE_ONLY_RECIPIENTS | FINAL_DOWNSTREAM_RECIPIENTS
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_LF_ADAPTER_CAPSULE_CHARS = 2000
INPUT_GOVERNANCE_AGENT = "input-governance-agent-v1"
INPUT_GOVERNANCE_SECTIONS = {
    "APPLICABILITY_READINESS",
    "SOURCE_AUTHORITY_PROVENANCE",
    "FRESHNESS_INVALIDATION",
    "NEGATIVE_REQUIREMENTS",
    "CONFLICT_PRECEDENCE",
}


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def canonical_json_sha256(value: Any) -> str:
    rendered = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return sha256_text(rendered)


def _is_timezone_aware_iso8601(value: Any) -> bool:
    if not _nonempty_string(value):
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def validate_governance_receipt(receipt: Any) -> list[str]:
    """Validate the live PASS receipt consumed by a Router-bound adapter."""
    if not isinstance(receipt, dict):
        return ["INPUT_GOVERNANCE_RECEIPT_MISSING"]

    errors: list[str] = []
    required_strings = (
        "governance_agent", "governance_version", "snapshot_hash",
        "contract_snapshot_hash", "decision", "gap_or_na", "timestamp",
        "screen_code", "agent_output_sha256", "currentness",
    )
    for key in required_strings:
        if not _nonempty_string(receipt.get(key)):
            errors.append(f"INPUT_GOVERNANCE_{key.upper()}_MISSING")

    if receipt.get("governance_agent_used") is not True:
        errors.append("INPUT_GOVERNANCE_AGENT_NOT_USED")
    if receipt.get("governance_agent") != INPUT_GOVERNANCE_AGENT:
        errors.append("INPUT_GOVERNANCE_AGENT_INVALID")
    if receipt.get("decision") != "PASS":
        errors.append("INPUT_GOVERNANCE_DECISION_NOT_PASS")
    if receipt.get("currentness") != "LIVE_CURRENT":
        errors.append("INPUT_GOVERNANCE_RECEIPT_NOT_CURRENT")
    if receipt.get("gap_or_na") != "NONE":
        errors.append("INPUT_GOVERNANCE_GAP_PRESENT")
    if receipt.get("governance_version") == "N/A":
        errors.append("INPUT_GOVERNANCE_VERSION_INVALID")

    for key in ("snapshot_hash", "contract_snapshot_hash", "agent_output_sha256"):
        value = receipt.get(key)
        if _nonempty_string(value) and not _is_sha256(value):
            errors.append(f"INPUT_GOVERNANCE_{key.upper()}_INVALID")

    for key in ("timestamp", "run_created_at"):
        if not _is_timezone_aware_iso8601(receipt.get(key)):
            errors.append(f"INPUT_GOVERNANCE_{key.upper()}_INVALID")

    for key in ("run_id", "pantalla_id"):
        value = receipt.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            errors.append(f"INPUT_GOVERNANCE_{key.upper()}_INVALID")

    sections = receipt.get("sections_consumed")
    if (
        not isinstance(sections, list)
        or not sections
        or len(sections) != len(set(sections))
        or any(section not in INPUT_GOVERNANCE_SECTIONS for section in sections)
    ):
        errors.append("INPUT_GOVERNANCE_SECTIONS_INVALID")

    refs = receipt.get("source_refs")
    if (
        not isinstance(refs, list)
        or not refs
        or len(refs) != len(set(refs))
        or not all(_nonempty_string(ref) for ref in refs)
    ):
        errors.append("INPUT_GOVERNANCE_SOURCE_REFS_INVALID")
    elif isinstance(receipt.get("run_id"), int):
        expected_run_ref = f"programacion.input_readiness_runs/{receipt['run_id']}"
        if expected_run_ref not in refs:
            errors.append("INPUT_GOVERNANCE_RUN_SOURCE_REF_MISMATCH")

    return sorted(set(errors))


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_sha256(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value))


def _validate_lf_adapter_invocations(value: Any, profile_code: str | None) -> list[str]:
    if value is None:
        return []
    errors: list[str] = []
    if not isinstance(value, list):
        return ["LF_ADAPTER_INVOCATIONS_NOT_ARRAY"]
    seen: set[tuple[str, str]] = set()
    for index, item in enumerate(value):
        prefix = f"LF_ADAPTER_INVOCATION_{index}"
        if not isinstance(item, dict):
            errors.append(f"{prefix}_NOT_OBJECT")
            continue
        required = (
            "invocation_id", "adapter_code", "assurance_revision", "activation_source",
            "binding_ref", "profile_id", "target_ref", "capsule_ref", "capsule_char_count",
            "source_refs", "verdict",
        )
        for key in required:
            if key not in item:
                errors.append(f"{prefix}_{key.upper()}_MISSING")
        for key in (
            "invocation_id", "adapter_code", "assurance_revision", "activation_source",
            "binding_ref", "profile_id", "target_ref", "capsule_ref", "verdict",
        ):
            if key in item and not _nonempty_string(item.get(key)):
                errors.append(f"{prefix}_{key.upper()}_INVALID")
        if item.get("activation_source") != "ROUTER":
            errors.append(f"{prefix}_ACTIVATION_SOURCE_NOT_ROUTER")
        if item.get("verdict") not in {"APPLIED", "BLOCKED"}:
            errors.append(f"{prefix}_VERDICT_INVALID")
        if profile_code is not None and item.get("profile_id") != profile_code:
            errors.append(f"{prefix}_PROFILE_ID_MISMATCH")
        chars = item.get("capsule_char_count")
        if not isinstance(chars, int) or isinstance(chars, bool) or not 1 <= chars <= MAX_LF_ADAPTER_CAPSULE_CHARS:
            errors.append(f"{prefix}_CAPSULE_CHAR_COUNT_INVALID")
        refs = item.get("source_refs")
        if not isinstance(refs, list) or not refs or len(refs) > 8 or len(refs) != len(set(refs)) or not all(_nonempty_string(ref) for ref in refs):
            errors.append(f"{prefix}_SOURCE_REFS_INVALID")
        key = (str(item.get("adapter_code", "")), str(item.get("target_ref", "")))
        if key in seen:
            errors.append("LF_ADAPTER_INVOCATION_DUPLICATE_ADAPTER_TARGET")
        seen.add(key)
    return sorted(set(errors))


def build_receipt(
    *, execution_id: str, profile_code: str, profile_slug: str,
    profile_source_refs: list[str], profile_source_sha256: str,
    input_literal: str, raw_output: Any, runtime_attestation: dict[str, Any],
    obligation_manifest_sha256: str | None = None,
    lf_adapter_invocations: list[dict[str, Any]] | None = None,
    governance_receipt: dict[str, Any] | None = None,
    input_governance_required_adapters: list[str] | None = None,
) -> dict[str, Any]:
    receipt = {
        "receipt_type": RECEIPT_TYPE,
        "operation_code": OPERATION_CODE,
        "execution_id": execution_id,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "profile_source_refs": profile_source_refs,
        "profile_source_sha256": profile_source_sha256,
        "input_sha256": sha256_text(input_literal),
        "raw_output_sha256": canonical_json_sha256(raw_output),
        "raw_output_captured": True,
        "execution_origin": "MODEL_RUNTIME",
        "runtime_attestation": runtime_attestation,
        "downstream_authorized": False,
    }
    if obligation_manifest_sha256 is not None:
        receipt["obligation_manifest_sha256"] = obligation_manifest_sha256
    if lf_adapter_invocations:
        receipt["lf_adapter_invocations"] = lf_adapter_invocations
    if governance_receipt is not None:
        receipt["governance_receipt"] = governance_receipt
        receipt["governance_receipt_sha256"] = canonical_json_sha256(governance_receipt)
    if input_governance_required_adapters:
        receipt["input_governance_required_adapters"] = sorted(input_governance_required_adapters)
    receipt["receipt_sha256"] = canonical_json_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
    return receipt


def validate_receipt(
    receipt: Any, *, expected_profile_code: str | None = None,
    expected_input_literal: str | None = None, expected_raw_output: Any | None = None,
    expected_profile_source_sha256: str | None = None,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(receipt, dict):
        return ["RECEIPT_NOT_OBJECT"]
    required_strings = (
        "receipt_type", "operation_code", "execution_id", "profile_code", "profile_slug",
        "profile_source_sha256", "input_sha256", "raw_output_sha256", "execution_origin", "receipt_sha256",
    )
    for key in required_strings:
        if not _nonempty_string(receipt.get(key)):
            errors.append(f"MISSING_OR_EMPTY_{key.upper()}")
    for key in ("profile_source_sha256", "input_sha256", "raw_output_sha256", "receipt_sha256"):
        if _nonempty_string(receipt.get(key)) and not _is_sha256(receipt.get(key)):
            errors.append(f"{key.upper()}_INVALID")
    manifest_sha = receipt.get("obligation_manifest_sha256")
    if manifest_sha is not None and not _is_sha256(manifest_sha):
        errors.append("OBLIGATION_MANIFEST_SHA256_INVALID")
    if receipt.get("receipt_type") != RECEIPT_TYPE:
        errors.append("RECEIPT_TYPE_INVALID")
    if receipt.get("operation_code") != OPERATION_CODE:
        errors.append("OPERATION_CODE_INVALID")
    if receipt.get("execution_origin") not in ALLOWED_RUNTIME_ORIGINS:
        errors.append("EXECUTION_ORIGIN_NOT_MODEL_RUNTIME")
    if receipt.get("raw_output_captured") is not True:
        errors.append("RAW_OUTPUT_NOT_CAPTURED")
    source_refs = receipt.get("profile_source_refs")
    if not isinstance(source_refs, list) or not source_refs or not all(_nonempty_string(x) for x in source_refs):
        errors.append("PROFILE_SOURCE_REFS_INVALID")
    attestation = receipt.get("runtime_attestation")
    if not isinstance(attestation, dict):
        errors.append("RUNTIME_ATTESTATION_MISSING")
    else:
        for key in (
            "provider", "model_id", "run_id", "attested_at", "attestation_verifier",
            "attestation_evidence_sha256", "verified_request_sha256", "verified_response_sha256",
        ):
            if not _nonempty_string(attestation.get(key)):
                errors.append(f"RUNTIME_ATTESTATION_{key.upper()}_MISSING")
        for key in ("attestation_evidence_sha256", "verified_request_sha256", "verified_response_sha256"):
            if _nonempty_string(attestation.get(key)) and not _is_sha256(attestation.get(key)):
                errors.append(f"RUNTIME_ATTESTATION_{key.upper()}_INVALID")
    if expected_profile_code is not None and receipt.get("profile_code") != expected_profile_code:
        errors.append("PROFILE_CODE_MISMATCH")
    if expected_profile_source_sha256 is not None and receipt.get("profile_source_sha256") != expected_profile_source_sha256:
        errors.append("PROFILE_SOURCE_SHA256_MISMATCH")
    if expected_input_literal is not None and receipt.get("input_sha256") != sha256_text(expected_input_literal):
        errors.append("INPUT_SHA256_MISMATCH")
    if expected_raw_output is not None and receipt.get("raw_output_sha256") != canonical_json_sha256(expected_raw_output):
        errors.append("RAW_OUTPUT_SHA256_MISMATCH")
    errors.extend(_validate_lf_adapter_invocations(receipt.get("lf_adapter_invocations"), receipt.get("profile_code")))

    required_adapters = receipt.get("input_governance_required_adapters")
    governance_receipt = receipt.get("governance_receipt")
    governance_sha = receipt.get("governance_receipt_sha256")
    attested_governance_sha = attestation.get("governance_receipt_sha256") if isinstance(attestation, dict) else None
    if required_adapters is None:
        if governance_receipt is not None or governance_sha is not None or attested_governance_sha is not None:
            errors.append("INPUT_GOVERNANCE_RECEIPT_UNEXPECTED")
    elif (
        not isinstance(required_adapters, list)
        or not required_adapters
        or len(required_adapters) != len(set(required_adapters))
        or not all(_nonempty_string(code) for code in required_adapters)
    ):
        errors.append("INPUT_GOVERNANCE_REQUIRED_ADAPTERS_INVALID")
    else:
        invocation_codes = {
            item.get("adapter_code")
            for item in receipt.get("lf_adapter_invocations", [])
            if isinstance(item, dict)
        }
        if not set(required_adapters).issubset(invocation_codes):
            errors.append("INPUT_GOVERNANCE_REQUIRED_ADAPTER_INVOCATION_MISSING")
        errors.extend(validate_governance_receipt(governance_receipt))
        if not _is_sha256(governance_sha):
            errors.append("INPUT_GOVERNANCE_RECEIPT_SHA256_INVALID")
        elif isinstance(governance_receipt, dict) and governance_sha != canonical_json_sha256(governance_receipt):
            errors.append("INPUT_GOVERNANCE_RECEIPT_SHA256_MISMATCH")
        if attested_governance_sha != governance_sha:
            errors.append("INPUT_GOVERNANCE_ATTESTATION_SHA256_MISMATCH")

    claimed_receipt_sha = receipt.get("receipt_sha256")
    if _nonempty_string(claimed_receipt_sha):
        recalculated = canonical_json_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        if claimed_receipt_sha != recalculated:
            errors.append("RECEIPT_SHA256_MISMATCH")
    if receipt.get("downstream_authorized") is True:
        errors.append("SELF_AUTHORIZATION_FORBIDDEN")
    return sorted(set(errors))


def authorize_downstream(
    *, profile_execution_required: bool, recipient: str, receipt: Any | None,
    expected_profile_code: str | None = None, expected_input_literal: str | None = None,
    expected_raw_output: Any | None = None, expected_profile_source_sha256: str | None = None,
    semantic_receipt: Any | None = None, semantic_check_bundle: Any | None = None,
    semantic_obligation_manifest: Any | None = None,
) -> dict[str, Any]:
    if recipient not in DOWNSTREAM_RECIPIENTS:
        return {"status": "BLOCK_PIPELINE", "blocking_codes": ["RECIPIENT_NOT_SUPPORTED"]}
    if not profile_execution_required:
        return {"status": "PASS_NO_PROFILE_REQUIRED", "blocking_codes": []}
    if receipt is None:
        return {"status": "BLOCK_PIPELINE", "blocking_codes": ["PROFILE_EXECUTION_RECEIPT_MISSING"]}
    errors = validate_receipt(
        receipt, expected_profile_code=expected_profile_code,
        expected_input_literal=expected_input_literal, expected_raw_output=expected_raw_output,
        expected_profile_source_sha256=expected_profile_source_sha256,
    )
    if errors:
        return {"status": "BLOCK_PIPELINE", "blocking_codes": errors}
    if recipient in PROVENANCE_ONLY_RECIPIENTS:
        return {"status": "PASS_PROFILE_EXECUTION_PROVENANCE", "blocking_codes": [], "receipt_sha256": receipt["receipt_sha256"], "authorized_recipient": recipient}
    semantic_errors = validate_semantic_judge_receipt(
        semantic_receipt, expected_bundle=semantic_check_bundle,
        expected_obligation_manifest=semantic_obligation_manifest,
        expected_raw_output=expected_raw_output, execution_receipt=receipt,
    )
    if semantic_errors:
        return {"status": "BLOCK_PIPELINE", "blocking_codes": semantic_errors}
    return {
        "status": "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY", "blocking_codes": [],
        "execution_receipt_sha256": receipt["receipt_sha256"],
        "semantic_receipt_sha256": semantic_receipt["receipt_sha256"],
        "obligation_manifest_sha256": receipt["obligation_manifest_sha256"],
        "authorized_recipient": recipient,
    }


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--profile-code")
    parser.add_argument("--input-file", type=Path)
    parser.add_argument("--raw-output", type=Path)
    parser.add_argument("--profile-source-sha256")
    parser.add_argument("--semantic-receipt", type=Path)
    parser.add_argument("--semantic-check-bundle", type=Path)
    parser.add_argument("--semantic-obligation-manifest", type=Path)
    parser.add_argument("--recipient", default="INTERNAL_AGENT")
    args = parser.parse_args(list(argv) if argv is not None else None)
    receipt = _load_json(args.receipt)
    input_literal = args.input_file.read_text(encoding="utf-8") if args.input_file else None
    raw_output = _load_json(args.raw_output) if args.raw_output else None
    semantic_receipt = _load_json(args.semantic_receipt) if args.semantic_receipt else None
    semantic_bundle = _load_json(args.semantic_check_bundle) if args.semantic_check_bundle else None
    semantic_manifest = _load_json(args.semantic_obligation_manifest) if args.semantic_obligation_manifest else None
    result = authorize_downstream(
        profile_execution_required=True, recipient=args.recipient, receipt=receipt,
        expected_profile_code=args.profile_code, expected_input_literal=input_literal,
        expected_raw_output=raw_output, expected_profile_source_sha256=args.profile_source_sha256,
        semantic_receipt=semantic_receipt, semantic_check_bundle=semantic_bundle,
        semantic_obligation_manifest=semantic_manifest,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"].startswith("PASS_") else 1


if __name__ == "__main__":
    raise SystemExit(main())
