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
    require(type(request_id) is str and 1 <= len(request_id) <= 128
            and request_id.isascii() and request_id[0].isalnum()
            and all(c.isalnum() or c in '._:-' for c in request_id),
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
            and receipt.get('render_authorized') is False
            and receipt.get('native_transmitted') is False
            and receipt.get('qa_verdict') == 'NOT_EVALUATED'
            and 'provider_receipt' in receipt
            and receipt['provider_receipt'] is None, 'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH')
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


def archive_pre_dispatch(wire, reference_files, protected_assets, output_dir):
    """Save exact intended payload and actual assets before a tool call, not a receipt.

    protected_assets: {component: {'path': local_path, 'sha256': source_pin,
                                   'source_ref': registered_ref}}.
    The caller must obtain pins from the authoritative business adapter.
    This function cannot authorize or invoke an external tool.
    """
    import os
    import tempfile
    from pathlib import Path

    payload = parse_wire(wire, require_local_canonical=False)
    require(set(payload) == {'prompt', 'attachments'} and isinstance(payload['prompt'], str)
            and bool(payload['prompt'].strip()) and isinstance(payload['attachments'], list),
            'NATIVE_ARCHIVE_PAYLOAD')
    require(type(reference_files) is dict and type(protected_assets) is dict, 'NATIVE_ARCHIVE_FILES')
    snapshots = {'payload.json': wire, 'prompt.txt': payload['prompt'].encode('utf-8')}
    references = []
    names = set()
    for entry in payload['attachments']:
        require(type(entry) is dict and isinstance(entry.get('filename'), str)
                and entry['filename'] and Path(entry['filename']).name == entry['filename']
                and entry['filename'] not in ('.', '..') and entry['filename'] not in names,
                'NATIVE_ARCHIVE_ATTACHMENT_NAME')
        name = entry['filename']; names.add(name)
        require(name in reference_files and valid_sha(entry.get('sha256')), 'NATIVE_ARCHIVE_ATTACHMENT_PIN')
        path = Path(reference_files[name])
        require(path.is_file() and not path.is_symlink(), 'NATIVE_ARCHIVE_ATTACHMENT_FILE')
        data = path.read_bytes()
        require(sha(data) == entry['sha256'], 'NATIVE_ARCHIVE_ATTACHMENT_DRIFT')
        snapshots['references/' + name] = data
        references.append({'filename': name, 'sha256': sha(data), 'bytes': len(data)})
    require(names == set(reference_files), 'NATIVE_ARCHIVE_ATTACHMENT_SET')
    fixed = []
    for component, pin in sorted(protected_assets.items()):
        require(type(component) is str and component and type(pin) is dict
                and set(pin) == {'path', 'sha256', 'source_ref'} and valid_sha(pin['sha256'])
                and isinstance(pin['source_ref'], str) and pin['source_ref'].strip(), 'NATIVE_ARCHIVE_PROTECTED_PIN')
        path = Path(pin['path'])
        require(path.is_file() and not path.is_symlink(), 'NATIVE_ARCHIVE_PROTECTED_FILE')
        data = path.read_bytes()
        require(sha(data) == pin['sha256'], 'NATIVE_ARCHIVE_PROTECTED_DRIFT')
        name = 'protected/asset_' + str(len(fixed) + 1)
        snapshots[name] = data
        fixed.append({'component': component, 'source_ref': pin['source_ref'], 'file': name,
                      'sha256': sha(data), 'bytes': len(data)})
    receipt = {'status': 'HANDOFF_PREPARED_NOT_SENT', 'payload_sha256': sha(wire),
               'prompt_sha256': sha(snapshots['prompt.txt']), 'payload_bytes': len(wire),
               'attachments': references, 'protected_assets': fixed,
               'invocation_recorded': False, 'provider_receipt': None,
               'reception_status': 'NOT_SENT', 'production_approved': False}
    snapshots['archive.json'] = strict_json_bytes(receipt)
    out = Path(output_dir)
    require(out.parent.is_dir() and not out.parent.is_symlink() and not out.exists(), 'NATIVE_ARCHIVE_OUTPUT_EXISTS')
    # Create exclusively: a second attempt must use a new directory. On error remove only own files.
    with tempfile.TemporaryDirectory(prefix='.handoff-stage-', dir=out.parent) as stage:
        root = Path(stage)
        for name, data in snapshots.items():
            dst = root / name; dst.parent.mkdir(parents=True, exist_ok=True)
            with dst.open('xb') as f:
                f.write(data); f.flush(); os.fsync(f.fileno())
            require(dst.read_bytes() == data, 'NATIVE_ARCHIVE_READBACK_DRIFT')
        out.mkdir()
        created = []
        try:
            for name, data in snapshots.items():
                dst = out / name; dst.parent.mkdir(parents=True, exist_ok=True)
                with dst.open('xb') as f:
                    created.append(dst); f.write(data); f.flush(); os.fsync(f.fileno())
                require(dst.read_bytes() == data, 'NATIVE_ARCHIVE_READBACK_DRIFT')
        except (OSError, CaptureRejected):
            for dst in reversed(created): dst.unlink()
            for folder in ('references', 'protected'):
                p = out / folder
                if p.exists(): p.rmdir()
            out.rmdir()
            raise
    return receipt
