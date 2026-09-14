#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from lf_ekb_preflight_validator_v1 import resolve

HERE = Path(__file__).resolve().parent
BASE = json.loads((HERE / "first_real_case_20260914.json").read_text(encoding="utf-8"))


class EKBPreflightValidatorV1Test(unittest.TestCase):
    def test_first_real_case_resolves_but_does_not_fake_pass(self) -> None:
        result = resolve(copy.deepcopy(BASE))
        self.assertEqual("EKB_RESOLVED_CONTROLS_PENDING", result["result"])
        self.assertFalse(result["pass"])
        self.assertEqual(BASE["expected_selected_codes"], result["matched_error_codes"])
        self.assertIn("GOV-CI-MIGRATION-SOURCE-PARITY-20260829", result["required_control_codes"])
        self.assertTrue(result["detectability_is_not_execution_evidence"])

    def test_context_matching_is_case_insensitive_but_not_fuzzy(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["lifecycle_phases"] = ["ci_source_parity"]
        payload["consumer_roles"] = ["governance"]
        payload["required_codes"] = []
        payload["control_coverage"]["bindings"] = [
            row for row in payload["control_coverage"]["bindings"]
            if row["error_code"] in {
                "CI-MIGRATION-SOURCE-PARITY-001",
                "GOV-CI-MIGRATION-SOURCE-PARITY-20260829",
            }
        ]
        result = resolve(payload)
        self.assertEqual(
            ["CI-MIGRATION-SOURCE-PARITY-001", "GOV-CI-MIGRATION-SOURCE-PARITY-20260829"],
            result["matched_error_codes"],
        )

        payload["consumer_roles"] = ["govern"]
        payload["control_coverage"]["bindings"] = []
        result = resolve(payload)
        self.assertEqual([], result["matched_error_codes"])

    def test_explicit_required_code_must_exist(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["required_codes"].append("DOES-NOT-EXIST")
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_REQUIRED_CODE_MISSING", result["result"])
        self.assertIn("DOES-NOT-EXIST", result["missing_required_codes"])

    def test_duplicate_active_error_code_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["errors"].append(copy.deepcopy(payload["errors"][0]))
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_DUPLICATE_ACTIVE_CODE", result["result"])

    def test_legacy_rule_can_cover_missing_inline_prevention(self) -> None:
        payload = copy.deepcopy(BASE)
        row = next(x for x in payload["errors"] if x["codigo"] == "GOV-001")
        row["has_inline_prevention"] = False
        result = resolve(payload)
        self.assertNotEqual("BLOCK_EKB_UNHANDLED_HIGH_CRITICAL", result["result"])
        self.assertEqual(["PRV-GOV-001"], result["inherited_active_rules"]["GOV-001"])

    def test_high_error_without_inline_or_rule_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        row = next(x for x in payload["errors"] if x["codigo"] == "GOV-001")
        row["has_inline_prevention"] = False
        payload["active_rule_codes_by_error"].pop("GOV-001")
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_UNHANDLED_HIGH_CRITICAL", result["result"])
        self.assertIn("GOV-001", result["unhandled_high_critical_codes"])

    def test_missing_control_binding_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["control_coverage"]["bindings"] = [
            row for row in payload["control_coverage"]["bindings"]
            if row["error_code"] != "AUD-018"
        ]
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_CONTROL_COVERAGE_INCOMPLETE", result["result"])
        self.assertIn("AUD-018", result["missing_control_bindings"])

    def test_unknown_control_binding_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["control_coverage"]["bindings"].append({
            "error_code": "FOREIGN-CODE",
            "control_mode": "DETERMINISTIC_CHECK",
            "control_ref": "foreign",
            "status": "PENDING",
            "evidence_ref": None,
            "executed": False,
        })
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_CONTROL_COVERAGE_INCOMPLETE", result["result"])
        self.assertIn("FOREIGN-CODE", result["unknown_control_bindings"])

    def test_declarative_pass_without_execution_evidence_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        for binding in payload["control_coverage"]["bindings"]:
            binding["status"] = "PASS"
        result = resolve(payload)
        self.assertEqual("BLOCK_EKB_CONTROL_EVIDENCE_INVALID", result["result"])
        self.assertIn("AUD-018", result["control_evidence_failures"])

    def test_executed_evidence_can_pass(self) -> None:
        payload = copy.deepcopy(BASE)
        for idx, binding in enumerate(payload["control_coverage"]["bindings"], start=1):
            binding.update({
                "status": "PASS",
                "executed": True,
                "evidence_ref": f"evidence://test/{idx}",
                "evidence_sha256": f"{idx:064x}"[-64:],
            })
        result = resolve(payload)
        self.assertEqual("PASS_EKB_PREFLIGHT_CONTROLS_BOUND", result["result"])
        self.assertTrue(result["pass"])

    def test_human_review_required_is_not_pass(self) -> None:
        payload = copy.deepcopy(BASE)
        for idx, binding in enumerate(payload["control_coverage"]["bindings"], start=1):
            binding.update({
                "status": "PASS",
                "executed": True,
                "evidence_ref": f"evidence://test/{idx}",
                "evidence_sha256": f"{idx:064x}"[-64:],
            })
        target = payload["control_coverage"]["bindings"][0]
        target.update({"control_mode":"HUMAN_REVIEW","status":"REVIEW_REQUIRED","executed":False,"evidence_ref":None,"evidence_sha256":None})
        result = resolve(payload)
        self.assertEqual("EKB_RESOLVED_CONTROLS_PENDING", result["result"])
        self.assertFalse(result["pass"])


if __name__ == "__main__":
    unittest.main()
