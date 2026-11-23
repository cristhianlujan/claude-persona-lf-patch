"""SALY creative Native RENDER_READY admission contract (candidate, no effects).

This module is not an adapter and has NO DB writes, Native tool calls, grants,
rendering effects, or ability to promote existing REVIEW_ONLY orders. It only
validates snapshots from ports bound by an authorized runtime. An untrusted
caller-supplied snapshot is never an authorized source. Existing SQL canonical
wire SALY_CANONICAL_NATIVE_WIRE_V1 is strictly REVIEW_ONLY and is rejected.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
from collections.abc import Callable, Mapping
from datetime import datetime, timezone
from typing import Any

PROVIDERS = {
    "GPT_NATIVE": "OPENAI_CHATGPT_NATIVE",
    "CLAUDE_NATIVE": "ANTHROPIC_CLAUDE_NATIVE",
}
POLICY_KEYS = ("QUEUE_MAX", "MAX_ATTEMPTS", "QUEUE_TIMEOUT_SECONDS", "LEASE_SECONDS")


class RenderAdmissionRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def require(ok: bool, code: str) -> None:
    if not ok:
        raise RenderAdmissionRejected(code)


def _call(port: Callable[..., Any] | None, code: str, *args: Any) -> Any:
    require(callable(port), "CREATIVE_RENDER_TRUSTED_READER_MISSING")
    try:
        return port(*args)
    except RenderAdmissionRejected:
        raise
    except Exception as exc:
        raise RenderAdmissionRejected(code) from exc


def _asof(value: Any) -> datetime:
    require(isinstance(value, datetime) and value.tzinfo is not None,
            "CREATIVE_RENDER_ASOF_INVALID")
    return value.astimezone(timezone.utc)


def _instant(value: Any) -> datetime | None:
    try:
        if isinstance(value, datetime):
            dt = value
        elif isinstance(value, str):
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        else:
            return None
        return dt.astimezone(timezone.utc) if dt.tzinfo is not None else None
    except ValueError:
        return None


def _sha(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def _object(value: Any) -> bool:
    return isinstance(value, Mapping)


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    obj: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in obj, "CREATIVE_RENDER_WIRE_DUPLICATE_JSON_KEY")
        obj[key] = value
    return obj


def validate_render_ready(
    *,
    order_id: int,
    item_id: int,
    run_id: int,
    asof: datetime,
    executor: Mapping[str, Any],
    policy_reader: Callable[[datetime], Mapping[str, Any]] | None,
    binding_reader: Callable[[int], Mapping[str, Any]] | None,
    render_wire_reader: Callable[[int, int], Mapping[str, Any]] | None,
) -> dict[str, Any]:
    """Pure contract validation; all readers MUST be runtime-owned authoritative.

    RENDER_READY is intentionally separate from the existing PLAN_ONLY wire.
    The proposed RENDER wire producer does not yet exist in deployed Supabase.
    This cannot be used for current 2 review-only orders.
    """
    require(all(type(v) is int and v > 0 for v in (order_id, item_id, run_id)),
            "CREATIVE_RENDER_ENTITY_ID_INVALID")
    t = _asof(asof)
    require(_object(executor), "CREATIVE_RENDER_EXECUTOR_INVALID")
    mode = executor.get("mode")
    require(type(mode) is str and mode in PROVIDERS,
            "CREATIVE_RENDER_EXECUTOR_MODE_INVALID")
    require(executor.get("provider_identity") == PROVIDERS[mode],
            "CREATIVE_RENDER_PROVIDER_MODE_MISMATCH")
    require(executor.get("conversation_scope") == "EXISTING_CONVERSATION_ONLY"
            and executor.get("native_api_invocation") is False
            and executor.get("native_session_creation") is False
            and executor.get("remote_api_fallback") == "FORBIDDEN",
            "CREATIVE_RENDER_NATIVE_SESSION_INVALID")
    require(executor.get("provider_attested") is False,
            "CREATIVE_RENDER_PROVIDER_ATTESTATION_FORGED")
    # Required ports are passed by a trusted executor, never via the request JSON.
    require(all(callable(v) for v in (policy_reader, binding_reader, render_wire_reader)),
            "CREATIVE_RENDER_TRUSTED_READER_MISSING")

    policy = _call(policy_reader, "CREATIVE_RENDER_POLICY_READ_FAILED", t)
    require(_object(policy) and policy.get("schema_version") == "CREATIVE_EXECUTION_POLICY_V1"
            and policy.get("config_scope") == "CREATIVE_FACTORY",
            "CREATIVE_RENDER_POLICY_SOURCE_INVALID")
    versions = policy.get("versions")
    require(_object(versions), "CREATIVE_RENDER_POLICY_VERSIONS_MISSING")
    for k in POLICY_KEYS:
        v = policy.get(k)
        require(type(v) is int and v > 0 and v <= 2147483647,
                "CREATIVE_RENDER_POLICY_KEY_INVALID:" + k)
        at = _instant(versions.get(k))
        require(at is not None and at <= t, "CREATIVE_RENDER_POLICY_VERSION_INVALID:" + k)

    row = _call(binding_reader, "CREATIVE_RENDER_BINDING_READ_FAILED", run_id)
    require(_object(row), "CREATIVE_RENDER_BINDING_INVALID")
    require(row.get("order_id") == order_id and row.get("item_id") == item_id
            and row.get("run_id") == run_id and type(row.get("claim_id")) is int
            and row.get("claim_id") > 0,
            "CREATIVE_RENDER_RUN_CLAIM_BINDING_MISMATCH")
    require(row.get("queue_mode") == "SERIAL_V1"
            and row.get("rendering_authority") is True
            and row.get("render_authorized") is True
            and row.get("review_only") is False,
            "CREATIVE_RENDER_ORDER_AUTHORITY_MISSING")
    require(row.get("order_status") in ("PLANIFICADO", "EN_PROCESO")
            and row.get("item_status") in ("LISTO", "PRODUCIENDO"),
            "CREATIVE_RENDER_ORDER_ITEM_NOT_READY")
    require(row.get("run_state") == "EJECUTANDO"
            and row.get("claim_state") == "ACTIVE"
            and isinstance(row.get("worker_ref"), str)
            and bool(row["worker_ref"].strip())
            and row.get("worker_ref") == row.get("claim_worker_ref"),
            "CREATIVE_RENDER_RUN_CLAIM_NOT_ACTIVE")
    require(_instant(row.get("lease_until")) is not None
            and _instant(row["lease_until"]) > t
            and _instant(row.get("deadline_at")) is not None
            and _instant(row["deadline_at"]) > t,
            "CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED")
    attempt = row.get("attempt_number")
    require(type(attempt) is int and 1 <= attempt <= policy["MAX_ATTEMPTS"],
            "CREATIVE_RENDER_ATTEMPT_EXCEEDED")
    run_policy = row.get("execution_policy")
    require(_object(run_policy) and run_policy.get("schema_version") == "CREATIVE_EXECUTION_POLICY_V1"
            and run_policy.get("config_scope") == "CREATIVE_FACTORY"
            and all(run_policy.get(k) == policy[k] for k in POLICY_KEYS)
            and run_policy.get("versions") == versions,
            "CREATIVE_RENDER_RUN_POLICY_DRIFT")
    require(_sha(row.get("input_snapshot_sha256")) and _sha(row.get("contract_sha256")),
            "CREATIVE_RENDER_RUN_SNAPSHOT_PIN_MISSING")

    wire = _call(render_wire_reader, "CREATIVE_RENDER_WIRE_READ_FAILED", item_id, run_id)
    require(_object(wire) and wire.get("schema_version") == "SALY_NATIVE_RENDER_WIRE_V1"
            and wire.get("status") == "RENDER_WIRE_FROZEN_AUTHORIZED"
            and wire.get("render_authorized") is True
            and wire.get("native_transmitted") is False,
            "CREATIVE_RENDER_WIRE_NOT_AUTHORIZED")
    require(wire.get("order_id") == order_id and wire.get("item_id") == item_id
            and wire.get("run_id") == run_id and wire.get("claim_id") == row["claim_id"]
            and wire.get("executor_mode") == mode
            and wire.get("executor_provider") == PROVIDERS[mode],
            "CREATIVE_RENDER_WIRE_BINDING_MISMATCH")
    require(wire.get("input_snapshot_sha256") == row["input_snapshot_sha256"]
            and wire.get("contract_sha256") == row["contract_sha256"],
            "CREATIVE_RENDER_WIRE_SOURCE_PIN_DRIFT")
    encoded = wire.get("wire_base64")
    require(type(encoded) is str and bool(encoded), "CREATIVE_RENDER_WIRE_BASE64_MISSING")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RenderAdmissionRejected("CREATIVE_RENDER_WIRE_BASE64_INVALID") from exc
    require(_sha(wire.get("wire_sha256"))
            and hashlib.sha256(raw).hexdigest() == wire["wire_sha256"],
            "CREATIVE_RENDER_WIRE_SHA256_MISMATCH")
    try:
        body = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except RenderAdmissionRejected:
        raise
    except (ValueError, UnicodeError) as exc:
        raise RenderAdmissionRejected("CREATIVE_RENDER_WIRE_JSON_INVALID") from exc
    require(type(body) is dict and set(body) == {"prompt", "attachments"}
            and isinstance(body["prompt"], str) and body["prompt"].strip()
            and type(body["attachments"]) is list,
            "CREATIVE_RENDER_WIRE_PAYLOAD_INVALID")
    require(_sha(wire.get("prompt_sha256"))
            and hashlib.sha256(body["prompt"].encode("utf-8")).hexdigest() == wire["prompt_sha256"],
            "CREATIVE_RENDER_PROMPT_HASH_DRIFT")
    # Never leak queue fencing token or authorization evidence to the graphic generator.
    require("claim_token" not in body and "queue_claim_token" not in body
            and not any(x in body["prompt"] for x in ("claim_token", "queue_claim_token")),
            "CREATIVE_RENDER_TOKEN_IN_NATIVE_PAYLOAD")
    require(wire.get("provider_receipt") is None,
            "CREATIVE_RENDER_PROVIDER_RECEIPT_PRETENDED")
    return {
        "schema_version": "SALY_RENDER_READY_ADMISSION_V1",
        "status": "RENDER_READY_CANDIDATE_VALIDATED_NOT_DISPATCHED",
        "order_id": order_id, "item_id": item_id, "run_id": run_id,
        "claim_id": row["claim_id"],
        "executor_mode": mode, "executor_provider": PROVIDERS[mode],
        "wire_sha256": wire["wire_sha256"], "prompt_sha256": wire["prompt_sha256"],
        "input_snapshot_sha256": row["input_snapshot_sha256"],
        "config_versions": dict(versions),
        "image_generation_executed": False,
        "provider_attested": False,
        "host_delivery_verified": False,
        "db_done_allowed": False,
        "next_action": "EXECUTE_IN_VERIFIED_CURRENT_NATIVE_SESSION_ONLY_AFTER_RUNTIME_ENABLEMENT",
    }
