"""Governed preflight and local capture for a sealed, review-only Native envelope.

No provider SDK, external send, image generation, DB writes or QA promotion here.
A local readback is never a native/provider receipt.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
from dataclasses import dataclass
from typing import Any, Callable, Protocol

SCHEMA = 'SALY_NATIVE_TRANSPORT_V2'
VALIDATION_SCHEMA = 'SALY_CANONICAL_NATIVE_WIRE_V1'
SHA64 = set('0123456789abcdef')


class CaptureRejected(ValueError):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


def require(ok: bool, code: str) -> None:
    if not ok:
        raise CaptureRejected(code)


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def valid_sha(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and set(value) <= SHA64


def strict_json_bytes(value: dict[str, Any]) -> bytes:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(',', ':'), allow_nan=False).encode('utf-8')
    except (TypeError, ValueError, UnicodeError) as exc:
        raise CaptureRejected('NATIVE_CAPTURE_WIRE_SERIALIZATION_INVALID') from exc


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out = {}
    for key, value in pairs:
        require(key not in out, 'NATIVE_CAPTURE_DUPLICATE_JSON_KEY')
        out[key] = value
    return out


def parse_wire(wire: bytes, require_local_canonical: bool = True) -> dict[str, Any]:
    require(type(wire) is bytes, 'NATIVE_CAPTURE_WIRE_TYPE')
    try:
        parsed = json.loads(wire.decode('utf-8'), object_pairs_hook=reject_duplicate_keys)
    except (UnicodeError, json.JSONDecodeError, ValueError) as exc:
        if isinstance(exc, CaptureRejected):
            raise
        raise CaptureRejected('NATIVE_CAPTURE_BAD_WIRE_JSON') from exc
    require(type(parsed) is dict, 'NATIVE_CAPTURE_WIRE_OBJECT')
    if require_local_canonical:
        require(strict_json_bytes(parsed) == wire, 'NATIVE_CAPTURE_NONCANONICAL_WIRE')
    return parsed


def sealed_envelope(packet: dict[str, Any]) -> dict[str, Any]:
    require(type(packet) is dict, 'NATIVE_CAPTURE_PACKET_TYPE')
    require(packet.get('schema_version') == 'SALY_WORK_PACKET_L2C_V1', 'NATIVE_CAPTURE_PACKET_SCHEMA')
    require(packet.get('readiness_code') == 'READY_FOR_REVIEW_ONLY'
            and packet.get('native_execution_authorized') is False
            and packet.get('image_generation_allowed') is False, 'NATIVE_CAPTURE_AUTHORITY')
    review = packet.get('review_contract')
    require(type(review) is dict and review.get('state') == 'REVIEW_CONTRACT_PREPARED', 'NATIVE_CAPTURE_REVIEW_STATE')
    contract = review.get('contract')
    require(type(contract) is dict and contract.get('qa_verdict') == 'NOT_EVALUATED'
            and contract.get('native_execution_authorized') is False
            and contract.get('image_generation_allowed') is False, 'NATIVE_CAPTURE_QA_AUTHORITY')
    handoff = contract.get('handoff')
    require(type(handoff) is dict and handoff.get('mode') == 'REVIEW_ONLY'
            and handoff.get('transmitted') is False, 'NATIVE_CAPTURE_HANDOFF_STATE')
    envelope = packet.get('native_transport')
    require(type(envelope) is dict and set(envelope) == {
        'schema_version','item_id','contract_sha256','prompt_sha256','payload'
    } and envelope.get('schema_version') == SCHEMA, 'NATIVE_CAPTURE_ENVELOPE_SCHEMA')
    payload = envelope.get('payload')
    require(type(payload) is dict and set(payload) == {'prompt','attachments'}, 'NATIVE_CAPTURE_PAYLOAD_SHAPE')
    require(type(payload.get('prompt')) is str and payload['prompt'].strip() != ''
            and type(payload.get('attachments')) is list, 'NATIVE_CAPTURE_PAYLOAD_FIELDS')
    require(type(envelope.get('item_id')) is int and envelope['item_id'] > 0
            and envelope['item_id'] == packet.get('item_id') == handoff.get('item_id'), 'NATIVE_CAPTURE_ITEM_BINDING')
    require(valid_sha(envelope.get('contract_sha256')) and
            envelope['contract_sha256'] == review.get('contract_sha256'), 'NATIVE_CAPTURE_CONTRACT_BINDING')
    require(valid_sha(envelope.get('prompt_sha256')) and
            envelope['prompt_sha256'] == handoff.get('prompt_sha256'), 'NATIVE_CAPTURE_PROMPT_BINDING')
    require(payload['prompt'] == handoff.get('native_prompt') and
            payload['attachments'] == handoff.get('attachments'), 'NATIVE_CAPTURE_PAYLOAD_DRIFT')
    try:
        prompt_bytes = payload['prompt'].encode('utf-8')
    except UnicodeError as exc:
        raise CaptureRejected('NATIVE_CAPTURE_UTF8_INVALID') from exc
    require(sha(prompt_bytes) == envelope['prompt_sha256'], 'NATIVE_CAPTURE_PROMPT_HASH')
    require(type(packet.get('composition_svg_assets')) is dict, 'NATIVE_CAPTURE_ASSET_SNAPSHOT_MISSING')
    return envelope


class CaptureSink(Protocol):
    """Local, non-provider sink; must return the exact bytes actually received."""
    def capture(self, request_id: str, wire: bytes) -> bytes: ...


@dataclass(frozen=True)
class LocalCapture:
    request_id: str
    item_id: int
    wire_sha256: str
    payload_sha256: str
    prompt_sha256: str
    contract_sha256: str
    captured_bytes: int
    status: str = 'LOCAL_READBACK_MATCH_REVIEW_ONLY'
    provider_receipt: None = None
    transmitted_to_native: bool = False
    native_execution_authorized: bool = False
    image_generation_allowed: bool = False
    qa_verdict: str = 'NOT_EVALUATED'


def capture_review_only(packet: dict[str, Any],
                        db_preflight: Callable[[dict[str, Any]], dict[str, Any]],
                        sink: CaptureSink, request_id: str,
                        used_request_ids: set[str]) -> LocalCapture:
    """A real service-role preflight can be injected; a local fake proves only local flow."""
    envelope = sealed_envelope(packet)
    require(type(request_id) is str and 1 <= len(request_id) <= 128 and request_id.strip() == request_id,
            'NATIVE_CAPTURE_REQUEST_ID')
    require(request_id not in used_request_ids, 'NATIVE_CAPTURE_REPLAY')
    # First check JSON encodability. The DB owns the authoritative wire bytes.
    strict_json_bytes(envelope['payload'])
    receipt = db_preflight(envelope)
    require(type(receipt) is dict and receipt.get('schema_version') == VALIDATION_SCHEMA
            and receipt.get('status') == 'CANONICAL_WIRE_REVIEW_ONLY'
            and receipt.get('item_id') == envelope['item_id']
            and receipt.get('prompt_sha256') == envelope['prompt_sha256']
            and receipt.get('contract_sha256') == envelope['contract_sha256']
            and receipt.get('native_transmitted') is False
            and receipt.get('qa_verdict') == 'NOT_EVALUATED'
            and receipt.get('provider_receipt') is None, 'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH')
    require(valid_sha(receipt.get('wire_sha256')) and
            receipt.get('payload_sha256') == receipt.get('wire_sha256') and
            type(receipt.get('wire_base64')) is str,
            'NATIVE_CAPTURE_DB_WIRE_FIELDS')
    try:
        wire = base64.b64decode(receipt['wire_base64'], validate=True)
    except (ValueError, binascii.Error) as exc:
        raise CaptureRejected('NATIVE_CAPTURE_DB_WIRE_BASE64') from exc
    require(sha(wire) == receipt['wire_sha256'], 'NATIVE_CAPTURE_DB_WIRE_HASH')
    require(parse_wire(wire, require_local_canonical=False) == envelope['payload'],
            'NATIVE_CAPTURE_DB_WIRE_PAYLOAD_DRIFT')
    # Avoid a false 'delivered' state if the sink cannot return its *actual* readback.
    readback = sink.capture(request_id, wire)
    require(type(readback) is bytes and readback == wire, 'NATIVE_CAPTURE_RECEIVER_BYTES_DRIFT')
    require(parse_wire(readback, require_local_canonical=False) == envelope['payload'], 'NATIVE_CAPTURE_RECEIVER_PAYLOAD_DRIFT')
    used_request_ids.add(request_id)
    return LocalCapture(request_id=request_id,item_id=envelope['item_id'],
                        wire_sha256=sha(wire),payload_sha256=receipt['payload_sha256'],
                        prompt_sha256=envelope['prompt_sha256'],
                        contract_sha256=envelope['contract_sha256'],
                        captured_bytes=len(wire))


def validate_provider_ack(*_args: Any, **_kwargs: Any) -> None:
    """No verified provider callback adapter exists. Fail closed, including for forged JSON receipts."""
    raise CaptureRejected('NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE')
