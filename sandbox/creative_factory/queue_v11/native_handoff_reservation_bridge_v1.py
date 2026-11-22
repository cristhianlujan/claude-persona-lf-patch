"""SALY V11: V09 archive+freshness gate -> V10 SQL reservation -> SQL readback.

Candidate service choreography, deliberately NOT a Native sender. It cannot
prove the injected ports are authoritative: that is the runtime owner's duty.
No provider API, DB connection, host session discovery, QA, or DONE in module.
"""
from __future__ import annotations

import hashlib
import re
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

from sandbox.creative_factory.queue_v09.dispatch_fence_v1 import (
    DispatchFenceRejected, verify_dispatch_fence_v1,
)

KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
MODES = {"GPT_NATIVE": "OPENAI_CHATGPT_NATIVE",
         "CLAUDE_NATIVE": "ANTHROPIC_CLAUDE_NATIVE"}
NOT_SENT = ("native_transmitted", "provider_attested",
            "host_delivery_verified", "db_done_allowed")


class HandoffReservationRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def need(ok: bool, code: str) -> None:
    if not ok:
        raise HandoffReservationRejected(code)


def read_archive_manifest(archived: Mapping[str, Any]) -> str:
    """This is an integrity pin of local file bytes, NOT host/provider evidence."""
    need(isinstance(archived, Mapping) and
         isinstance(archived.get("archive_path"), str) and
         bool(archived["archive_path"]), "SALY_V11_ARCHIVE_UNAVAILABLE")
    root = Path(archived["archive_path"])
    manifest = root / "archive.json"
    need(root.is_absolute() and root.is_dir() and not root.is_symlink()
         and manifest.is_file() and not manifest.is_symlink(),
         "SALY_V11_ARCHIVE_UNAVAILABLE")
    try:
        return hashlib.sha256(manifest.read_bytes()).hexdigest()
    except OSError as exc:
        raise HandoffReservationRejected("SALY_V11_ARCHIVE_READ_FAILED") from exc


def port_call(port: Callable[..., Any], code: str, *args: Any) -> Any:
    try:
        return port(*args)
    except HandoffReservationRejected:
        raise
    except Exception as exc:
        raise HandoffReservationRejected(code) from exc


