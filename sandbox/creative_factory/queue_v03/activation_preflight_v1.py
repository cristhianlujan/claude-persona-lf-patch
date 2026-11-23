"""SALY creative serial queue: read-only activation evidence gate.

CANDIDATE, NO EFFECTS. All rows must be supplied from a verified source query.
This does not grant execution, attest an image provider, or mutate any DB.
"""
from __future__ import annotations

from collections.abc import Callable, Iterable, Mapping
from datetime import datetime, timezone
from hashlib import sha256
from typing import Any

REQUIRED_KEYS = (
    "QUEUE_MAX",
    "MAX_ATTEMPTS",
    "QUEUE_TIMEOUT_SECONDS",
    "LEASE_SECONDS",
)


def _parse_instant(raw: Any) -> datetime | None:
    if isinstance(raw, datetime):
        dt = raw
    elif isinstance(raw, str):
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    return dt.astimezone(timezone.utc) if dt.tzinfo is not None else None


def check_creative_config(rows: Iterable[Mapping[str, Any]], asof: datetime) -> dict[str, Any]:
    """Mirrors readback of latest valid_from, type/status/version checks; never defaults values."""
    if asof.tzinfo is None:
        raise ValueError("CREATIVE_CONFIG_ASOF_REQUIRED")
    at = asof.astimezone(timezone.utc)
    values: dict[str, Any] = {}
    versions: dict[str, str] = {}
    blockers: list[str] = []
    records = list(rows)
    for key in REQUIRED_KEYS:
        candidates = []
        for row in records:
            if row.get("scope") != "CREATIVE_FACTORY" or row.get("config_key") != key:
                continue
            dt = _parse_instant(row.get("valid_from"))
            if dt is not None and dt <= at:
                candidates.append((dt, row))
        if not candidates:
            blockers.append(f"CREATIVE_CONFIG_MISSING:{key}")
            continue
        latest = max(candidates, key=lambda x: x[0])
        row = latest[1]
        raw = row.get("config_value")
        if (row.get("value_status") != "REAL" or row.get("value_type") != "INTEGER"
                or not isinstance(raw, str) or not raw.isascii() or not raw.isdecimal()
                or raw[0] == "0" or int(raw) > 2147483647):
            blockers.append(f"CREATIVE_CONFIG_INVALID:{key}")
            continue
        values[key] = int(raw)
        versions[key] = latest[0].isoformat()
    return {
        "schema_version": "SALY_CREATIVE_ACTIVATION_PREFLIGHT_V1",
        "activation_allowed": False,  # preflight cannot confer operational authority
        "config_contract_valid": not blockers,
        "blocking_codes": blockers,
        "config_versions": versions,
        "config_values": values,
        "next_action": (
            "REGISTER_APPROVED_VALUES_VIA_GOVERNED_MIGRATION"
            if blockers else "VERIFY_TRUSTED_NATIVE_PROVIDER_AND_HOST_DELIVERY"
        ),
    }


class DeliveryEvidenceRejected(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def verify_delivered_image(
    *,
    expected: Mapping[str, Any],
    message_id: str,
    host_readback: Callable[[str], Mapping[str, Any]] | None,
    provider_readback: Callable[[str], Mapping[str, Any]] | None,
    artifact_readback: Callable[[str], bytes] | None,
) -> dict[str, Any]:
    """Verify a trusted *injected* host message and real image bytes.

    This function cannot prove host trust by itself: caller MUST bind readers
    to independently authorized runtime connectors, not user-submitted JSON.
    A positive unit test with fakes is a contract test, NOT provider evidence.
    """
    if host_readback is None or artifact_readback is None:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_TRUSTED_ADAPTER_MISSING")
    if provider_readback is None:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_PROVIDER_ATTESTATION_UNAVAILABLE")
    required = ("run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256", "recipient_surface")
    if any(expected.get(key) in (None, "") for key in required):
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_BINDING_INCOMPLETE")
    digest = expected["artifact_sha256"]
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_INVALID_ARTIFACT_HASH")
    try:
        provider = provider_readback(expected["artifact_ref"])
    except Exception as exc:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_PROVIDER_READBACK_FAILED") from exc
    if not isinstance(provider, Mapping) or provider.get("generation_status") != "GENERATED":
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_NATIVE_GENERATION_UNVERIFIED")
    for key in ("run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256"):
        if provider.get(key) != expected[key]:
            raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_PROVIDER_BINDING_MISMATCH:" + key)
    if not isinstance(message_id, str) or not message_id.strip():
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_MESSAGE_ID_REQUIRED")
    try:
        host = host_readback(message_id)
    except Exception as exc:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_HOST_READBACK_FAILED") from exc
    if not isinstance(host, Mapping):
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_HOST_RECEIPT_INVALID")
    if host.get("delivery_status") != "DELIVERED":
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_NOT_CONFIRMED")
    if host.get("message_id") != message_id:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_MESSAGE_MISMATCH")
    for key in required:
        if host.get(key) != expected[key]:
            raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_BINDING_MISMATCH:" + key)
    try:
        body = artifact_readback(expected["artifact_ref"])
    except Exception as exc:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_ARTIFACT_READBACK_FAILED") from exc
    if not isinstance(body, bytes) or not body or sha256(body).hexdigest() != digest:
        raise DeliveryEvidenceRejected("CREATIVE_DELIVERY_ARTIFACT_BYTES_MISMATCH")
    # Refuse even if correct bytes came from a different host/message.
    return {
        "schema_version": "SALY_CREATIVE_DELIVERY_READBACK_V1",
        "receipt_status": "DELIVERY_READBACK_VERIFIED_BY_INJECTED_HOST",
        "run_id": expected["run_id"],
        "claim_id": expected["claim_id"],
        "message_id": message_id,
        "artifact_sha256": digest,
        "recipient_surface": expected["recipient_surface"],
        "production_authorized": False,
    }