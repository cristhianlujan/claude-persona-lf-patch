"""Connect existing art-direction preflight and compositor through a real local handoff.
Only technical candidate review. No Native payload, provider call, or semantic approval.
"""
import io
import json
from pathlib import Path

from PIL import Image
from art_direction_preflight_v1 import preflight, ArtBlocked
from compositor_core_v1 import compose, digest, CompositionError
from compositor_blueprint_layers_v2 import canonical, SCHEMA

REQUEST = 'CREATIVE_SKILL_BLUEPRINT_REVIEW_V2'


def require(ok, code):
    if not ok:
        raise CompositionError(code)


def strict_pairs(pairs):
    obj = {}
    for key, value in pairs:
        require(key not in obj, 'BLUEPRINT_DUPLICATE_JSON_KEY')
        obj[key] = value
    return obj


def read_pinned(path, expected, limit):
    p = Path(path)
    require(p.is_file() and not p.is_symlink() and p.stat().st_size <= limit,
            'BLUEPRINT_INPUT_FILE_INVALID')
    raw = p.read_bytes()
    require(digest(raw) == expected, 'BLUEPRINT_INPUT_HASH_DRIFT')
    return raw


class LocalCompositorReceiver:
    """Actual local receiver, not a stand-in for Native. Keeps the received bytes on failure."""
    def __init__(self):
        self.received = None

    def receive(self, wire, expected_sha, body_bytes):
        self.received = bytes(wire)
        require(digest(self.received) == expected_sha, 'BLUEPRINT_HANDOFF_WIRE_DRIFT')
        obj = json.loads(self.received, object_pairs_hook=strict_pairs)
        require(digest(body_bytes) == obj['body_file_sha256'], 'BLUEPRINT_BODY_WIRE_DRIFT')
        with Image.open(io.BytesIO(body_bytes)) as src:
            require(src.format == 'PNG' and src.width * src.height <= 8_000_000,
                    'BLUEPRINT_BODY_PNG_REQUIRED')
            src.load()
            body = src.copy()
        return compose(obj['manifest'], body)

    def readback(self):
        return self.received


