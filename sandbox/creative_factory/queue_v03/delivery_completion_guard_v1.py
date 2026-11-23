"""Candidate SALY delivery->DONE coordinator, no built-in provider or host adapter.

Trusted ports MUST be supplied by an authorized runtime (never from an order or
worker payload). The program does not send/render images and cannot certify that
ChatGPT displayed a message unless the external host readback really exists.
"""
from __future__ import annotations

from collections.abc import Callable, Mapping
from typing import Any

from activation_preflight_v1 import DeliveryEvidenceRejected, verify_delivered_image


class DeliveryPorts:
    """The owner/executor binds real DB/provider/host ports, not the user request."""

    def __init__(
        self, *,
        claim_readback: Callable[[int], Mapping[str, Any]] | None = None,
        provider_readback: Callable[[str], Mapping[str, Any]] | None = None,
        host_readback: Callable[[str], Mapping[str, Any]] | None = None,
        artifact_readback: Callable[[str], bytes] | None = None,
        receipt_readback: Callable[[int], Mapping[str, Any] | None] | None = None,
        record_delivery: Callable[[str, int, str, str], Mapping[str, Any]] | None = None,
        release_done: Callable[[str], Mapping[str, Any]] | None = None,
    ) -> None:
        self.claim_readback = claim_readback
        self.provider_readback = provider_readback
        self.host_readback = host_readback
        self.artifact_readback = artifact_readback
        self.receipt_readback = receipt_readback
        self.record_delivery = record_delivery
        self.release_done = release_done


def _require(ok: bool, code: str) -> None:
    if not ok:
        raise DeliveryEvidenceRejected(code)


def _call(code: str, fn: Callable[..., Any], *args: Any) -> Any:
    try:
        return fn(*args)
    except DeliveryEvidenceRejected:
        raise
    except Exception as exc:
        raise DeliveryEvidenceRejected(code) from exc


def finish_verified_delivery(*, run_id: int, message_id: str,
                             ports: DeliveryPorts | None) -> dict[str, Any]:
    """Read trusted sources, prove delivery, write receipt, read it back, then DONE.

    A valid fake adapter test shows sequencing only, never real host delivery.
    The existing DB RPC MUST independently enforce live claim fencing and QA.
    """
    _require(type(run_id) is int and run_id > 0,
             "CREATIVE_DELIVERY_RUN_ID_INVALID")
    _require(type(message_id) is str and bool(message_id.strip()),
             "CREATIVE_DELIVERY_MESSAGE_ID_REQUIRED")
    _require(isinstance(ports, DeliveryPorts) and all(callable(getattr(ports, name)) for name in (
        "claim_readback", "provider_readback", "host_readback", "artifact_readback",
        "receipt_readback", "record_delivery", "release_done")),
        "CREATIVE_DELIVERY_TRUSTED_ADAPTER_MISSING")

    binding = _call("CREATIVE_DELIVERY_DB_BINDING_READBACK_FAILED", ports.claim_readback, run_id)
    _require(isinstance(binding, Mapping), "CREATIVE_DELIVERY_DB_BINDING_INVALID")
    _require(binding.get("run_id") == run_id and type(binding.get("claim_id")) is int
             and binding["claim_id"] > 0 and type(binding.get("item_id")) is int
             and binding["item_id"] > 0 and type(binding.get("claim_token")) is str
             and bool(binding["claim_token"].strip()),
             "CREATIVE_DELIVERY_DB_BINDING_MISMATCH")
    _require(binding.get("run_state") == "EXITOSO" and binding.get("item_status") == "APROBADO"
             and binding.get("claim_state") == "ACTIVE",
             "CREATIVE_DELIVERY_RUN_QA_CLAIM_NOT_READY")
    expected = {key: binding.get(key) for key in (
        "run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256",
        "recipient_surface")}
    proof = verify_delivered_image(
        expected=expected, message_id=message_id,
        provider_readback=ports.provider_readback,
        host_readback=ports.host_readback,
        artifact_readback=ports.artifact_readback,
    )
    # Expected fields come from DB, not from worker-supplied text.
    receipt_expected = {
        "claim_id": binding["claim_id"], "run_id": run_id,
        "artifact_ref": binding["artifact_ref"],
        "artifact_sha256": binding["artifact_sha256"],
        "delivery_channel": binding["recipient_surface"],
        "delivery_receipt": message_id,
    }
    receipt = _call("CREATIVE_DELIVERY_RECEIPT_READBACK_FAILED", ports.receipt_readback, run_id)
    if receipt is None:
        result = _call("CREATIVE_DELIVERY_RECORD_FAILED", ports.record_delivery,
                       binding["claim_token"], run_id, binding["recipient_surface"], message_id)
        _require(isinstance(result, Mapping) and result.get("status") == "DELIVERY_RECORDED"
                 and result.get("run_id") == run_id,
                 "CREATIVE_DELIVERY_RECORD_NOT_CONFIRMED")
        receipt = _call("CREATIVE_DELIVERY_RECEIPT_READBACK_FAILED", ports.receipt_readback, run_id)
    _require(isinstance(receipt, Mapping) and all(receipt.get(k) == v
             for k, v in receipt_expected.items()),
             "CREATIVE_DELIVERY_DB_RECEIPT_MISMATCH")

    # DB RPC must independently re-evaluate live lease, token, QA and lifecycle.
    result = _call("CREATIVE_DELIVERY_RELEASE_FAILED", ports.release_done, binding["claim_token"])
    _require(isinstance(result, Mapping) and result.get("status") == "RELEASED"
             and result.get("result") == "DONE" and result.get("claim_id") == binding["claim_id"],
             "CREATIVE_DELIVERY_RELEASE_NOT_CONFIRMED")
    return {
        "schema_version": "SALY_CREATIVE_DELIVERY_COMPLETION_V1",
        "status": "DB_DONE_AFTER_DUAL_READBACK",
        "run_id": run_id,
        "claim_id": binding["claim_id"],
        "message_id": message_id,
        "artifact_sha256": proof["artifact_sha256"],
        "order_closed": result.get("order_closed") is True,
        "production_authorized": False,
    }