def prepare_native_reservation_handoff_v1(
    *, archived: Mapping[str, Any], executor: Mapping[str, Any],
    request_key: str,
    db_clock_reader: Callable[..., Any] | None,
    policy_reader: Callable[..., Any] | None,
    binding_reader: Callable[..., Any] | None,
    render_wire_reader: Callable[..., Any] | None,
    claim_credential_reader: Callable[..., Any] | None,
    reserve_dispatch: Callable[..., Any] | None,
    reservation_readback: Callable[..., Any] | None,
) -> dict[str, Any]:
    """Records and checks a V10 intent. Never calls the image tool.

    Port signatures:
      claim_credential_reader(run_id) -> {order_id,item_id,run_id,claim_id,claim_token}
      reserve_dispatch(token, run_id, mode, wire_sha, archive_sha, request_key)
      reservation_readback(reservation_id) -> V10 persisted row (independent SQL SELECT)

    The claim credential MUST be runtime-owned and never logged or returned.
    """
    need(type(request_key) is str and KEY_RE.fullmatch(request_key) is not None,
         "SALY_V11_REQUEST_KEY_INVALID")
    need(isinstance(archived, Mapping) and isinstance(executor, Mapping),
         "SALY_V11_INPUT_SHAPE_INVALID")
    need(all(callable(port) for port in (
        db_clock_reader, policy_reader, binding_reader, render_wire_reader,
        claim_credential_reader, reserve_dispatch, reservation_readback)),
        "SALY_V11_TRUSTED_PORT_MISSING")
    # A worker-supplied "status" cannot override the V09 live SQL+bytes fence.
    before = read_archive_manifest(archived)
    try:
        fenced = verify_dispatch_fence_v1(
            archived=archived, executor=executor,
            db_clock_reader=db_clock_reader,
            policy_reader=policy_reader,
            binding_reader=binding_reader,
            render_wire_reader=render_wire_reader)
    except DispatchFenceRejected as exc:
        raise HandoffReservationRejected("SALY_V11_V09_" + exc.code) from exc
    need(before == read_archive_manifest(archived),
         "SALY_V11_ARCHIVE_CHANGED_DURING_PREFLIGHT")
    need(fenced.get("schema_version") == "SALY_NATIVE_DISPATCH_FENCE_V1"
         and fenced.get("status") == "FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT"
         and all(fenced.get(k) is False for k in NOT_SENT),
         "SALY_V11_PREFLIGHT_FALSE_AUTHORITY")
    identity = ("order_id", "item_id", "run_id", "claim_id")
    need(all(type(archived.get(k)) is int and archived[k] > 0
             and fenced.get(k) == archived[k] for k in identity),
         "SALY_V11_PREFLIGHT_BINDING_MISMATCH")
    need(executor.get("mode") == archived.get("executor_mode")
         and archived.get("executor_mode") in MODES
         and executor.get("provider_identity") == MODES[archived["executor_mode"]],
         "SALY_V11_MODE_OR_PROVIDER_MISMATCH")
    need(type(archived.get("wire_sha256")) is str
         and SHA_RE.fullmatch(archived["wire_sha256"]) is not None
         and fenced.get("wire_sha256") == archived["wire_sha256"],
         "SALY_V11_WIRE_PIN_MISMATCH")
    need(type(archived.get("prompt_sha256")) is str
         and SHA_RE.fullmatch(archived["prompt_sha256"]) is not None,
         "SALY_V11_PROMPT_PIN_INVALID")

    credential = port_call(claim_credential_reader,
                           "SALY_V11_CLAIM_CREDENTIAL_READ_FAILED", archived["run_id"])
    need(isinstance(credential, Mapping)
         and all(type(credential.get(k)) is int
                 and credential[k] == archived[k] for k in identity)
         and type(credential.get("claim_token")) is str
         and bool(credential["claim_token"].strip()),
         "SALY_V11_CLAIM_CREDENTIAL_NOT_BOUND")
    # Only the SQL port receives claim_token. No logs, payload or result echo.
    result = port_call(
        reserve_dispatch, "SALY_V11_DB_RESERVATION_FAILED",
        credential["claim_token"], archived["run_id"], archived["executor_mode"],
        archived["wire_sha256"], before, request_key)
    need(isinstance(result, Mapping)
         and result.get("schema_version") == "SALY_NATIVE_DISPATCH_RESERVATION_V1"
         and result.get("status") in (
             "RESERVED_NOT_DISPATCHED", "ALREADY_RESERVED_NOT_DISPATCHED")
         and all(result.get(k) is False for k in NOT_SENT)
         and result.get("dispatch_authorized") is False
         and type(result.get("reservation_id")) is int
         and result["reservation_id"] > 0
         and result.get("claim_id") == archived["claim_id"]
         and result.get("run_id") == archived["run_id"],
         "SALY_V11_RESERVATION_RECEIPT_INVALID")
    row = port_call(reservation_readback,
                    "SALY_V11_RESERVATION_READBACK_FAILED",
                    result["reservation_id"])
    expected = {
        "id": result["reservation_id"],
        "order_id": archived["order_id"], "item_id": archived["item_id"],
        "run_id": archived["run_id"], "claim_id": archived["claim_id"],
        "request_key": request_key, "executor_mode": archived["executor_mode"],
        "executor_provider": MODES[archived["executor_mode"]],
        "wire_sha256": archived["wire_sha256"],
        "prompt_sha256": archived["prompt_sha256"],
        "archive_reported_sha256": before,
        "state": "RESERVED_NOT_DISPATCHED",
    }
    need(isinstance(row, Mapping)
         and all(row.get(k) == v for k, v in expected.items()),
         "SALY_V11_RESERVATION_READBACK_DRIFT")
    need(type(row.get("input_snapshot_sha256")) is str
         and SHA_RE.fullmatch(row["input_snapshot_sha256"]) is not None,
         "SALY_V11_SNAPSHOT_PIN_INVALID")
    # Replays must never be interpreted as a new authority to call Native.
    replay = result["status"] == "ALREADY_RESERVED_NOT_DISPATCHED"
    need(before == read_archive_manifest(archived),
         "SALY_V11_ARCHIVE_CHANGED_AFTER_RESERVATION")
    return {
        "schema_version": "SALY_NATIVE_V11_RESERVATION_HANDOFF_V1",
        "status": ("IDEMPOTENT_RESERVATION_READBACK_NOT_SENT" if replay
                   else "RESERVATION_READBACK_VERIFIED_NOT_SENT"),
        "order_id": archived["order_id"], "item_id": archived["item_id"],
        "run_id": archived["run_id"], "claim_id": archived["claim_id"],
        "reservation_id": result["reservation_id"],
        "executor_mode": archived["executor_mode"],
        "wire_sha256": archived["wire_sha256"],
        "archive_manifest_sha256": before,
        "reservation_replay": replay,
        "native_transmitted": False, "provider_attested": False,
        "host_delivery_verified": False, "db_done_allowed": False,
        "dispatch_authorized": False,
        "next_action": "BLOCKED_HOST_NATIVE_DISPATCH_ADAPTER_NOT_CONNECTED",
    }
