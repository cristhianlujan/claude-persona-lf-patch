"""Regression of the existing OIDC batch transport adapter.

Simulation of the transport response is NOT a production OIDC attestation.
"""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_evolution_oidc_recorder_v02 import make_oidc_profile_evolution_recorder, METHOD

RECEIPT = "37db027e-ad58-4cbb-b4dc-01b7568f6ac2"
EXEC = "EXEC-PE10-V02-TEST-ONLY"
HEAD = "b" * 40


def positive_packet(packet):
    assert packet["action"] == "profile_operation_record_batch_v1"
    assert packet["execution_id"] == EXEC
    assert [x["step_id"] for x in packet["steps"]] == ["method_selection", "evolution_decision"]
    return {"outcome": "BATCH_RECORDED", "execution_id": EXEC,
            "recorded_count": 2, "requested_count": 2,
            "blocked_step_id": None, "caller": {"method": METHOD},
            "receipts": [
                {"step_id": x["step_id"], "outcome": "STEP_RECORDED",
                 "operation_code": "ACTUALIZACION_PERFIL_LF",
                 "result": {"result": {"status": "STEP_PASS_WITH_EVIDENCE"}}}
                for x in packet["steps"]]}


class OidcAdapterTests(unittest.TestCase):
    def setUp(self):
        self.methods = {"profile_assessment_receipt_id": RECEIPT,
                        "source_head_sha": HEAD, "method_execution_permitted": False}
        self.decision = {"profile_assessment_receipt_id": RECEIPT,
                         "source_head_sha": HEAD, "github_write_permitted": False}

    def test_valid_existing_oidc_batch(self):
        runner = make_oidc_profile_evolution_recorder(positive_packet)
        result = runner(EXEC, self.methods, self.decision)
        self.assertEqual(result["method_selection"], "STEP_PASS_WITH_EVIDENCE")
        self.assertEqual(result["evolution_decision"], "STEP_PASS_WITH_EVIDENCE")

    def test_reject_untrusted_receipt(self):
        m = dict(self.methods, profile_assessment_receipt_id="fixture://not-trusted")
        d = dict(self.decision, profile_assessment_receipt_id="fixture://not-trusted")
        with self.assertRaisesRegex(ValueError, "OIDC_EVIDENCE_RECEIPT_INVALID"):
            make_oidc_profile_evolution_recorder(positive_packet)(EXEC, m, d)

    def test_reject_mismatched_assessment(self):
        d = dict(self.decision, profile_assessment_receipt_id=str("0"*8+"-0000-0000-0000-000000000000"))
        with self.assertRaisesRegex(ValueError, "OIDC_ASSESSMENT_SOURCE_NOT_IDENTICAL"):
            make_oidc_profile_evolution_recorder(positive_packet)(EXEC, self.methods, d)

    def test_reject_false_write_permission(self):
        d = dict(self.decision, github_write_permitted=True)
        with self.assertRaisesRegex(ValueError, "OIDC_DECISION_UNAUTHORIZED_WRITE"):
            make_oidc_profile_evolution_recorder(positive_packet)(EXEC, self.methods, d)

    def test_reject_caller_spoof(self):
        def spoof(packet):
            r = positive_packet(packet)
            r["caller"]["method"] = "UNAUTHORIZED"
            return r
        with self.assertRaisesRegex(ValueError, "OIDC_PROFILE_STEP_BATCH_NOT_RECORDED"):
            make_oidc_profile_evolution_recorder(spoof)(EXEC, self.methods, self.decision)

    def test_reject_incomplete_batch(self):
        def one_only(packet):
            r = positive_packet(packet)
            r["receipts"] = r["receipts"][:1]
            return r
        with self.assertRaisesRegex(ValueError, "OIDC_PROFILE_STEP_RECEIPTS_INCOMPLETE"):
            make_oidc_profile_evolution_recorder(one_only)(EXEC, self.methods, self.decision)

    def test_reject_blocked_step(self):
        def blocked(packet):
            r = positive_packet(packet)
            r["receipts"][1]["result"]["result"]["status"] = "BLOCKED_STEP_NOT_CLEAN"
            return r
        with self.assertRaisesRegex(ValueError, "OIDC_STEP_NOT_CLEAN"):
            make_oidc_profile_evolution_recorder(blocked)(EXEC, self.methods, self.decision)


if __name__ == "__main__":
    unittest.main()
