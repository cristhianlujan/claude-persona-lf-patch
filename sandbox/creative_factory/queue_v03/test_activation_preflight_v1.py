"""Offline contract tests. Fake host is *never* evidence of real ChatGPT delivery."""
import copy
import hashlib
import unittest
from datetime import datetime, timezone

from activation_preflight_v1 import (
    REQUIRED_KEYS, DeliveryEvidenceRejected, check_creative_config, verify_delivered_image,
)

AT = datetime(2026, 11, 22, 12, 0, tzinfo=timezone.utc)
PNG = b"\x89PNG\r\n\x1a\nTEST-ONLY-BYTES"
EXPECTED = dict(run_id=12, claim_id=6, item_id=9, artifact_ref="test://artifact/12",
                artifact_sha256=hashlib.sha256(PNG).hexdigest(), recipient_surface="CHATGPT_CHAT")


def config_rows():
    return [dict(scope="CREATIVE_FACTORY", config_key=k, config_value="600",
                 value_status="REAL", value_type="INTEGER", valid_from="2026-11-22T10:00:00+00:00")
            for k in REQUIRED_KEYS]


def generation():
    return dict((k, EXPECTED[k]) for k in ("run_id", "claim_id", "item_id", "artifact_ref", "artifact_sha256")) | {"generation_status": "GENERATED"}


def provider(_):
    return generation()


def receipt(message_id="msg-1"):
    return dict(EXPECTED, message_id=message_id, delivery_status="DELIVERED")


class ContractTests(unittest.TestCase):
    def blocked(self, code, fn):
        with self.assertRaises(DeliveryEvidenceRejected) as e:
            fn()
        self.assertEqual(e.exception.code, code)

    def test_missing_all_live_configs(self):
        x = check_creative_config([], AT)
        self.assertFalse(x["config_contract_valid"])
        self.assertEqual(x["blocking_codes"], ["CREATIVE_CONFIG_MISSING:"+k for k in REQUIRED_KEYS])
        self.assertFalse(x["activation_allowed"])

    def test_valid_fixture_not_runtime_authority(self):
        x = check_creative_config(config_rows(), AT)
        self.assertTrue(x["config_contract_valid"])
        self.assertFalse(x["activation_allowed"])

    def test_missing_value(self):
        rows = [x for x in config_rows() if x["config_key"] != "LEASE_SECONDS"]
        self.assertIn("CREATIVE_CONFIG_MISSING:LEASE_SECONDS", check_creative_config(rows, AT)["blocking_codes"])

    def test_fictitious_value(self):
        rows = config_rows(); rows[0]["value_status"] = "FICTICIO"
        self.assertIn("CREATIVE_CONFIG_INVALID:QUEUE_MAX", check_creative_config(rows, AT)["blocking_codes"])

    def test_wrong_type(self):
        rows = config_rows(); rows[0]["value_type"] = "TEXT"
        self.assertFalse(check_creative_config(rows, AT)["config_contract_valid"])

    def test_non_positive(self):
        rows = config_rows(); rows[0]["config_value"] = "0"
        self.assertFalse(check_creative_config(rows, AT)["config_contract_valid"])

    def test_future_value_ignored(self):
        rows = config_rows(); rows[0]["valid_from"]="2026-11-23T10:00:00+00:00"
        self.assertIn("CREATIVE_CONFIG_MISSING:QUEUE_MAX", check_creative_config(rows, AT)["blocking_codes"])

    def test_latest_invalid_overrides_old(self):
        rows = config_rows(); z=copy.deepcopy(rows[0]); z["valid_from"]="2026-11-22T11:00:00+00:00";z["value_status"]="FICTICIO";rows.append(z)
        self.assertIn("CREATIVE_CONFIG_INVALID:QUEUE_MAX",check_creative_config(rows,AT)["blocking_codes"])

    def test_missing_host_adapter(self):
        self.blocked("CREATIVE_DELIVERY_TRUSTED_ADAPTER_MISSING", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=None,provider_readback=None,artifact_readback=None))

    def test_missing_native_provider(self):
        self.blocked("CREATIVE_DELIVERY_PROVIDER_ATTESTATION_UNAVAILABLE", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _:receipt(),provider_readback=None,artifact_readback=lambda _:PNG))

    def test_unverified_provider(self):
        got=generation(); got["generation_status"]="PENDING"
        self.blocked("CREATIVE_DELIVERY_NATIVE_GENERATION_UNVERIFIED", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _:receipt(),provider_readback=lambda _:got,artifact_readback=lambda _:PNG))

    def test_provider_cross_run(self):
        got=generation(); got["run_id"]=99
        self.blocked("CREATIVE_DELIVERY_PROVIDER_BINDING_MISMATCH:run_id", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _:receipt(),provider_readback=lambda _:got,artifact_readback=lambda _:PNG))

    def test_host_readback_failure(self):
        def bad(_): raise RuntimeError("host down")
        self.blocked("CREATIVE_DELIVERY_HOST_READBACK_FAILED", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=bad,provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_not_delivered(self):
        got=receipt();got["delivery_status"]="QUEUED"
        self.blocked("CREATIVE_DELIVERY_NOT_CONFIRMED", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: got,provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_wrong_message(self):
        self.blocked("CREATIVE_DELIVERY_MESSAGE_MISMATCH", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: receipt("msg-old"),provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_cross_run(self):
        got=receipt();got["run_id"]=99
        self.blocked("CREATIVE_DELIVERY_BINDING_MISMATCH:run_id", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: got,provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_cross_claim(self):
        got=receipt();got["claim_id"]=7
        self.blocked("CREATIVE_DELIVERY_BINDING_MISMATCH:claim_id", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: got,provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_cross_surface(self):
        got=receipt();got["recipient_surface"]="OTHER_CHAT"
        self.blocked("CREATIVE_DELIVERY_BINDING_MISMATCH:recipient_surface", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: got,provider_readback=provider,artifact_readback=lambda _: PNG))

    def test_wrong_image_bytes(self):
        self.blocked("CREATIVE_DELIVERY_ARTIFACT_BYTES_MISMATCH", lambda: verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: receipt(),provider_readback=provider,artifact_readback=lambda _: PNG+b"tamper"))

    def test_positive_synthetic_only(self):
        got=verify_delivered_image(expected=EXPECTED,message_id="msg-1",host_readback=lambda _: receipt(),provider_readback=provider,artifact_readback=lambda _:PNG)
        self.assertEqual(got["receipt_status"],"DELIVERY_READBACK_VERIFIED_BY_INJECTED_HOST")
        self.assertFalse(got["production_authorized"])

    def test_invalid_hash(self):
        fake=dict(EXPECTED,artifact_sha256="bad")
        self.blocked("CREATIVE_DELIVERY_INVALID_ARTIFACT_HASH",lambda:verify_delivered_image(expected=fake,message_id="msg-1",host_readback=lambda _:receipt(),provider_readback=provider,artifact_readback=lambda _:PNG))


if __name__ == "__main__":
    unittest.main(verbosity=2)