"""SALY V11 source-readback and reservation contract tests; ALL fixtures synthetic.

V09 is stubbed HERE to target V11 edge behavior, but the CI workflow also
executes the actual V09 tests separately. No real host, DB, RUN, or Native call.
"""
from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sandbox.creative_factory.queue_v09.dispatch_fence_v1 import DispatchFenceRejected
from sandbox.creative_factory.queue_v11.native_handoff_reservation_bridge_v1 import (
    HandoffReservationRejected, prepare_native_reservation_handoff_v1,
)


def sha(x: bytes) -> str:
    return hashlib.sha256(x).hexdigest()


class Case:
    def __init__(self, mode="GPT_NATIVE"):
        self.tmp = tempfile.TemporaryDirectory(prefix="saly-v11-synthetic-")
        self.parent = Path(self.tmp.name) / "private"
        self.parent.mkdir(mode=0o700)
        self.archive = self.parent / "archived"
        self.archive.mkdir(mode=0o700)
        self.manifest = self.archive / "archive.json"
        self.manifest.write_bytes(b'{"status":"HANDOFF_PREPARED_NOT_SENT"}')
        self.manifest_hash = sha(self.manifest.read_bytes())
        self.mode = mode
        self.provider = ("OPENAI_CHATGPT_NATIVE" if mode == "GPT_NATIVE"
                         else "ANTHROPIC_CLAUDE_NATIVE")
        self.archived = {
            "schema_version":"SALY_NATIVE_RENDER_ARCHIVE_BRIDGE_V1",
            "status":"HANDOFF_ARCHIVED_NOT_SENT",
            "archive_path":str(self.archive),
            "order_id":11,"item_id":12,"run_id":13,"claim_id":14,
            "executor_mode":mode,
            "wire_sha256":sha(b"wire"),"prompt_sha256":sha(b"prompt"),
            "native_transmitted":False,"provider_attested":False,
            "host_delivery_verified":False,"db_done_allowed":False,
        }
        self.executor = {"mode":mode,"provider_identity":self.provider}
        self.requests = []
        self.readback_calls = []
        self.calls = {"gate":0,"claim":0,"reserve":0,"readback":0}
        self.return_replay = False
        self.port_row = {
            "id":15,"order_id":11,"item_id":12,"run_id":13,"claim_id":14,
            "request_key":"V11-SYNTHETIC-A",
            "executor_mode":mode,"executor_provider":self.provider,
            "wire_sha256":sha(b"wire"),"prompt_sha256":sha(b"prompt"),
            "archive_reported_sha256":self.manifest_hash,
            "state":"RESERVED_NOT_DISPATCHED","input_snapshot_sha256":sha(b"snapshot"),
        }
        self.claim_credential={"order_id":11,"item_id":12,"run_id":13,
                               "claim_id":14,"claim_token":"private-v11-token"}
        self.fake_receipt=None

    def close(self): self.tmp.cleanup()

    def gate(self, **kw):
        self.calls["gate"]+=1
        return {
            "schema_version":"SALY_NATIVE_DISPATCH_FENCE_V1",
            "status":"FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT",
            "order_id":11,"item_id":12,"run_id":13,"claim_id":14,
            "wire_sha256":sha(b"wire"),
            "native_transmitted":False,"provider_attested":False,
            "host_delivery_verified":False,"db_done_allowed":False,
        }

    def claim(self, run_id):
        self.calls["claim"]+=1
        if run_id != 13: raise ValueError("wrong RUN")
        return self.claim_credential

    def reserve(self, token, run_id, mode, wire_hash, archive_hash, key):
        self.calls["reserve"]+=1
        self.requests.append((token,run_id,mode,wire_hash,archive_hash,key))
        if self.fake_receipt is not None:
            return self.fake_receipt
        return {
            "schema_version":"SALY_NATIVE_DISPATCH_RESERVATION_V1",
            "status":("ALREADY_RESERVED_NOT_DISPATCHED" if self.return_replay
                      else "RESERVED_NOT_DISPATCHED"),
            "reservation_id":15,"run_id":13,"claim_id":14,
            "native_transmitted":False,"provider_attested":False,
            "host_delivery_verified":False,"db_done_allowed":False,
            "dispatch_authorized":False,
        }

    def readback(self, res_id):
        self.calls["readback"]+=1
        self.readback_calls.append(res_id)
        return self.port_row

    def call(self, **change):
        kw = {
            "archived":self.archived, "executor":self.executor,
            "request_key":"V11-SYNTHETIC-A",
            "db_clock_reader":lambda:None,
            "policy_reader":lambda t:{},
            "binding_reader":lambda run:{},
            "render_wire_reader":lambda item,run:{},
            "claim_credential_reader":self.claim,
            "reserve_dispatch":self.reserve,
            "reservation_readback":self.readback,
        }
        kw.update(change)
        with patch("sandbox.creative_factory.queue_v11.native_handoff_reservation_bridge_v1.verify_dispatch_fence_v1",
                   side_effect=self.gate):
            return prepare_native_reservation_handoff_v1(**kw)


