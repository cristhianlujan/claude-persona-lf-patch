"""LF owner chat authorization V1 -- verification only, no ingestion/writes.

A model-generated JSON, screenshot, pasted chat transcript or claimed sender has
NO approval authority. Only a non-LLM first-party signed message can qualify.
ChatGPT message signing is NOT currently available to this integration.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

_ALLOWED_ACTIONS = frozenset({"PROMOTE_RULE_BATCH", "MERGE_GOVERNANCE_PR"})
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_CHALLENGE = re.compile(r"LF-[A-Z0-9]{12,48}\Z")
_APPROVAL = re.compile(r"\A(?:APRUEBO|AUTORIZO)\s+(LF-[A-Z0-9]{12,48})\s*\Z", re.IGNORECASE)
_HEX40 = re.compile(r"[0-9a-f]{40}\Z")


class ApprovalRejected(ValueError):
    """Stable fail-closed reason code."""


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _b64(value: Any) -> bytes:
    if not isinstance(value, str) or not value or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ApprovalRejected("INVALID_BASE64URL")
    try:
        return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except (ValueError, TypeError) as exc:
        raise ApprovalRejected("INVALID_BASE64URL") from exc


def _parse_utc(value: Any) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ApprovalRejected("INVALID_UTC_TIMESTAMP")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ApprovalRejected("INVALID_UTC_TIMESTAMP") from exc


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ApprovalRejected("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def normalized_scope(scope: Any) -> dict[str, Any]:
    if not isinstance(scope, dict) or scope.get("repository") != "cristhianlujan/claude-persona-lf-patch":
        raise ApprovalRejected("INVALID_REPOSITORY_SCOPE")
    kind = scope.get("action")
    if kind not in _ALLOWED_ACTIONS:
        raise ApprovalRejected("INVALID_ACTION")
    if kind == "MERGE_GOVERNANCE_PR":
        if set(scope) != {"action", "repository", "pr_number", "head_sha"}:
            raise ApprovalRejected("NONEXACT_PR_SCOPE")
        if type(scope["pr_number"]) is not int or scope["pr_number"] <= 0 or not isinstance(scope["head_sha"], str) or not _HEX40.fullmatch(scope["head_sha"]):
            raise ApprovalRejected("INVALID_PR_SCOPE")
    else:
        if set(scope) != {"action", "repository", "pr_number", "head_sha",
                          "execution_id", "rule_codes", "rule_snapshots_sha256"}:
            raise ApprovalRejected("NONEXACT_RULE_SCOPE")
        if type(scope["pr_number"]) is not int or scope["pr_number"] <= 0 or not isinstance(scope["head_sha"], str) or not _HEX40.fullmatch(scope["head_sha"]):
            raise ApprovalRejected("INVALID_PR_SCOPE")
        codes = scope["rule_codes"]
        if not isinstance(scope["execution_id"], str) or not scope["execution_id"].startswith("EXEC-"):
            raise ApprovalRejected("INVALID_RUN_SCOPE")
        if not isinstance(codes, list) or not codes or any(
            not isinstance(x, str) or not re.fullmatch(r"[A-Z0-9_-]{4,128}", x)
            for x in codes
        ) or codes != sorted(set(codes)):
            raise ApprovalRejected("NONEXACT_RULE_COHORT")
        if not isinstance(scope["rule_snapshots_sha256"], str) or not _SHA256.fullmatch(scope["rule_snapshots_sha256"]):
            raise ApprovalRejected("INVALID_RULE_SNAPSHOTS")
    return scope


def verify_event(packet: dict[str, Any], *,
                 trusted_public_key: Ed25519PublicKey | None,
                 trusted_key_id: str | None,
                 trusted_owner_subject: str | None,
                 expected_scope: dict[str, Any],
                 now: datetime) -> dict[str, Any]:
    """Verify provenance but DO NOT consume. Atomically consume using DB gate.

    Trusted key, owner subject and expected scope MUST be independently provided
    by a server-side non-LLM authority, NEVER read from packet or model output.
    """
    if not trusted_public_key or not trusted_key_id or not trusted_owner_subject:
        raise ApprovalRejected("TRUSTED_CHAT_INGRESS_NOT_CONFIGURED")
    if not isinstance(packet, dict) or set(packet) != {"key_id", "payload_b64", "signature_b64"}:
        raise ApprovalRejected("PACKET_FORMAT_INVALID")
    if packet["key_id"] != trusted_key_id:
        raise ApprovalRejected("UNTRUSTED_SIGNER")
    payload_bytes = _b64(packet["payload_b64"])
    signature = _b64(packet["signature_b64"])
    if len(signature) != 64:
        raise ApprovalRejected("INVALID_SIGNATURE")
    try:
        trusted_public_key.verify(signature, payload_bytes)
    except InvalidSignature as exc:
        raise ApprovalRejected("INVALID_SIGNATURE") from exc
    try:
        event = json.loads(payload_bytes.decode("utf-8"), object_pairs_hook=_unique_pairs)
    except (ValueError, UnicodeError) as exc:
        raise ApprovalRejected("PAYLOAD_JSON_INVALID") from exc
    if not isinstance(event, dict) or set(event) != {
        "schema_version", "event_type", "source_platform", "issuer_kind",
        "actor_subject", "conversation_id", "message_id", "challenge_id",
        "literal_text", "sent_at", "expires_at", "scope"
    }:
        raise ApprovalRejected("EVENT_SCHEMA_INVALID")
    if (event["schema_version"] != "LF_OWNER_CHAT_SIGNED_MESSAGE_V1"
        or event["event_type"] != "USER_MESSAGE"
        or event["source_platform"] != "CHATGPT"
        or event["issuer_kind"] != "TRUSTED_FIRST_PARTY_INGRESS"):
        raise ApprovalRejected("UNTRUSTED_EVENT_ORIGIN")
    if event["actor_subject"] != trusted_owner_subject:
        raise ApprovalRejected("WRONG_OWNER_IDENTITY")
    for key in ("conversation_id", "message_id"):
        if not isinstance(event[key], str) or len(event[key]) < 12:
            raise ApprovalRejected("INVALID_CHAT_PROVENANCE")
    if not isinstance(event["challenge_id"], str) or not _CHALLENGE.fullmatch(event["challenge_id"]):
        raise ApprovalRejected("INVALID_CHALLENGE")
    if not isinstance(event["literal_text"], str) or len(event["literal_text"]) > 512:
        raise ApprovalRejected("INVALID_LITERAL_TEXT")
    parsed = _APPROVAL.fullmatch(event["literal_text"].strip())
    if not parsed or parsed.group(1).upper() != event["challenge_id"]:
        raise ApprovalRejected("NO_EXPLICIT_CHALLENGE_APPROVAL")
    t0, t1 = _parse_utc(event["sent_at"]), _parse_utc(event["expires_at"])
    if now.tzinfo is None:
        raise ApprovalRejected("CLOCK_NOT_UTC_AWARE")
    at = now.astimezone(timezone.utc)
    if (t0 > at + timedelta(seconds=30)
        or t1 <= at or t1 <= t0
        or t1 - t0 > timedelta(minutes=15)):
        raise ApprovalRejected("CHAT_APPROVAL_EXPIRED_OR_FUTURE")
    actual = normalized_scope(event["scope"])
    wanted = normalized_scope(expected_scope)
    if canonical(actual) != canonical(wanted):
        raise ApprovalRejected("EXACT_SCOPE_MISMATCH")
    return {
        "receipt_schema": "LF_OWNER_CHAT_VERIFIED_RECEIPT_V1",
        "source": "SIGNED_USER_MESSAGE_NOT_MODEL",
        "actor_subject": event["actor_subject"],
        "message_id": event["message_id"],
        "conversation_id": event["conversation_id"],
        "challenge_id": event["challenge_id"],
        "literal_text_sha256": digest(event["literal_text"].encode("utf-8")),
        "payload_sha256": digest(payload_bytes),
        "scope_sha256": digest(canonical(actual)),
        "action": actual["action"],
        "scope": actual,
        "sent_at": event["sent_at"],
        "expires_at": event["expires_at"],
        "key_id": trusted_key_id,
        "signature_verified": True,
        "consumed": False,
    }