def run_blueprint_review(request, emit):
    """Construct manifest from locked plan. Show -> send -> readback -> QA in one call."""
    receiver = LocalCompositorReceiver()
    wire = None
    base = {'schema_version': REQUEST, 'native_transmitted': False, 'provider_receipt': None,
            'native_payload': None, 'image_generation_allowed': False, 'production_approved': False,
            'semantic_qa': 'NOT_EVALUATED', 'router_invoked': False, 'profile_invoked': False,
            'database_written': False}
    try:
        require(type(request) is dict and set(request) == {'schema_version','mode','business_code',
                'plan_path','plan_sha256','body_path','body_sha256','body_origin','files','output_dir'},
                'BLUEPRINT_REQUEST_FIELDS')
        require(request['schema_version'] == REQUEST and request['mode'] == 'BLUEPRINT_REVIEW_ONLY'
                and request['body_origin'] == 'SYNTHETIC_REVIEW', 'BLUEPRINT_REVIEW_AUTHORITY')
        raw = read_pinned(request['plan_path'], request['plan_sha256'], 2_000_000)
        plan = json.loads(raw, object_pairs_hook=strict_pairs)
        p = preflight(plan)
        require(p['business_code'] == request['business_code'], 'BLUEPRINT_BUSINESS_DRIFT')
        layout = plan['blueprint']['design_lock']['LOCK'].get('composition_layout')
        require(type(layout) is dict and set(layout) == {'canvas','regions','backdrop'},
                'BLUEPRINT_LAYOUT_MISSING')
        body_bytes = read_pinned(request['body_path'], request['body_sha256'], 20_000_000)
        out = Path(request['output_dir'])
        require(not out.exists() and out.parent.is_dir() and not out.parent.is_symlink(),
                'BLUEPRINT_OUTPUT_NOT_NEW')
        manifest = {'schema_version': SCHEMA, 'review_only': True, 'render_authorized': False,
                    'body_origin': 'SYNTHETIC_REVIEW', 'plan': plan,
                    'proposal_sha256': p['proposal_sha256'], 'files': request['files'], **layout}
        wire = canonical({'manifest': manifest, 'body_file_sha256': digest(body_bytes)})
        # Visible intermediate event is mandatory; an exception here prevents invocation.
        emit({'stage':'PREPARED_NOT_SENT','receiver':'LOCAL_COMPOSITOR','wire_sha256':digest(wire),
              'handoff_utf8':wire.decode('utf-8')})
        image, evidence = receiver.receive(wire, digest(wire), body_bytes)
        readback = receiver.readback()
        require(readback == wire, 'BLUEPRINT_RECEIVER_READBACK_DRIFT')
        emit({'stage':'LOCAL_HANDOFF_RECEIVED','wire_sha256':digest(readback), 'receiver':'LOCAL_COMPOSITOR'})
        require(evidence['status'] == 'LOCAL_BLUEPRINT_COMPOSITOR_PASS' and
                evidence['manifest_sha256'] == digest(canonical(manifest)) and
                evidence['proposal_sha256'] == p['proposal_sha256'] and
                evidence['image_sha256'] == digest(image.tobytes()) and
                list(image.size) == manifest['canvas'] and
                evidence['qa_verdict'] == 'NOT_EVALUATED' and
                evidence['native_transmitted'] is False and evidence['production_approved'] is False,
                'BLUEPRINT_TECHNICAL_QA_DRIFT')
        buf = io.BytesIO(); image.save(buf, format='PNG'); png = buf.getvalue()
        with Image.open(io.BytesIO(png)) as check:
            require(check.mode == image.mode and check.size == image.size and check.tobytes() == image.tobytes(),
                    'BLUEPRINT_PNG_READBACK_DRIFT')
        result = dict(base, status='LOCAL_REVIEW_COMPLETE_SEMANTIC_PENDING',
                      business_code=p['business_code'], plan_file_sha256=digest(raw),
                      proposal_sha256=p['proposal_sha256'], local_wire_sha256=digest(wire),
                      local_readback_sha256=digest(readback), technical_qa='PASS_LOCAL',
                      semantic_qa='PENDING_INDEPENDENT_REVIEW', final_delivery_allowed=False,
                      native_handoff='NOT_COMPILED_NOT_SENT', artifact_sha256=digest(png),
                      source_authenticity=p['source_authenticity'], compositor=evidence)
        # A candidate preview is not a final delivery. Exclusively create a new output folder.
        out.mkdir()
        created = []
        try:
            for name, data in (('composition_review.png', png), ('local_handoff.json', wire),
                               ('receipt.json', (json.dumps(result, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))):
                path = out/name
                with path.open('xb') as dst:
                    created.append(path)
                    dst.write(data)
                require(path.read_bytes() == data, 'BLUEPRINT_FILE_READBACK_DRIFT')
        except (OSError, CompositionError):
            for path in reversed(created):
                path.unlink()
            out.rmdir()
            raise
        emit({'stage':'TECHNICAL_QA_COMPLETE','technical_qa':'PASS_LOCAL', 'final_delivery_allowed':False,
              'semantic_qa':'PENDING_INDEPENDENT_REVIEW'})
        return result
    except (ArtBlocked, CompositionError, OSError, ValueError, TypeError, KeyError) as exc:
        received = receiver.readback()  # automatic readback from this attempt, never reconstructed
        code = str(exc) if isinstance(exc, (ArtBlocked, CompositionError)) else 'BLUEPRINT_INPUT_OR_OUTPUT_INVALID'
        result = dict(base, status='BLOCKED', blocking_code=code, final_delivery_allowed=False,
                      local_handoff_status='LOCAL_RECEIVER_READBACK' if received is not None else 'HANDOFF_NOT_SENT',
                      prepared_sha256=digest(wire) if wire is not None else None,
                      received_sha256=digest(received) if received is not None else None)
        emit({'stage':'REJECTION_READBACK','receiver':'LOCAL_COMPOSITOR', **result,
              'received_handoff_utf8':received.decode('utf-8', errors='replace') if received is not None else None})
        return result
