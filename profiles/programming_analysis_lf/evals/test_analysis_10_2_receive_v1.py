#!/usr/bin/env python3
"""Synthetic contract verification. NO real-run or Supabase transport claim."""
import copy
from hashlib import sha256
import importlib.util
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1] / "validators"


def load(file, module):
    spec = importlib.util.spec_from_file_location(module, BASE / file)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


A1 = load("analysis_10_1_classify_v1.py", "step_101")
A2 = load("analysis_10_2_receive_v1.py", "step_102")


def fixture():
    literal = "Programar login B2B de LF a partir de definiciones canónicas"
    req_sha = sha256(literal.encode("utf8")).hexdigest()
    run = {"execution_id": "EXEC-FIXTURE-ANALYSIS-102", "request_sha256": req_sha,
           "business": "LF", "status": "IN_PROGRESS",
           "operation_code": "EJECUCION_PERFIL_LF",
           "profile_code": "PERFIL-PROGRAMMING-ANALYSIS-LF"}
    previous = A1.classify({
        "business": "LF", "execution_id": run["execution_id"],
        "literal_request": literal, "request_sha256": req_sha,
        "intent_kind": "CREATE",
        "intent_evidence_refs": ["fixture://original", "fixture://router"],
    })
    transfer = {"from_step": "10.1", "to_step": "10.2",
                "sender_payload_sha256": A2.digest(previous),
                "execution_id": run["execution_id"], "request_sha256": req_sha,
                "business": "LF", "target_code": "B2B-AUTH-001"}
    sources = {"status": "FOUND", "business": "LF", "source_namespace": "lf_ops",
               "target_type": "SCREEN", "target_code": "B2B-AUTH-001",
               "screen_id": 51, "screen_status": "CANDIDATO", "screen_version": "v0.5",
               "screen_source_ref": "fixture://lf_ops.pantallas/51",
               "rule_relation_source_ref": "fixture://lf_ops.reglas_pantallas/51",
               "rule_count": 71, "resolved_by": "FIXTURE_AUTHORITY_ADAPTER",
               "source_receipt_ref": "fixture://source-observation"}
    return previous, run, transfer, sources


class SourceReceiveTests(unittest.TestCase):
    def bad(self, p, run, transport, sources, code):
        result = A2.receive(p, run, transport, sources)
        self.assertEqual(result["status"], "BLOCKED", result)
        self.assertIn(code, result["blocking_codes"])
        self.assertFalse(result["persisted"])
        self.assertFalse(result["operationally_verified"])

    def test_01_new_login_source_found_but_not_approved(self):
        p, r, t, s = fixture()
        output = A2.receive(p, r, t, s)
        self.assertEqual(output["status"], "RECEIVED_CANDIDATE")
        self.assertEqual(output["screen_id"], 51)
        self.assertEqual(output["definition_status"], "CANDIDATO")
        self.assertEqual(output["source_currentness"], "NOT_ATTESTED")
        self.assertEqual(output["next_action"], "10.3")
        self.assertFalse(output["persisted"])
        self.assertFalse(output["programming_authorized"])

    def test_02_10_1_digest_tampered(self):
        p, r, t, s = fixture()
        t["sender_payload_sha256"] = "0"*64
        self.bad(p, r, t, s, "10_1_TO_10_2_TRANSPORT_MISMATCH")

    def test_03_10_1_output_tampered_after_transport(self):
        p, r, t, s = fixture()
        p["development_class"] = "MIXED_CANDIDATE"
        self.bad(p, r, t, s, "10_1_TO_10_2_TRANSPORT_MISMATCH")

    def test_04_cross_business_saly_source(self):
        p, r, t, s = fixture()
        s["business"] = "SALY"
        self.bad(p, r, t, s, "CROSS_BUSINESS_SOURCE_FORBIDDEN")

    def test_05_cross_schema_saly_tables(self):
        p, r, t, s = fixture()
        s["source_namespace"] = "saly"
        self.bad(p, r, t, s, "CROSS_BUSINESS_SOURCE_FORBIDDEN")

    def test_06_wrong_target_screen(self):
        p, r, t, s = fixture()
        s["target_code"] = "B2B-AUTH-002"
        self.bad(p, r, t, s, "TARGET_NOT_EXACTLY_RESOLVED")

    def test_07_unknown_or_unresolved_source(self):
        p, r, t, s = fixture()
        s["status"] = "NOT_FOUND"
        self.bad(p, r, t, s, "SOURCE_NOT_FOUND_OR_UNRESOLVED")

    def test_08_wrong_run_id(self):
        p, r, t, s = fixture()
        t["execution_id"] = "EXEC-OTHER"
        self.bad(p, r, t, s, "EXECUTION_OR_REQUEST_DRIFT")

    def test_09_wrong_input_hash(self):
        p, r, t, s = fixture()
        t["request_sha256"] = "1"*64
        self.bad(p, r, t, s, "EXECUTION_OR_REQUEST_DRIFT")

    def test_10_missing_run(self):
        p, r, t, s = fixture()
        self.bad(p, {}, t, s, "CANONICAL_RUN_MISSING")

    def test_11_no_source_receipt(self):
        p, r, t, s = fixture()
        s.pop("source_receipt_ref")
        self.bad(p, r, t, s, "SOURCE_READBACK_FIELD_MISSING")

    def test_12_no_10_1_eligibility(self):
        p, r, t, s = fixture()
        p["status"] = "BLOCKED"
        t["sender_payload_sha256"] = A2.digest(p)
        self.bad(p, r, t, s, "10_1_NOT_ELIGIBLE")

    def test_13_wrong_profile(self):
        p, r, t, s = fixture()
        r["profile_code"] = "PERFIL-PRODUCT-DIRECTOR-LF"
        self.bad(p, r, t, s, "WRONG_RUN_OWNER")

    def test_14_duplicate_screen_id_type(self):
        p, r, t, s = fixture()
        s["screen_id"] = True
        self.bad(p, r, t, s, "SCREEN_ID_INVALID")

    def test_15_wrong_business_from_router(self):
        p, r, t, s = fixture()
        t["business"] = "SALY"
        self.bad(p, r, t, s, "BUSINESS_BINDING_MISMATCH")

    def test_16_expired_run(self):
        p, r, t, s = fixture()
        r["status"] = "COMPLETED"
        self.bad(p, r, t, s, "RUN_NOT_IN_PROGRESS")

    def test_17_receives_evolution_without_claiming_code_exists(self):
        p, r, t, s = fixture()
        p["development_class"] = "EXISTING_EVOLUTION_CANDIDATE"
        p["intent_kind"] = "EVOLVE"
        t["sender_payload_sha256"] = A2.digest(p)
        v = A2.receive(p, r, t, s)
        self.assertEqual(v["status"], "RECEIVED_CANDIDATE")
        self.assertEqual(v["implementation_state"], "UNVERIFIED_PENDING_10_4")


if __name__ == "__main__":
    unittest.main(verbosity=2)
