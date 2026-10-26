import copy
import json
import unittest
from pathlib import Path

from a9_independent_review_adapter_v1 import (
    A9ContractError, CHAT_LEVEL, CAPABILITY_MANIFEST,
    build_subject_anchor_params, build_begin_params, build_blind_review_packet,
    parse_review_verdict, build_a9q_c3_evidence, build_v2_envelope_review_fragment,
    build_semantic_review_step_payload,
)

ROOT = Path(__file__).resolve().parent
CONTRACT = json.loads((ROOT / "programming_analysis_package_review_subject_v1.json").read_text(encoding="utf-8"))
CID = "c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c"
SHA = "1" * 64


def row():
    fields = {f: {"reference": f} for f in CONTRACT["required_snapshot_fields"]}
    return {"context_id": CID, "context_sha256": SHA, "context_payload": {"extensions": {"programming_context_snapshot": fields}, "stage_trace": "SECRET", "producer_execution_id": "EXEC-PRODUCER", "producer_verdict": "PASS"}}


def subject():
    return {"subject_type": "PROGRAMMING_ANALYSIS_PACKAGE", "subject_ref": f"PROGRAMMING_ANALYSIS_PACKAGE/{CID}", "subject_sha256": SHA, "context_sha256": SHA, "context_id": CID, "source_head_sha": "a" * 40, "producer_execution_id": "EXEC-PRODUCER"}


def review_json(packet_hash, statuses=None):
    statuses = statuses or {}
    return json.dumps({"packet_sha256": packet_hash, "dimensions": [{"code": d["code"], "verdict": statuses.get(d["code"], "PASS"), "evidence": ["extensions.programming_context_snapshot." + CONTRACT["required_snapshot_fields"][i]], "reason": "revisión del campo correspondiente"} for i, d in enumerate(CONTRACT["required_dimensions"])]})


