"""V09 negative archive/fence tests with synthetic bytes and mocked live readback.

Does NOT test a deployed SQL policy, real GPT/Claude invocation or real delivery.
"""
from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from sandbox.creative_factory.queue_v04.render_ready_gate_v1 import RenderAdmissionRejected
from sandbox.creative_factory.queue_v09.dispatch_fence_v1 import (
    DispatchFenceRejected, verify_dispatch_fence_v1,
)


def sha(x: bytes) -> str:
    return hashlib.sha256(x).hexdigest()


class TestDispatchFence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'private'
        self.root.mkdir(mode=0o700)
        self.arc = self.root / 'archive'
        self.arc.mkdir(mode=0o700)
        (self.arc / 'references').mkdir(mode=0o700)
        self.src = b'not-a-real-image-synthetic-source'
        self.body = {'prompt': 'SALY Prueba sin envio.', 'attachments': [
            {'filename':'sample.png', 'sha256':sha(self.src)}]}
        self.payload = json.dumps(self.body, ensure_ascii=False,
                                  separators=(',', ':')).encode()
        (self.arc / 'payload.json').write_bytes(self.payload)
        (self.arc / 'prompt.txt').write_bytes(self.body['prompt'].encode())
        (self.arc / 'references' / 'sample.png').write_bytes(self.src)
        self.receipt = {
            'status': 'HANDOFF_PREPARED_NOT_SENT',
            'provider_receipt': None, 'invocation_recorded': False,
            'reception_status': 'NOT_SENT', 'production_approved': False,
            'payload_sha256': sha(self.payload),
            'prompt_sha256': sha(self.body['prompt'].encode()),
            'payload_bytes': len(self.payload),
            'attachments': [{'filename':'sample.png','sha256':sha(self.src),
                             'bytes':len(self.src)}], 'protected_assets': [],
        }
        self.save_receipt()
        self.archived = {
            'schema_version': 'SALY_NATIVE_RENDER_ARCHIVE_BRIDGE_V1',
            'status': 'HANDOFF_ARCHIVED_NOT_SENT', 'order_id':1, 'item_id':2,
            'run_id':3, 'claim_id':4, 'executor_mode':'GPT_NATIVE',
            'wire_sha256':sha(self.payload),
            'prompt_sha256':sha(self.body['prompt'].encode()),
            'source_count':1, 'protected_component_count':0,
            'archive_path':str(self.arc),
            'native_transmitted':False, 'provider_attested':False,
            'host_delivery_verified':False, 'db_done_allowed':False,
        }
        self.calls = 0
        self.fake_ready = self.ready
        self.clock = lambda: datetime(2026, 11, 22, 15, 0, tzinfo=timezone.utc)

    def save_receipt(self):
        (self.arc / 'archive.json').write_bytes(json.dumps(self.receipt).encode())

    def ready(self, **kwargs):
        self.calls += 1
        self.assertEqual(kwargs['run_id'], 3)
        return {'status':'RENDER_READY_CANDIDATE_VALIDATED_NOT_DISPATCHED',
                'claim_id':4, 'executor_mode':'GPT_NATIVE',
                'wire_sha256':sha(self.payload),
                'prompt_sha256':sha(self.body['prompt'].encode())}

    def call(self, **changes):
        opts = {'archived':self.archived,
                'executor': {'mode':'GPT_NATIVE'},
                'db_clock_reader':self.clock,
                'policy_reader':lambda _: {},
                'binding_reader':lambda _: {},
                'render_wire_reader':lambda _a,_b: {}}
        opts.update(changes)
        with patch('sandbox.creative_factory.queue_v09.dispatch_fence_v1.validate_render_ready',
                   side_effect=self.fake_ready):
            return verify_dispatch_fence_v1(**opts)

    def reject(self, code, **changes):
        with self.assertRaises(DispatchFenceRejected) as ctx:
            self.call(**changes)
        self.assertEqual(ctx.exception.code, code)

    def test_positive_is_never_dispatch_or_done(self):
        x = self.call()
        self.assertEqual(x['status'], 'FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT')
        for key in ('native_transmitted','provider_attested','host_delivery_verified','db_done_allowed'):
            self.assertIs(x[key], False)
        self.assertEqual(self.calls, 1)
        self.assertNotIn('claim_token', x)

    def test_fake_done_archive_rejected(self):
        self.archived['db_done_allowed'] = True
        self.reject('SALY_DISPATCH_ARCHIVE_NOT_PREPARED')
        self.assertEqual(self.calls, 0)

    def test_missing_sql_port_rejected(self):
        self.reject('SALY_DISPATCH_TRUSTED_SQL_PORT_MISSING', policy_reader=None)
        self.assertEqual(self.calls, 0)

    def test_sql_clock_unavailable_rejected(self):
        def broken(): raise OSError('network')
        self.reject('SALY_DISPATCH_DB_CLOCK_UNAVAILABLE', db_clock_reader=broken)
        self.assertEqual(self.calls, 0)

    def test_naive_clock_rejected(self):
        self.reject('SALY_DISPATCH_DB_CLOCK_INVALID',
                    db_clock_reader=lambda:datetime(2026,11,22))
        self.assertEqual(self.calls, 0)

    def test_expired_lease_from_real_gate_is_propagated(self):
        self.fake_ready = lambda **kw: (_ for _ in ()).throw(
            RenderAdmissionRejected('CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED'))
        self.reject('SALY_DISPATCH_LIVE_CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED')

    def test_new_claim_binding_rejected(self):
        self.fake_ready = lambda **kw: {**self.ready(**kw), 'claim_id':9}
        self.reject('SALY_DISPATCH_LIVE_BINDING_OR_WIRE_DRIFT')

    def test_wire_hash_replaced_in_db_rejected(self):
        self.fake_ready = lambda **kw: {**self.ready(**kw), 'wire_sha256':'0'*64}
        self.reject('SALY_DISPATCH_LIVE_BINDING_OR_WIRE_DRIFT')

    def test_source_bytes_modified_rejected_before_sql(self):
        (self.arc / 'references' / 'sample.png').write_bytes(b'altered')
        self.reject('SALY_DISPATCH_ARCHIVE_SOURCE_BYTES_DRIFT')
        self.assertEqual(self.calls, 0)

    def test_prompt_modified_rejected(self):
        (self.arc / 'prompt.txt').write_bytes(b'other')
        self.reject('SALY_DISPATCH_ARCHIVE_BYTES_DRIFT')

    def test_archive_receipt_claims_sent_rejected(self):
        self.receipt['reception_status'] = 'DELIVERED'
        self.save_receipt()
        self.reject('SALY_DISPATCH_ARCHIVE_RECEIPT_INVALID')

    def test_unexpected_file_in_archive_rejected(self):
        (self.arc / 'extra.bin').write_bytes(b'x')
        self.reject('SALY_DISPATCH_ARCHIVE_UNEXPECTED_FILE')

    def test_source_symlink_rejected(self):
        (self.arc / 'references' / 'sample.png').unlink()
        (self.arc / 'references' / 'sample.png').symlink_to(self.arc / 'prompt.txt')
        self.reject('SALY_DISPATCH_ARCHIVE_FILE_UNSAFE')

    def test_archive_world_readable_rejected(self):
        os.chmod(self.arc, 0o755)
        self.reject('SALY_DISPATCH_ARCHIVE_PATH_UNSAFE')

    def test_protected_count_tamper_rejected(self):
        self.archived['protected_component_count'] = 1
        self.reject('SALY_DISPATCH_ARCHIVE_UNEXPECTED_FILE')

    def test_valid_protected_asset(self):
        (self.arc / 'protected').mkdir(mode=0o700)
        data = b'synthetic-protected'
        (self.arc / 'protected' / 'asset_1').write_bytes(data)
        self.receipt['protected_assets'] = [{'component':'LOGO',
            'file':'protected/asset_1', 'source_ref':'REGISTERED',
            'sha256':sha(data), 'bytes':len(data)}]
        self.save_receipt()
        self.archived['protected_component_count'] = 1
        self.assertEqual(self.call()['status'], 'FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT')

    def test_duplicate_receipt_json_key_rejected(self):
        text = (self.arc / 'archive.json').read_text()
        (self.arc / 'archive.json').write_text(text[:-1]+',"status":"DELIVERED"}')
        self.reject('SALY_DISPATCH_ARCHIVE_DUPLICATE_JSON_FIELD')

    def test_missing_archive_source_rejected(self):
        (self.arc / 'references' / 'sample.png').unlink()
        self.reject('SALY_DISPATCH_ARCHIVE_SOURCE_SET_DRIFT')


if __name__ == '__main__':
    unittest.main(verbosity=2)
