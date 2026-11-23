"""SALY V09: last readback of a pre-dispatch Native archive and live SQL fence.

Candidate only. No call to GPT/Claude, DB writing, delivery attestation or DONE.
The caller MUST own the SQL readers and Native session. A JSON order is not a
trusted source of readers, policy, clock, authority or signed host identity.
"""
from __future__ import annotations

import hashlib
import json
import stat
from collections.abc import Callable, Mapping
from datetime import datetime
from pathlib import Path
from typing import Any

from sandbox.creative_factory.queue_v04.render_ready_gate_v1 import (
    RenderAdmissionRejected, validate_render_ready,
)


class DispatchFenceRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def need(condition: bool, code: str) -> None:
    if not condition:
        raise DispatchFenceRejected(code)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse(data: bytes) -> Any:
    def no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for k, v in pairs:
            need(k not in out, 'SALY_DISPATCH_ARCHIVE_DUPLICATE_JSON_FIELD')
            out[k] = v
        return out
    try:
        return json.loads(data.decode('utf-8'), object_pairs_hook=no_duplicates)
    except DispatchFenceRejected:
        raise
    except (ValueError, UnicodeError) as exc:
        raise DispatchFenceRejected('SALY_DISPATCH_ARCHIVE_JSON_INVALID') from exc


def read_exact(path: Path) -> bytes:
    need(path.is_file() and not path.is_symlink(), 'SALY_DISPATCH_ARCHIVE_FILE_UNSAFE')
    try:
        return path.read_bytes()
    except OSError as exc:
        raise DispatchFenceRejected('SALY_DISPATCH_ARCHIVE_READ_FAILED') from exc


