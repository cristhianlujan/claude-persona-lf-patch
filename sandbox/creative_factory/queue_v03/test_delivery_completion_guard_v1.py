"""Offline simulations; successes here are NOT proof of ChatGPT delivery."""
import copy
import hashlib
import unittest

from activation_preflight_v1 import DeliveryEvidenceRejected
from delivery_completion_guard_v1 import DeliveryPorts, finish_verified_delivery

IMAGE = b"\x89PNG\r\n\x1a\nfixture-not-an-image"
BASE = {
    "run_id": 4, "claim_id": 8, "item_id": 3,
    "claim_token": "synthetic-token", "claim_state": "ACTIVE",
    "run_state": "EXITOSO", "item_status": "APROBADO",
    "artifact_ref": "test://artifact", "artifact_sha256": hashlib.sha256(IMAGE).hexdigest(),
    "recipient_surface": "CHATGPT_CHAT",
}


class Harness:
    def __init__(self):
        self.binding = copy.deepcopy(BASE)
        self.provider = {k: self.binding[k] for k in (
            "run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256")}
        self.provider["generation_status"] = "GENERATED"
        self.host = {k: self.binding[k] for k in (
            "run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256",
            "recipient_surface")}
        self.host.update({"message_id": "host-msg-4", "delivery_status": "DELIVERED"})
        self.image = IMAGE
        self.receipt = None
        self.writes = 0
        self.releases = 0

    def db_read(self, run):
        return copy.deepcopy(self.binding)

    def read_receipt(self, run):
        return copy.deepcopy(self.receipt)

    def record(self, token, run, channel, message):
        self.writes += 1
        self.receipt = {
            "claim_id": self.binding["claim_id"], "run_id": run,
            "artifact_ref": self.binding["artifact_ref"],
            "artifact_sha256": self.binding["artifact_sha256"],
            "delivery_channel": channel, "delivery_receipt": message,
        }
        return {"status": "DELIVERY_RECORDED", "run_id": run}

    def release(self, token):
        self.releases += 1
        return {"status": "RELEASED", "result": "DONE",
                "claim_id": self.binding["claim_id"], "order_closed": True}

    def ports(self):
        return DeliveryPorts(
            claim_readback=self.db_read, provider_readback=lambda _: self.provider,
            host_readback=lambda _: self.host, artifact_readback=lambda _: self.image,
            receipt_readback=self.read_receipt, record_delivery=self.record,
            release_done=self.release,
        )


class CompletionTests(unittest.TestCase):
    def fail(self, h, code, ports=None):
        with self.assertRaises(DeliveryEvidenceRejected) as cm:
            finish_verified_delivery(run_id=4, message_id="host-msg-4", ports=ports or h.ports())
        self.assertEqual(cm.exception.code, code)
        self.assertEqual(h.releases, 0)

    def test_missing_ports(self):
        self.fail(Harness(), "CREATIVE_DELIVERY_TRUSTED_ADAPTER_MISSING", DeliveryPorts())

    def test_missing_provider(self):
        h = Harness(); p=h.ports(); p.provider_readback = None
        self.fail(h, "CREATIVE_DELIVERY_TRUSTED_ADAPTER_MISSING", p)
        self.assertEqual(h.writes, 0)

    def test_qa_blocked(self):
        h = Harness(); h.binding["item_status"] = "EN_QA"
        self.fail(h, "CREATIVE_DELIVERY_RUN_QA_CLAIM_NOT_READY")
        self.assertEqual(h.writes, 0)

    def test_expired_claim(self):
        h = Harness(); h.binding["claim_state"] = "EXPIRED"
        self.fail(h, "CREATIVE_DELIVERY_RUN_QA_CLAIM_NOT_READY")

    def test_wrong_run(self):
        h = Harness(); h.binding["run_id"] = 7
        self.fail(h, "CREATIVE_DELIVERY_DB_BINDING_MISMATCH")

    def test_host_not_delivered(self):
        h = Harness(); h.host["delivery_status"] = "PENDING"
        self.fail(h, "CREATIVE_DELIVERY_NOT_CONFIRMED")
        self.assertEqual(h.writes, 0)

    def test_provider_not_generated(self):
        h = Harness(); h.provider["generation_status"] = "PENDING"
        self.fail(h, "CREATIVE_DELIVERY_NATIVE_GENERATION_UNVERIFIED")
        self.assertEqual(h.writes, 0)

    def test_bytes_tampered(self):
        h = Harness(); h.image = IMAGE+b"tampered"
        self.fail(h, "CREATIVE_DELIVERY_ARTIFACT_BYTES_MISMATCH")
        self.assertEqual(h.writes, 0)

    def test_cross_claim(self):
        h = Harness(); h.host["claim_id"] = 99
        self.fail(h, "CREATIVE_DELIVERY_BINDING_MISMATCH:claim_id")
        self.assertEqual(h.writes, 0)

    def test_receipt_mismatch_blocks_release(self):
        h = Harness(); h.record=lambda *a:{"status":"DELIVERY_RECORDED","run_id":4}
        self.fail(h, "CREATIVE_DELIVERY_DB_RECEIPT_MISMATCH")

    def test_failed_write_blocks_release(self):
        h = Harness()
        def bad(*args): raise OSError("DB down")
        h.record = bad
        self.fail(h, "CREATIVE_DELIVERY_RECORD_FAILED")

    def test_release_failure_is_not_success(self):
        h = Harness()
        def bad(*args): raise OSError("stale lease")
        h.release = bad
        self.fail(h, "CREATIVE_DELIVERY_RELEASE_FAILED")

    def test_positive_synthetic_sequence(self):
        h = Harness()
        result = finish_verified_delivery(run_id=4,message_id="host-msg-4",ports=h.ports())
        self.assertEqual(result["status"], "DB_DONE_AFTER_DUAL_READBACK")
        self.assertFalse(result["production_authorized"])
        self.assertEqual((h.writes,h.releases), (1,1))

    def test_existing_matching_receipt_skips_duplicate_write(self):
        h = Harness()
        h.record("synthetic-token",4,"CHATGPT_CHAT","host-msg-4")
        h.writes = 0
        result = finish_verified_delivery(run_id=4,message_id="host-msg-4",ports=h.ports())
        self.assertEqual(result["status"], "DB_DONE_AFTER_DUAL_READBACK")
        self.assertEqual((h.writes,h.releases), (0,1))

    def test_existing_wrong_receipt_never_overwritten(self):
        h = Harness()
        h.record("synthetic-token",4,"CHATGPT_CHAT","wrong-message")
        h.writes = 0
        self.fail(h, "CREATIVE_DELIVERY_DB_RECEIPT_MISMATCH")
        self.assertEqual(h.writes,0)

    def test_blank_message_rejected(self):
        h=Harness()
        with self.assertRaises(DeliveryEvidenceRejected) as cm:
            finish_verified_delivery(run_id=4,message_id=" ",ports=h.ports())
        self.assertEqual(cm.exception.code, "CREATIVE_DELIVERY_MESSAGE_ID_REQUIRED")
        self.assertEqual(h.writes,0)

    def test_wrong_db_record_response_not_success(self):
        h=Harness();h.record=lambda *a:{"status":"DELIVERY_RECORDED","run_id":9}
        self.fail(h,"CREATIVE_DELIVERY_RECORD_NOT_CONFIRMED")

    def test_wrong_release_claim_not_success(self):
        h=Harness();h.release=lambda *a:{"status":"RELEASED","result":"DONE","claim_id":9}
        self.fail(h,"CREATIVE_DELIVERY_RELEASE_NOT_CONFIRMED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
