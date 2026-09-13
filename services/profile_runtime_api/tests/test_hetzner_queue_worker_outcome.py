from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "hetzner_queue_worker_under_test", SCRIPTS / "hetzner_queue_worker.py"
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
_execution_queue_outcome = MODULE._execution_queue_outcome


def clean_profile() -> dict:
    return {
        "runtime_completion": {"status": "PASS", "blocking_codes": []},
        "profile_contract_valid": {"status": "PASS", "blocking_codes": []},
        "semantic_utility": {
            "status": "PASS",
            "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_NOT_FINAL_SEMANTIC_AUTHORITY",
            "blocking_codes": [],
        },
        "raw_output": {"status": "RETURN_TO_ORCHESTRATOR"},
    }


class HetznerQueueOutcomeTest(unittest.TestCase):
    def test_clean_three_gate_result_succeeds_even_when_payload_returns_to_orchestrator(self) -> None:
        outcome = _execution_queue_outcome(clean_profile())
        self.assertEqual(outcome["status"], "SUCCEEDED")
        self.assertIsNone(outcome["error_code"])

    def test_runtime_failure_blocks(self) -> None:
        profile = clean_profile()
        profile["runtime_completion"] = {
            "status": "FAIL", "blocking_codes": ["LLAMA_STRUCTURED_OUTPUT_JSON_INVALID"]
        }
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "LLAMA_STRUCTURED_OUTPUT_JSON_INVALID")

    def test_contract_failure_blocks_even_when_runtime_passed(self) -> None:
        profile = clean_profile()
        profile["profile_contract_valid"] = {
            "status": "FAIL", "blocking_codes": ["JSON_SCHEMA_VALIDATION_FAILED"]
        }
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "JSON_SCHEMA_VALIDATION_FAILED")

    def test_semantic_utility_failure_blocks_exact_canary_shape(self) -> None:
        profile = clean_profile()
        profile["semantic_utility"] = {
            "status": "FAIL",
            "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_NOT_FINAL_SEMANTIC_AUTHORITY",
            "blocking_codes": [
                "UI_FOCUSED_SIZE_OR_COVERAGE_NON_CONCRETE",
                "UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE",
            ],
        }
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE")
        self.assertIn("gate=semantic_utility", outcome["error_detail"] or "")

    def test_explicit_unbound_utility_policy_preserves_generic_profile_compatibility(self) -> None:
        profile = clean_profile()
        profile["semantic_utility"] = {
            "status": "NOT_EVALUATED",
            "evaluation_scope": "NO_PROFILE_UTILITY_POLICY",
            "blocking_codes": ["SEMANTIC_UTILITY_POLICY_NOT_BOUND"],
        }
        self.assertEqual(_execution_queue_outcome(profile)["status"], "SUCCEEDED")

    def test_unexpected_not_evaluated_is_fail_closed(self) -> None:
        profile = clean_profile()
        profile["semantic_utility"] = {
            "status": "NOT_EVALUATED",
            "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR",
            "blocking_codes": ["PROFILE_CONTRACT_INVALID"],
        }
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "PROFILE_CONTRACT_INVALID")

    def test_pass_with_blocking_code_is_fail_closed(self) -> None:
        profile = clean_profile()
        profile["semantic_utility"]["blocking_codes"] = ["IMPOSSIBLE_PASS_WITH_BLOCKER"]
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "IMPOSSIBLE_PASS_WITH_BLOCKER")

    def test_missing_contract_gate_is_fail_closed(self) -> None:
        profile = clean_profile()
        profile.pop("profile_contract_valid")
        outcome = _execution_queue_outcome(profile)
        self.assertEqual(outcome["status"], "BLOCKED")
        self.assertEqual(outcome["error_code"], "HETZNER_PROFILE_CONTRACT_FAILED_MISSING")


if __name__ == "__main__":
    unittest.main()
