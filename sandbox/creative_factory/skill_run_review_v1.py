"""Standalone Creative Factory skill: reviewed composition from a sealed offline packet.

Intentionally does not invoke the Router, profiles, database, model provider or QA approver.
Only the existing SALY adapter is currently registered. Other businesses fail closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Any

from PIL import Image

from adapter_saly_review_v1 import ReviewPacketError, from_packet as saly_from_packet
from compositor_core_v1 import CompositionError, compose
from native_transport_capture_v1 import CaptureRejected, sealed_envelope

SCHEMA = 'CREATIVE_SKILL_STANDALONE_REVIEW_V1'
BUSINESSES = {'SALY': ('SALY_WORK_PACKET_L2C_V1', saly_from_packet)}
SHA_PATTERN = re.compile(r'^[0-9a-f]{64}$')


class SkillBlocked(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def ensure(condition: bool, code: str) -> None:
    if not condition:
        raise SkillBlocked(code)


def hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unique_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        ensure(key not in result, 'SKILL_DUPLICATE_JSON_KEY')
        result[key] = value
    return result


def load_json(path: Path, *, max_bytes: int = 2_000_000) -> tuple[dict[str, Any], str]:
    ensure(path.is_file() and not path.is_symlink(), 'SKILL_SOURCE_NOT_REGULAR_FILE')
    ensure(path.stat().st_size <= max_bytes, 'SKILL_SOURCE_TOO_LARGE')
    raw = path.read_bytes()
    try:
        data = json.loads(raw.decode('utf-8'), object_pairs_hook=unique_keys)
    except (ValueError, UnicodeError) as exc:
        if isinstance(exc, SkillBlocked):
            raise
        raise SkillBlocked('SKILL_SOURCE_JSON_INVALID') from exc
    ensure(type(data) is dict, 'SKILL_SOURCE_JSON_OBJECT_REQUIRED')
    return data, hash_bytes(raw)


def run_review(request: dict[str, Any]) -> dict[str, Any]:
    """Offline test/review only; the request and packet cannot grant production authority."""
    ensure(type(request) is dict and request.get('schema_version') == SCHEMA, 'SKILL_REQUEST_SCHEMA')
    ensure(request.get('mode') == 'COMPOSE_REVIEW_ONLY', 'SKILL_MODE_NOT_AUTHORIZED')
    business = request.get('business_code')
    ensure(type(business) is str and re.fullmatch(r'[A-Z][A-Z0-9_]{1,31}', business) is not None,
           'SKILL_BUSINESS_CODE_INVALID')
    ensure(business in BUSINESSES, 'SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE')
    schema, adapter = BUSINESSES[business]
    required = {'schema_version', 'mode', 'business_code', 'packet_path', 'packet_sha256',
                'logo_path', 'fonts_path', 'body_path', 'output_dir', 'body_origin'}
    ensure(set(request) == required, 'SKILL_REQUEST_FIELDS_INVALID')
    ensure(request.get('body_origin') == 'SYNTHETIC_REVIEW', 'SKILL_BODY_PROVENANCE_NOT_VERIFIED')
    packet_path = Path(request['packet_path'])
    packet, packet_hash = load_json(packet_path)
    ensure(type(request['packet_sha256']) is str and SHA_PATTERN.fullmatch(request['packet_sha256']) is not None,
           'SKILL_PACKET_HASH_INVALID')
    ensure(packet_hash == request['packet_sha256'], 'SKILL_PACKET_BYTES_DRIFT')
    ensure(packet.get('schema_version') == schema, 'SKILL_BUSINESS_PACKET_MISMATCH')
    ensure(packet.get('native_execution_authorized') is False
           and packet.get('image_generation_allowed') is False, 'SKILL_RENDER_AUTHORITY_FORBIDDEN')
    try:
        envelope = sealed_envelope(packet)
    except CaptureRejected as exc:
        raise SkillBlocked('SKILL_NATIVE_CONTRACT_' + exc.code) from exc
    fonts, font_hash = load_json(Path(request['fonts_path']), max_bytes=50_000)
    ensure(type(fonts.get('family')) is str and type(fonts.get('files')) is dict,
           'SKILL_FONT_REGISTRY_INVALID')
    body_path = Path(request['body_path'])
    ensure(body_path.is_file() and not body_path.is_symlink(), 'SKILL_BODY_FILE_MISSING')
    ensure(body_path.stat().st_size <= 20_000_000, 'SKILL_BODY_FILE_TOO_LARGE')
    body_binary = body_path.read_bytes()
    try:
        with Image.open(body_path) as src:
            src.load()
            body = src.copy()
    except (OSError, ValueError) as exc:
        raise SkillBlocked('SKILL_BODY_DECODE_FAILED') from exc
    output = Path(request['output_dir'])
    ensure(not output.exists() and output.parent.is_dir() and not output.parent.is_symlink(),
           'SKILL_OUTPUT_MUST_BE_NEW_DIRECTORY')
    try:
        with tempfile.TemporaryDirectory(prefix='.creative-skill-', dir=output.parent) as tmp:
            stage = Path(tmp)
            # The existing business adapter validates source refs and stages only the pinned SVGs.
            manifest = adapter(packet, request['logo_path'], fonts, stage / 'source_assets')
            image, evidence = compose(manifest, body)
            image2, evidence2 = compose(manifest, body)
            ensure(image.tobytes() == image2.tobytes()
                   and evidence['image_sha256'] == evidence2['image_sha256'],
                   'SKILL_NONDETERMINISTIC_COMPOSITION')
            ensure(evidence.get('status') == 'LOCAL_COMPOSITOR_PASS'
                   and evidence.get('native_transmitted') is False
                   and evidence.get('provider_receipt') is None
                   and evidence.get('production_approved') is False,
                   'SKILL_COMPOSITOR_AUTHORITY_DRIFT')
            outfile = stage / 'composition_review.png'
            image.save(outfile, format='PNG')
            image_sha = hash_bytes(outfile.read_bytes())
            with Image.open(outfile) as check:
                check.load()
                ensure(check.size == image.size and check.convert('RGBA').tobytes() == image.tobytes(),
                       'SKILL_FILE_READBACK_MISMATCH')
            receipt = {
                'schema_version': SCHEMA,
                'status': 'LOCAL_TECHNICAL_REVIEW_PASS',
                'business_code': business,
                'packet_sha256': packet_hash,
                'font_registry_sha256': font_hash,
                'body_sha256': hash_bytes(body_binary),
                'body_origin': 'SYNTHETIC_REVIEW',
                'item_id': envelope['item_id'],
                'contract_sha256': envelope['contract_sha256'],
                'prompt_sha256': envelope['prompt_sha256'],
                'file_sha256': image_sha,
                'image_pixel_sha256': evidence['image_sha256'],
                'source_sha256': evidence['source_sha256'],
                'technical_qa': 'PASS_LOCAL',
                'semantic_qa': 'NOT_EVALUATED',
                'provider_receipt': None,
                'native_transmitted': False,
                'native_execution_authorized': False,
                'image_generation_allowed': False,
                'production_approved': False,
                'router_invoked': False,
                'profile_invoked': False,
                'database_written': False,
                'artifact': 'composition_review.png',
            }
            # Source assets must not escape the staging directory; only vetted deliverables persist.
            (stage / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False,
                                                            sort_keys=True, indent=2) + '\n', encoding='utf-8')
            # Move only output, not the staged SVGs, into the new artifact folder.
            with tempfile.TemporaryDirectory(prefix='.creative-deliver-', dir=output.parent) as delivery:
                dest = Path(delivery)
                (dest / 'composition_review.png').write_bytes(outfile.read_bytes())
                (dest / 'receipt.json').write_bytes((stage / 'receipt.json').read_bytes())
                ensure(not output.exists(), 'SKILL_OUTPUT_RACE')
                os.rename(delivery, output)
            return receipt
    except (ReviewPacketError, CompositionError) as exc:
        raise SkillBlocked(str(exc)) from exc


def main() -> None:
    ap = argparse.ArgumentParser(description='Review-only independent Creative Factory skill')
    ap.add_argument('--request', required=True)
    args = ap.parse_args()
    try:
        request, _ = load_json(Path(args.request), max_bytes=50_000)
        result = run_review(request)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    except SkillBlocked as exc:
        print(json.dumps({'status': 'BLOCKED', 'blocking_code': exc.code,
                          'native_transmitted': False, 'production_approved': False}))
        raise SystemExit(2) from exc


if __name__ == '__main__':
    main()
