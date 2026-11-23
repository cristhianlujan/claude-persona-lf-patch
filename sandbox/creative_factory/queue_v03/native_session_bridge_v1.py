"""SALY candidate bridge to GPT_NATIVE / CLAUDE_NATIVE in the owning chat.

No API dispatch, synthetic provider/host attestation, runtime grant or DB write.
Source input is an immutable SQL canonical wire and a pre-dispatch archive.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
from collections.abc import Mapping
from typing import Any

PROVIDERS = {"GPT_NATIVE": "OPENAI_CHATGPT_NATIVE",
             "CLAUDE_NATIVE": "ANTHROPIC_CLAUDE_NATIVE"}


class NativeBridgeRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def need(ok: bool, code: str) -> None:
    if not ok:
        raise NativeBridgeRejected(code)


def hash256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def valid_hash(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def prepare_native_session_cursor(*, executor: Mapping[str, Any],
                                  canonical_wire: Mapping[str, Any],
                                  archive: Mapping[str, Any],
                                  binding: Mapping[str, Any]) -> dict[str, Any]:
    """Pure source-bound PLAN cursor. It NEVER sends or permits rendering.

    Native model must continue in its *current* session. No RUN/claim may be
    claimed at PLAN_ONLY. A governed render contract is a separate future stage.
    """
    need(all(isinstance(x, Mapping) for x in (executor, canonical_wire, archive, binding)),
         "CREATIVE_NATIVE_INPUT_SHAPE")
    mode = executor.get('mode')
    need(type(mode) is str and mode in PROVIDERS, 'CREATIVE_NATIVE_MODE_INVALID')
    need(executor.get('provider_identity') == PROVIDERS[mode], 'CREATIVE_NATIVE_PROVIDER_MODE_MISMATCH')
    need(executor.get('conversation_scope') == 'EXISTING_CONVERSATION_ONLY'
         and executor.get('native_api_invocation') is False
         and executor.get('native_session_creation') is False
         and executor.get('remote_api_fallback') == 'FORBIDDEN'
         and executor.get('host_execution') == 'FORBIDDEN',
         'CREATIVE_NATIVE_SESSION_TRANSPORT_INVALID')
    need(executor.get('provider_attested') is False,
         'CREATIVE_NATIVE_PROVIDER_ATTESTATION_FORGED')
    need(type(binding.get('order_id')) is int and binding['order_id'] > 0
         and type(binding.get('item_id')) is int and binding['item_id'] > 0
         and binding.get('run_id') is None and binding.get('claim_id') is None,
         'CREATIVE_NATIVE_PLAN_BINDING_INVALID')
    # Review-only is NOT a render authority; this cursor is a planning handoff.
    need(binding.get('render_authorized') is False
         and binding.get('review_only') is True,
         'CREATIVE_NATIVE_PLAN_AUTHORITY_MISMATCH')
    need(canonical_wire.get('schema_version') == 'SALY_CANONICAL_NATIVE_WIRE_V1'
         and canonical_wire.get('status') == 'CANONICAL_WIRE_REVIEW_ONLY'
         and canonical_wire.get('item_id') == binding['item_id']
         and canonical_wire.get('render_authorized') is False
         and canonical_wire.get('native_transmitted') is False,
         'CREATIVE_NATIVE_CANONICAL_WIRE_INVALID')
    encoded = canonical_wire.get('wire_base64')
    need(type(encoded) is str and len(encoded) > 0, 'CREATIVE_NATIVE_WIRE_BASE64_MISSING')
    try:
        wire = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise NativeBridgeRejected('CREATIVE_NATIVE_WIRE_BASE64_INVALID') from exc
    need(valid_hash(canonical_wire.get('wire_sha256'))
         and hash256(wire) == canonical_wire['wire_sha256'],
         'CREATIVE_NATIVE_WIRE_HASH_MISMATCH')
    try:
        payload = json.loads(wire.decode('utf-8'), object_pairs_hook=_reject_duplicates)
    except NativeBridgeRejected:
        raise
    except (ValueError, UnicodeError) as exc:
        raise NativeBridgeRejected('CREATIVE_NATIVE_WIRE_JSON_INVALID') from exc
    need(type(payload) is dict and set(payload) == {'prompt', 'attachments'}
         and type(payload['prompt']) is str and bool(payload['prompt'].strip())
         and type(payload['attachments']) is list,
         'CREATIVE_NATIVE_PAYLOAD_INVALID')
    need(valid_hash(canonical_wire.get('prompt_sha256'))
         and hash256(payload['prompt'].encode('utf-8')) == canonical_wire['prompt_sha256'],
         'CREATIVE_NATIVE_PROMPT_HASH_MISMATCH')
    need(archive.get('status') == 'HANDOFF_PREPARED_NOT_SENT'
         and archive.get('invocation_recorded') is False
         and archive.get('provider_receipt') is None
         and archive.get('reception_status') == 'NOT_SENT'
         and archive.get('production_approved') is False
         and archive.get('payload_sha256') == canonical_wire['wire_sha256']
         and archive.get('prompt_sha256') == canonical_wire['prompt_sha256'],
         'CREATIVE_NATIVE_PREDISPATCH_ARCHIVE_MISMATCH')
    need(valid_hash(binding.get('prompt_sha256'))
         and binding['prompt_sha256'] == canonical_wire['prompt_sha256'],
         'CREATIVE_NATIVE_RUN_PROMPT_DRIFT')
    return {
        'schema_version': 'SALY_CREATIVE_NATIVE_SESSION_CURSOR_V1',
        'status': 'NATIVE_PLAN_INPUT_PREPARED_NOT_SENT',
        'executor_mode': mode, 'executor_provider': PROVIDERS[mode],
        'continuation_target': 'CURRENT_' + mode + '_CONVERSATION',
        'order_id': binding['order_id'], 'run_id': None, 'claim_id': None,
        'item_id': binding['item_id'], 'wire_sha256': canonical_wire['wire_sha256'],
        'prompt_sha256': canonical_wire['prompt_sha256'],
        'native_transmitted': False, 'image_generation_allowed': False,
        'production_authorized': False, 'provider_attested': False,
        'host_delivery_verified': False, 'db_done_allowed': False,
        'next_action': 'REQUIRE_GOVERNED_CREATIVE_RENDER_AUTHORITY',
    }


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out = {}
    for k, v in pairs:
        if k in out:
            raise NativeBridgeRejected('CREATIVE_NATIVE_DUPLICATE_WIRE_KEY')
        out[k] = v
    return out


def classify_native_chat_artifact(*, cursor: Mapping[str, Any],
                                  image_bytes: bytes, report: Mapping[str, Any]) -> dict[str, Any]:
    """Classifies chat-local material; never emits a trusted provider/host receipt.

    A model or file asserting 'generated' is not an attested delivery callback.
    """
    need(isinstance(cursor, Mapping) and isinstance(report, Mapping),
         'CREATIVE_NATIVE_ARTIFACT_INPUT_INVALID')
    need(cursor.get('schema_version') == 'SALY_CREATIVE_NATIVE_SESSION_CURSOR_V1'
         and cursor.get('status') == 'NATIVE_PLAN_INPUT_PREPARED_NOT_SENT'
         and cursor.get('native_transmitted') is False,
         'CREATIVE_NATIVE_CURSOR_UNTRUSTED')
    need(type(image_bytes) is bytes and bool(image_bytes),
         'CREATIVE_NATIVE_ARTIFACT_BYTES_REQUIRED')
    need(report.get('order_id') == cursor.get('order_id')
         and report.get('item_id') == cursor.get('item_id')
         and report.get('run_id') is None and report.get('claim_id') is None,
         'CREATIVE_NATIVE_ARTIFACT_BINDING_MISMATCH')
    need(valid_hash(report.get('image_sha256'))
         and report['image_sha256'] == hash256(image_bytes),
         'CREATIVE_NATIVE_ARTIFACT_HASH_MISMATCH')
    return {
        'schema_version': 'SALY_CREATIVE_NATIVE_CHAT_LOCAL_EVIDENCE_V1',
        'status': 'LOCAL_ARTIFACT_HASH_VERIFIED_NO_DELIVERY_ATTESTATION',
        'order_id': cursor['order_id'], 'run_id': None, 'claim_id': None,
        'item_id': cursor['item_id'], 'image_sha256': hash256(image_bytes),
        'assurance_level': 'NATIVE_CHAT_LOCAL_EQUIVALENT_NOT_PROVIDER_ATTESTED',
        'provider_attested': False, 'host_delivery_verified': False,
        'production_authorized': False, 'db_done_allowed': False,
    }