def verify_dispatch_fence_v1(
    *,
    archived: Mapping[str, Any],
    executor: Mapping[str, Any],
    db_clock_reader: Callable[[], datetime] | None,
    policy_reader: Callable[..., Mapping[str, Any]] | None,
    binding_reader: Callable[..., Mapping[str, Any]] | None,
    render_wire_reader: Callable[..., Mapping[str, Any]] | None,
) -> dict[str, Any]:
    """Revalidate SQL authority AFTER archiving; never authorize a tool invocation.

    This validation is advisory outside a serial SQL transaction. A future
    native dispatcher must fence the claim atomically at its actual effect.
    """
    need(isinstance(archived, Mapping)
         and archived.get('schema_version') == 'SALY_NATIVE_RENDER_ARCHIVE_BRIDGE_V1'
         and archived.get('status') == 'HANDOFF_ARCHIVED_NOT_SENT'
         and all(archived.get(k) is False for k in (
             'native_transmitted', 'provider_attested',
             'host_delivery_verified', 'db_done_allowed')),
         'SALY_DISPATCH_ARCHIVE_NOT_PREPARED')
    ids = ('order_id', 'item_id', 'run_id', 'claim_id')
    need(all(type(archived.get(k)) is int and archived[k] > 0 for k in ids),
         'SALY_DISPATCH_ARCHIVE_IDENTIFIERS_INVALID')
    need(all(type(archived.get(k)) is str and len(archived[k]) == 64
             and all(c in '0123456789abcdef' for c in archived[k])
             for k in ('wire_sha256', 'prompt_sha256')),
         'SALY_DISPATCH_ARCHIVE_PINS_INVALID')
    need(type(archived.get('source_count')) is int and archived['source_count'] > 0
         and type(archived.get('protected_component_count')) is int
         and archived['protected_component_count'] >= 0,
         'SALY_DISPATCH_ARCHIVE_COUNTS_INVALID')
    need(isinstance(archived.get('archive_path'), str),
         'SALY_DISPATCH_ARCHIVE_PATH_INVALID')
    root = Path(archived['archive_path'])
    need(root.is_absolute() and root.is_dir() and not root.is_symlink()
         and root.parent.is_dir() and not root.parent.is_symlink()
         and (stat.S_IMODE(root.stat().st_mode) & 0o077) == 0
         and (stat.S_IMODE(root.parent.stat().st_mode) & 0o077) == 0,
         'SALY_DISPATCH_ARCHIVE_PATH_UNSAFE')
    # The canonical archivador omits protected/ entirely when there are zero pins.
    expected_top = {'archive.json', 'payload.json', 'prompt.txt', 'references'}
    if archived['protected_component_count']:
        expected_top.add('protected')
    need({p.name for p in root.iterdir()} == expected_top,
         'SALY_DISPATCH_ARCHIVE_UNEXPECTED_FILE')
    payload = read_exact(root / 'payload.json')
    prompt = read_exact(root / 'prompt.txt')
    receipt = parse(read_exact(root / 'archive.json'))
    body = parse(payload)
    need(type(body) is dict and set(body) == {'prompt', 'attachments'}
         and isinstance(body['prompt'], str)
         and type(body['attachments']) is list,
         'SALY_DISPATCH_ARCHIVE_PAYLOAD_INVALID')
    need(sha(payload) == archived['wire_sha256']
         and sha(prompt) == archived['prompt_sha256']
         and prompt == body['prompt'].encode('utf-8'),
         'SALY_DISPATCH_ARCHIVE_BYTES_DRIFT')
    need(type(receipt) is dict
         and receipt.get('status') == 'HANDOFF_PREPARED_NOT_SENT'
         and receipt.get('provider_receipt') is None
         and receipt.get('invocation_recorded') is False
         and receipt.get('reception_status') == 'NOT_SENT'
         and receipt.get('production_approved') is False
         and receipt.get('payload_sha256') == archived['wire_sha256']
         and receipt.get('prompt_sha256') == archived['prompt_sha256']
         and receipt.get('payload_bytes') == len(payload),
         'SALY_DISPATCH_ARCHIVE_RECEIPT_INVALID')
    entries, recorded = body['attachments'], receipt.get('attachments')
    need(type(recorded) is list and len(recorded) == len(entries)
         and len(entries) == archived['source_count'],
         'SALY_DISPATCH_ARCHIVE_SOURCE_COUNT_DRIFT')
    refs = root / 'references'
    need(refs.is_dir() and not refs.is_symlink(), 'SALY_DISPATCH_ARCHIVE_FILE_UNSAFE')
    filenames = [x.get('filename') for x in entries if type(x) is dict]
    need(len(filenames) == len(entries) and len(set(filenames)) == len(entries)
         and all(type(n) is str and n not in ('.', '..')
                 and Path(n).name == n for n in filenames)
         and {p.name for p in refs.iterdir()} == set(filenames),
         'SALY_DISPATCH_ARCHIVE_SOURCE_SET_DRIFT')
    for i, ent in enumerate(entries):
        data = read_exact(refs / ent['filename'])
        pin = recorded[i]
        need(type(pin) is dict and pin.get('filename') == ent['filename']
             and pin.get('sha256') == ent.get('sha256')
             and pin.get('bytes') == len(data)
             and sha(data) == ent.get('sha256'),
             'SALY_DISPATCH_ARCHIVE_SOURCE_BYTES_DRIFT')
    fixed = receipt.get('protected_assets')
    need(type(fixed) is list and len(fixed) == archived['protected_component_count'],
         'SALY_DISPATCH_ARCHIVE_PROTECTED_COUNT_DRIFT')
    protected = root / 'protected'
    if fixed:
        need(protected.is_dir() and not protected.is_symlink()
             and {p.name for p in protected.iterdir()} == {
                 'asset_' + str(i + 1) for i in range(len(fixed))},
             'SALY_DISPATCH_ARCHIVE_PROTECTED_SET_DRIFT')
    for i, pin in enumerate(fixed):
        need(type(pin) is dict and pin.get('file') == 'protected/asset_' + str(i + 1)
             and isinstance(pin.get('source_ref'), str) and bool(pin['source_ref']),
             'SALY_DISPATCH_ARCHIVE_PROTECTED_RECEIPT_INVALID')
        data = read_exact(protected / ('asset_' + str(i + 1)))
        need(pin.get('bytes') == len(data) and pin.get('sha256') == sha(data),
             'SALY_DISPATCH_ARCHIVE_PROTECTED_BYTES_DRIFT')

    # Fresh DB clock and authority readback must be LAST, after all local IO.
    need(callable(db_clock_reader) and callable(policy_reader)
         and callable(binding_reader) and callable(render_wire_reader),
         'SALY_DISPATCH_TRUSTED_SQL_PORT_MISSING')
    try:
        now = db_clock_reader()
    except Exception as exc:
        raise DispatchFenceRejected('SALY_DISPATCH_DB_CLOCK_UNAVAILABLE') from exc
    need(type(now) is datetime and now.tzinfo is not None,
         'SALY_DISPATCH_DB_CLOCK_INVALID')
    try:
        current = validate_render_ready(
            order_id=archived['order_id'], item_id=archived['item_id'],
            run_id=archived['run_id'], asof=now, executor=executor,
            policy_reader=policy_reader, binding_reader=binding_reader,
            render_wire_reader=render_wire_reader,
        )
    except RenderAdmissionRejected as exc:
        raise DispatchFenceRejected('SALY_DISPATCH_LIVE_' + exc.code) from exc
    need(current['status'] == 'RENDER_READY_CANDIDATE_VALIDATED_NOT_DISPATCHED'
         and current['claim_id'] == archived['claim_id']
         and current['executor_mode'] == archived['executor_mode']
         and current['wire_sha256'] == archived['wire_sha256']
         and current['prompt_sha256'] == archived['prompt_sha256'],
         'SALY_DISPATCH_LIVE_BINDING_OR_WIRE_DRIFT')
    return {
        'schema_version': 'SALY_NATIVE_DISPATCH_FENCE_V1',
        'status': 'FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT',
        **{k: archived[k] for k in ids},
        'wire_sha256': archived['wire_sha256'],
        'source_count': archived['source_count'],
        'native_transmitted': False,
        'provider_attested': False,
        'host_delivery_verified': False,
        'db_done_allowed': False,
        'next_action': 'BLOCKED_UNTIL_REAL_NATIVE_HOST_DISPATCH_AND_TRUSTED_ATTESTOR',
    }
