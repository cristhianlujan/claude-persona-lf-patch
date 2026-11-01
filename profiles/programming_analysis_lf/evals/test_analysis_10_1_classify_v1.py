#!/usr/bin/env python3
"""Unit tests for bounded, provisional 10.1 classification."""
from hashlib import sha256
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "analysis_101", Path(__file__).resolve().parents[1] / "validators"
    / "analysis_10_1_classify_v1.py"
)
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


def request(intent="CREATE", literal="Programar el login B2B LF"):
    return {
        "business": "LF",
        "execution_id": "EXEC-ANALYSIS-CANDIDATE-TEST",
        "literal_request": literal,
        "request_sha256": sha256(literal.encode("utf-8")).hexdigest(),
        "intent_kind": intent,
        "intent_evidence_refs": ["router-handoff://candidate-test", "user-request://candidate-test"],
    }


class DevelopmentEntryTests(unittest.TestCase):
    def blocked(self, x, code):
        r=M.classify(x)
        self.assertEqual(r["status"],"BLOCKED",r)
        self.assertIn(code,r["blocking_codes"])
        self.assertFalse(r["programming_authorized"] if "programming_authorized" in r else False)

    def test_01_new_login_rules_may_exist_without_verified_code(self):
        r=M.classify(request())
        self.assertEqual(r["development_class"],"NEW_CANDIDATE")
        self.assertEqual(r["implementation_state"],"UNVERIFIED_PENDING_10_4")
        self.assertEqual(r["authority_state"],"UNVERIFIED_PENDING_10_2")
        self.assertEqual(r["business"],"LF")
        self.assertFalse(r["programming_authorized"])
        self.assertFalse(r["persisted"])

    def test_02_extend_existing_capability(self):
        r=M.classify(request("EVOLVE","Ampliar la API ya existente"))
        self.assertEqual(r["development_class"],"EXISTING_EVOLUTION_CANDIDATE")

    def test_03_partial_reuse_plus_new_modules(self):
        r=M.classify(request("COMBINE","Ampliar módulo existente y construir flujo nuevo"))
        self.assertEqual(r["development_class"],"MIXED_CANDIDATE")

    def test_04_repair_returns_to_router(self):
        r=M.classify(request("REPAIR","Login falla al autenticar"))
        self.assertEqual(r["development_class"],"REPAIR_HANDOFF")
        self.assertEqual(r["next_action"],"RETURN_TO_ROUTER")
        self.assertFalse(r["programming_authorized"])

    def test_05_unknown_intent_does_not_invent_category(self):
        r=M.classify(request("UNKNOWN","Necesito login"))
        self.assertEqual(r["development_class"],"NEED_MORE_EVIDENCE")
        self.assertEqual(r["next_action"],"CLARIFY_INTENT")

    def test_06_explicit_lf_required(self):
        x=request(); del x["business"]
        self.blocked(x,"LF_BUSINESS_BINDING_REQUIRED")

    def test_07_saly_cannot_reuse_lf_binding(self):
        x=request(); x["business"]="SALY"
        self.blocked(x,"LF_BUSINESS_BINDING_REQUIRED")

    def test_08_tampered_literal_hash_blocks(self):
        x=request(); x["literal_request"]+=" modificado"
        self.blocked(x,"REQUEST_LITERAL_HASH_MISMATCH")

    def test_09_missing_run_blocks(self):
        x=request(); x["execution_id"]=""
        self.blocked(x,"RUN_ID_MISSING")

    def test_10_no_source_refs_blocks(self):
        x=request(); x["intent_evidence_refs"]=[]
        self.blocked(x,"INTENT_EVIDENCE_REFS_INVALID")

    def test_11_duplicated_refs_blocks(self):
        x=request(); x["intent_evidence_refs"]=["ref-a","ref-a"]
        self.blocked(x,"INTENT_EVIDENCE_REFS_INVALID")

    def test_12_invalid_typed_intent_blocks(self):
        x=request(); x["intent_kind"]="BUILD_NEW_NO_CODE"
        self.blocked(x,"INTENT_KIND_NOT_CANONICAL")

    def test_13_no_empty_literal(self):
        x=request(literal="   ")
        self.blocked(x,"LITERAL_REQUEST_MISSING")

    def test_14_no_keyword_heuristic_override(self):
        x=request("EVOLVE","Login B2B nuevo: indicación explícita de extender un componente existente")
        r=M.classify(x)
        self.assertEqual(r["development_class"],"EXISTING_EVOLUTION_CANDIDATE")
        self.assertEqual(r["classification_authority"],"NOT_ATTESTED")

    def test_15_same_literal_different_intent_has_distinct_provisional_outcome(self):
        a=M.classify(request("CREATE"))
        b=M.classify(request("EVOLVE"))
        self.assertNotEqual(a["development_class"],b["development_class"])
        self.assertEqual(a["request_sha256"],b["request_sha256"])
        self.assertFalse(a["operationally_verified"])

    def test_16_non_object_blocks(self):
        self.blocked(None,"INPUT_NOT_OBJECT")


    def test_17_unhashable_intent_fails_closed(self):
        x=request(); x["intent_kind"]=[]
        self.blocked(x,"INTENT_KIND_NOT_CANONICAL")

    def test_18_invalid_input_never_grants_write(self):
        r=M.classify(None)
        self.assertIs(r.get("programming_authorized"),False)
        x=request(); x["business"]="SALY"
        self.assertIs(M.classify(x).get("programming_authorized"),False)


if __name__=="__main__":
    unittest.main(verbosity=2)