class V11Tests(unittest.TestCase):
    def setUp(self):
        self.c=Case()
        self.addCleanup(self.c.close)

    def rejected(self, code, fn=lambda c:None, **overrides):
        fn(self.c)
        with self.assertRaises(HandoffReservationRejected) as err:
            self.c.call(**overrides)
        self.assertEqual(err.exception.code, code)

    def test_normal_records_intent_but_never_native(self):
        r=self.c.call()
        self.assertEqual(r["status"],"RESERVATION_READBACK_VERIFIED_NOT_SENT")
        self.assertEqual(r["reservation_id"],15)
        self.assertEqual(self.c.calls, {"gate":1,"claim":1,"reserve":1,"readback":1})
        self.assertEqual(self.c.requests[0],(
            "private-v11-token",13,"GPT_NATIVE",sha(b"wire"),
            self.c.manifest_hash,"V11-SYNTHETIC-A"))
        self.assertNotIn("claim_token",r)
        self.assertFalse(r["dispatch_authorized"])
        for k in ("native_transmitted","provider_attested","host_delivery_verified","db_done_allowed"):
            self.assertFalse(r[k])

    def test_claude_native_has_distinct_provider(self):
        c=Case("CLAUDE_NATIVE")
        self.addCleanup(c.close)
        out=c.call()
        self.assertEqual(out["executor_mode"],"CLAUDE_NATIVE")
        self.assertEqual(c.requests[0][2],"CLAUDE_NATIVE")

    def test_idempotent_replay_stays_no_send(self):
        self.c.return_replay=True
        out=self.c.call()
        self.assertEqual(out["status"],"IDEMPOTENT_RESERVATION_READBACK_NOT_SENT")
        self.assertTrue(out["reservation_replay"])
        self.assertFalse(out["dispatch_authorized"])

    def test_missing_credential_reader(self):
        self.rejected("SALY_V11_TRUSTED_PORT_MISSING",claim_credential_reader=None)
        self.assertEqual(self.c.calls["reserve"],0)

    def test_missing_reservation_reader(self):
        self.rejected("SALY_V11_TRUSTED_PORT_MISSING",reservation_readback=None)

    def test_invalid_request_key(self):
        self.rejected("SALY_V11_REQUEST_KEY_INVALID",request_key="../unsafe")
        self.assertEqual(self.c.calls["gate"],0)

    def test_invalid_executor_provider(self):
        self.rejected("SALY_V11_MODE_OR_PROVIDER_MISMATCH",
                      lambda c:c.executor.update(provider_identity="untrusted"))
        self.assertEqual(self.c.calls["reserve"],0)

    def test_credential_wrong_claim(self):
        self.rejected("SALY_V11_CLAIM_CREDENTIAL_NOT_BOUND",
                      lambda c:c.claim_credential.update(claim_id=999))
        self.assertEqual(self.c.calls["reserve"],0)

    def test_credential_missing_token(self):
        self.rejected("SALY_V11_CLAIM_CREDENTIAL_NOT_BOUND",
                      lambda c:c.claim_credential.update(claim_token=" "))

    def test_reservation_report_foreign_run(self):
        self.c.fake_receipt=self.c.reserve("",13,"GPT_NATIVE","",self.c.manifest_hash,"")
        self.c.calls["reserve"]=0
        self.c.fake_receipt["run_id"]=999
        self.rejected("SALY_V11_RESERVATION_RECEIPT_INVALID")

    def test_reservation_report_false_delivery(self):
        self.c.fake_receipt=self.c.reserve("",13,"GPT_NATIVE","",self.c.manifest_hash,"")
        self.c.calls["reserve"]=0
        self.c.fake_receipt["native_transmitted"]=True
        self.rejected("SALY_V11_RESERVATION_RECEIPT_INVALID")

    def test_reservation_report_false_authority(self):
        self.c.fake_receipt=self.c.reserve("",13,"GPT_NATIVE","",self.c.manifest_hash,"")
        self.c.calls["reserve"]=0
        self.c.fake_receipt["dispatch_authorized"]=True
        self.rejected("SALY_V11_RESERVATION_RECEIPT_INVALID")

    def test_reservation_readback_wrong_archive_hash(self):
        self.rejected("SALY_V11_RESERVATION_READBACK_DRIFT",
                      lambda c:c.port_row.update(archive_reported_sha256="a"*64))

    def test_reservation_readback_wrong_mode(self):
        self.rejected("SALY_V11_RESERVATION_READBACK_DRIFT",
                      lambda c:c.port_row.update(executor_mode="CLAUDE_NATIVE"))

    def test_reservation_readback_wrong_request_key(self):
        self.rejected("SALY_V11_RESERVATION_READBACK_DRIFT",
                      lambda c:c.port_row.update(request_key="different"))

    def test_reservation_readback_state_delivered_is_rejected(self):
        self.rejected("SALY_V11_RESERVATION_READBACK_DRIFT",
                      lambda c:c.port_row.update(state="DELIVERED"))

    def test_reservation_readback_wrong_snapshot_pin(self):
        self.rejected("SALY_V11_SNAPSHOT_PIN_INVALID",
                      lambda c:c.port_row.update(input_snapshot_sha256="bad"))

    def test_credential_reader_exception_is_blocking(self):
        self.rejected("SALY_V11_CLAIM_CREDENTIAL_READ_FAILED",
                      claim_credential_reader=lambda _:(1/0))
        self.assertEqual(self.c.calls["reserve"],0)

    def test_reservation_port_exception_is_blocking(self):
        self.rejected("SALY_V11_DB_RESERVATION_FAILED",
                      reserve_dispatch=lambda *args:(1/0))

    def test_readback_port_exception_is_blocking(self):
        self.rejected("SALY_V11_RESERVATION_READBACK_FAILED",
                      reservation_readback=lambda _:(1/0))

    def test_v09_gate_rejection_never_reserves(self):
        def deny(**kw):
            raise DispatchFenceRejected("SALY_DISPATCH_LIVE_CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED")
        self.c.gate=deny
        self.rejected("SALY_V11_V09_SALY_DISPATCH_LIVE_CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED")
        self.assertEqual(self.c.calls["reserve"],0)

    def test_archive_change_during_v09_blocks_reserve(self):
        original=self.c.gate
        def mutate(**kw):
            out=original(**kw)
            self.c.manifest.write_bytes(b'{"status":"changed"}')
            return out
        self.c.gate=mutate
        self.rejected("SALY_V11_ARCHIVE_CHANGED_DURING_PREFLIGHT")
        self.assertEqual(self.c.calls["reserve"],0)

    def test_archive_change_after_reserve_blocks_result(self):
        old=self.c.reserve
        def mutate(*args):
            out=old(*args)
            self.c.manifest.write_bytes(b'{"status":"changed-after-reserve"}')
            return out
        self.c.reserve=mutate
        self.rejected("SALY_V11_ARCHIVE_CHANGED_AFTER_RESERVATION")
        self.assertEqual(self.c.calls["reserve"],1)

    def test_forged_v09_false_delivery_rejected(self):
        original=self.c.gate
        self.c.gate=lambda **kw:{**original(**kw),"host_delivery_verified":True}
        self.rejected("SALY_V11_PREFLIGHT_FALSE_AUTHORITY")

    def test_forged_v09_identity_rejected(self):
        original=self.c.gate
        self.c.gate=lambda **kw:{**original(**kw),"claim_id":100}
        self.rejected("SALY_V11_PREFLIGHT_BINDING_MISMATCH")

    def test_v09_false_wire_pin_rejected(self):
        original=self.c.gate
        self.c.gate=lambda **kw:{**original(**kw),"wire_sha256":"b"*64}
        self.rejected("SALY_V11_WIRE_PIN_MISMATCH")


if __name__ == "__main__":
    unittest.main(verbosity=2)
