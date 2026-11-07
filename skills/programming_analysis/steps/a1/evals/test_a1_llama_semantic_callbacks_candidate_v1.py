"""Test model callback adapter with a MOCK LlamaHTTPClient; NOT live model evidence."""
import importlib.util
import json
import unittest
from pathlib import Path
from test_a1_semantic_candidate_v1 import LOGIN, semantic_candidate, A1

A1_ROOT = Path(__file__).resolve().parents[1]
path = A1_ROOT / "adapters/llama_semantic_callbacks_candidate_v1.py"
spec = importlib.util.spec_from_file_location("llama_a1_callbacks", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeClient:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def chat(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


class ModelCallbacksCandidate(unittest.TestCase):
    def make_clients(self, producer_result=None, reviewer_result=None):
        raw = json.dumps(semantic_candidate(LOGIN), ensure_ascii=False)
        first = FakeClient(producer_result if producer_result is not None else {
            "id": "producer-001", "content": raw
        })
        second = FakeClient(reviewer_result if reviewer_result is not None else {
            "id": "reviewer-001", "content": json.dumps({"verdict": "PASS", "issues": []})
        })
        return first, second

    def test_01_uses_existing_llama_chat_interface_twice(self):
        first, second = self.make_clients()
        producer, reviewer = module.bind_clients(producer_client=first, reviewer_client=second)
        result = A1.run(LOGIN, business="LF", semantic_producer=producer,
                        semantic_reviewer=reviewer)
        self.assertEqual(result["status"], "VALID_OUTPUT", result)
        self.assertEqual(len(first.calls), 1)
        self.assertEqual(len(second.calls), 1)
        self.assertEqual(first.calls[0]["user_prompt"], LOGIN)
        self.assertEqual(second.calls[0]["schema"]["properties"]["verdict"]["enum"],
                         ["PASS", "FAIL"])
        self.assertFalse(result["semantic_review_identity_verified"])

    def test_02_same_client_is_not_a_separate_reviewer(self):
        first, _ = self.make_clients()
        with self.assertRaisesRegex(ValueError, "A1_SEPARATE_MODEL_CLIENTS_REQUIRED"):
            module.bind_clients(producer_client=first, reviewer_client=first)

    def test_03_reviewer_fail_is_not_ready(self):
        first, second = self.make_clients(reviewer_result={
            "id": "reviewer-002",
            "content": json.dumps({"verdict": "FAIL", "issues": ["NEGATION_DROPPED"]})
        })
        producer, reviewer = module.bind_clients(producer_client=first, reviewer_client=second)
        result = A1.run(LOGIN, business="LF", semantic_producer=producer,
                        semantic_reviewer=reviewer)
        self.assertEqual(result["status"], "REQUIRES_SEMANTIC_REVIEW")
        self.assertIsNone(result["next_capability"])

    def test_04_invalid_producer_payload_is_blocked(self):
        first, second = self.make_clients(producer_result={
            "id": "producer-003", "content": "{}"
        })
        producer, reviewer = module.bind_clients(producer_client=first, reviewer_client=second)
        result = A1.run(LOGIN, business="LF", semantic_producer=producer,
                        semantic_reviewer=reviewer)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("SEMANTIC_PRODUCER_FAILED", result["blocking_codes"])
        self.assertEqual(second.calls, [])

    def test_05_missing_response_id_refuses_unverifiable_transport(self):
        first, second = self.make_clients(reviewer_result={
            "id": "", "content": json.dumps({"verdict": "PASS", "issues": []})
        })
        producer, reviewer = module.bind_clients(producer_client=first, reviewer_client=second)
        result = A1.run(LOGIN, business="LF", semantic_producer=producer,
                        semantic_reviewer=reviewer)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("SEMANTIC_REVIEWER_FAILED", result["blocking_codes"])

    def test_06_model_does_not_supply_candidate_digest(self):
        first, second = self.make_clients()
        producer, reviewer = module.bind_clients(producer_client=first, reviewer_client=second)
        result = A1.run(LOGIN, business="LF", semantic_producer=producer,
                        semantic_reviewer=reviewer)
        import hashlib
        normalized = json.dumps(result["intent_analysis"], ensure_ascii=False,
                                sort_keys=True, separators=(",", ":"))
        self.assertEqual(result["semantic_candidate_sha256"],
                         hashlib.sha256(normalized.encode()).hexdigest())


if __name__ == "__main__":
    unittest.main(verbosity=2)