class AdapterTests(unittest.TestCase):
    def assert_code(self, code, fn):
        with self.assertRaises(A9ContractError) as cm: fn()
        self.assertEqual(cm.exception.code, code)

    def test_anchor_complete_and_missing(self):
        out = build_subject_anchor_params(row(), "a" * 40, "EXEC-PRODUCER", "EXEC-ACTOR", subject_contract=CONTRACT)
        self.assertEqual(out["p_subject_sha256"], SHA)
        self.assertEqual(out["p_subject_ref"], f"PROGRAMMING_ANALYSIS_PACKAGE/{CID}")
        self.assertIsNone(out["p_verification_state"])
        self.assertEqual((out["p_capability_code"], out["p_receipt_kind"]), ("EVIDENCE_LEDGER", "SOURCE_SNAPSHOT"))
        self.assertEqual((out["p_resolver_id"], out["p_provider"]), ("LF_SUPABASE_READBACK_V1", "SUPABASE"))
        self.assertNotIn("context_payload", out["p_receipt_payload"])
        self.assertNotIn("SECRET", json.dumps(out, ensure_ascii=False))
        bad = row()
        del bad["context_payload"]["extensions"]["programming_context_snapshot"]["requirements"]
        self.assert_code("A9_REVIEW_SUBJECT_INCOMPLETE", lambda: build_subject_anchor_params(bad, "a" * 40, "EXEC-PRODUCER", "EXEC-ACTOR", subject_contract=CONTRACT))

    def test_begin_guards(self):
        plan = {"expected_capability_manifest_sha256": CAPABILITY_MANIFEST, "plan_digest": "plan", "request_sha256": "3"*64, "idempotency_key":"key", "review_scope":"NATIVE_MATERIAL_CONTENT_ONLY"}
        args = lambda s, r, p: build_begin_params(s, "receipt-uuid", r, "EXEC-PRODUCER", p, "dispatch-uuid", "EXEC-ACTOR", subject_contract=CONTRACT)
        self.assert_code("BUILDER_REVIEWER_NOT_INDEPENDENT", lambda: args(subject(), "EXEC-PRODUCER", plan))
        bad_plan = {**plan, "expected_capability_manifest_sha256": "f" * 64}
        self.assert_code("BLOCK_CURRENTNESS_MISMATCH", lambda: args(subject(), "EXEC-REVIEWER", bad_plan))
        result = args(subject(), "EXEC-REVIEWER", plan)
        self.assertFalse(result["p_manifest"]["runtime_activation"])
        self.assertEqual(len(result["p_manifest"]["required_dimensions"]), 7)
        short_head = {**subject(), "source_head_sha": "abc"}
        self.assert_code("SUBJECT_HASH_INVALID", lambda: args(short_head, "EXEC-REVIEWER", plan))
        bad = {**subject(), "subject_sha256": "not-a-hash"}
        self.assert_code("SUBJECT_HASH_INVALID", lambda: args(bad, "EXEC-REVIEWER", plan))

    def test_blind_packet_deterministic(self):
        x = build_blind_review_packet(row()["context_payload"], CONTRACT)
        y = build_blind_review_packet(row()["context_payload"], CONTRACT)
        self.assertEqual(x["packet_sha256"], y["packet_sha256"])
        blob = json.dumps(x["packet"], ensure_ascii=False)
        for banned in ("EXEC-PRODUCER", "stage_trace", "producer_verdict", "producer_execution_id"):
            self.assertNotIn(banned, blob)

    def test_review_verdicts(self):
        ph = "2" * 64
        codes = [d["code"] for d in CONTRACT["required_dimensions"]]
        ok = parse_review_verdict(review_json(ph), ph, CONTRACT)
        self.assertEqual(ok["global_verdict"], "PASS")
        fail = parse_review_verdict(review_json(ph, {codes[0]: "FAIL"}), ph, CONTRACT)
        self.assertEqual(fail["global_verdict"], "RETURN_TO_WORKER")
        unknown = parse_review_verdict(review_json(ph, {codes[0]: "UNKNOWN"}), ph, CONTRACT)
        self.assertEqual(unknown["global_verdict"], "BLOCKED")
        missing = json.loads(review_json(ph)); missing["dimensions"].pop()
        self.assert_code("A9_REVIEW_DIMENSIONS_INVALID", lambda: parse_review_verdict(json.dumps(missing), ph, CONTRACT))
        extra = json.loads(review_json(ph)); extra["dimensions"].append({"code": "EXTRA", "verdict": "PASS", "evidence": ["x"], "reason": "r"})
        self.assert_code("A9_REVIEW_DIMENSIONS_INVALID", lambda: parse_review_verdict(json.dumps(extra), ph, CONTRACT))
        self.assert_code("A9_REVIEW_PACKET_HASH_MISMATCH", lambda: parse_review_verdict(review_json("4"*64), ph, CONTRACT))
        forged = json.loads(review_json(ph)); forged["dimensions"][0]["evidence"] = [{"governed_execution_id": "FAKE"}]
        self.assert_code("FORGED_GOVERNED_FIELD", lambda: parse_review_verdict(json.dumps(forged), ph, CONTRACT))
        without = json.loads(review_json(ph)); without["dimensions"][0]["evidence"] = []
        self.assert_code("A9_REVIEW_PASS_WITHOUT_EVIDENCE", lambda: parse_review_verdict(json.dumps(without), ph, CONTRACT))

    def test_evidence_chat_and_fragment(self):
        r = {"global_verdict":"PASS", "dimensions": json.loads(review_json("2"*64))["dimensions"]}
        ev = build_a9q_c3_evidence(subject=subject(), review=r, reviewer_execution_id="EXEC-REVIEWER", evidence_level=CHAT_LEVEL)
        self.assertFalse(ev["provider_attested"])
        for key in ("evidence_ledger_verified_ref", "governed_execution_id", "router_dispatch_receipt_id", "provider_response_id_attested_by_transport"):
            self.assertIsNone(ev[key])
        fragment = build_v2_envelope_review_fragment(subject=subject(), review=r, reviewer_execution_id="EXEC-REVIEWER", review_verdict_ref=None)
        self.assertEqual(fragment["context_id"], CID)
        self.assertEqual(fragment["context_sha256"], SHA)
        self.assertFalse(fragment["admissible"])

    def test_semantic_review_step_payload(self):
        ph = "2" * 64
        codes = [d["code"] for d in CONTRACT["required_dimensions"]]
        ok = build_semantic_review_step_payload(parse_review_verdict(review_json(ph), ph, CONTRACT), CONTRACT, rationale_summary="todas las dimensiones con evidencia")
        self.assertEqual((ok["verdict"], ok["review_type"], ok["review_context"]), ("PASS", "INDEPENDENT_REVIEW", "INDEPENDENT_OPERATION_CONTEXT"))
        self.assertEqual(ok["utility_dimensions_checked"], codes)
        self.assertTrue(ok["evidence_refs"])
        for status, expected in (("FAIL", "RETURN_TO_WORKER"), ("UNKNOWN", "BLOCKED")):
            r = parse_review_verdict(review_json(ph, {codes[0]: status}), ph, CONTRACT)
            p = build_semantic_review_step_payload(r, CONTRACT, rationale_summary="hallazgo")
            self.assertEqual((p["verdict"], p["a9_global_verdict"]), ("FAIL", expected))
        self.assert_code("A9_REVIEW_VERDICT_INVALID", lambda: build_semantic_review_step_payload({"global_verdict": "MAYBE", "dimensions": []}, CONTRACT, rationale_summary="x"))
        self.assert_code("A9_REVIEW_VERDICT_INVALID", lambda: build_semantic_review_step_payload(parse_review_verdict(review_json(ph), ph, CONTRACT), CONTRACT, rationale_summary=" "))

    def test_anchor_rejects_non_git_head(self):
        self.assert_code("SUBJECT_HASH_INVALID", lambda: build_subject_anchor_params(row(), "main", "EXEC-PRODUCER", "EXEC-ACTOR", subject_contract=CONTRACT))


if __name__ == "__main__":
    unittest.main()
