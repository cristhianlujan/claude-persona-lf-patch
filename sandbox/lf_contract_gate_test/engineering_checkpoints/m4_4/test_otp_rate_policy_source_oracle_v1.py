#!/usr/bin/env python3
"""Regression for IG's dedicated OTP rate policy oracle (non-decisional)."""
from __future__ import annotations

import copy
import unittest

from otp_rate_policy_source_oracle_v1 import evaluate


def source_case(screen_id: int = 287, run_id: int = 933) -> dict:
    return {
        "run_id": run_id,
        "pantalla_id": screen_id,
        "family_code": "RATE_LIMIT",
        "rule_bindings": [
            {"rule_code": "FIXTURE_CANDIDATE", "category": "rate_limiting",
             "status": "CANDIDATO", "rule_config": {"max_intentos": 10}, "policy": None},
            {"rule_code": "FIXTURE_OTP_RULE", "category": "rate_limiting",
             "status": "VIGENTE",
             "rule_config": {
                 "scope": "por_numero_celular_cross_session",
                 "canonical_rate_policy_code": "FIXTURE_OTP_POLICY",
                 "max_codigos": 5, "ventana_minutos": 60,
                 "phone_key_storage": "HASH_ONLY", "raw_phone_in_logs": "DENY",
                 "reset_on_new_session": False, "enforcement_side": "SERVER",
                 "atomic_enforcement_required": True,
             },
             "policy": {
                 "policy_code": "FIXTURE_OTP_POLICY", "status": "VIGENTE",
                 "resource_code": "CLIENT_OTP_SEND", "scope_key": "PHONE_HASH",
                 "max_requests": 5, "window_seconds": 3600, "burst_limit": 5,
             }},
        ],
    }


class DedicatedOtpRateOracleTests(unittest.TestCase):
    def _run(self, data: dict, screen_id: int = 287) -> dict:
        return evaluate(data, expected_run_id=933, expected_screen_id=screen_id)

    def test_source_consistent_is_not_semantic_pass(self) -> None:
        result = self._run(source_case())
        self.assertEqual(result["status"], "SOURCE_CONSISTENT")
        self.assertFalse(result["semantic_pass_authorized"])
        self.assertFalse(result["runtime_enforcement_verified"])
        self.assertEqual(result["ignored_candidate_count"], 1)

    def test_other_screen_with_no_otp_rule_is_unresolved(self) -> None:
        data = source_case(screen_id=701)
        data["rule_bindings"] = []
        self.assertEqual(self._run(data, 701)["status"], "UNRESOLVED")

    def test_mutation_wrong_max_requests_detected(self) -> None:
        data = source_case()
        data["rule_bindings"][1]["policy"]["max_requests"] = 10
        self.assertIn("MAX_REQUESTS_CONTRADICTS_RULE", self._run(data)["findings"])

    def test_mutation_wrong_window_detected(self) -> None:
        data = source_case()
        data["rule_bindings"][1]["policy"]["window_seconds"] = 600
        self.assertIn("WINDOW_SECONDS_CONTRADICTS_RULE", self._run(data)["findings"])

    def test_missing_policy_does_not_pass(self) -> None:
        data = source_case()
        data["rule_bindings"][1]["policy"] = None
        self.assertEqual(self._run(data)["code"], "CANONICAL_RATE_POLICY_MISSING")

    def test_ambiguous_rule_is_blocked(self) -> None:
        data = source_case()
        data["rule_bindings"].append(copy.deepcopy(data["rule_bindings"][1]))
        self.assertEqual(self._run(data)["code"], "AMBIGUOUS_SCOPED_RATE_RULES")

    def test_screen_rebinding_is_blocked(self) -> None:
        self.assertEqual(self._run(source_case(), 999)["code"], "SOURCE_IDENTITY_MISMATCH")

    def test_candidate_never_becomes_current_authority(self) -> None:
        data = source_case()
        data["rule_bindings"][1]["status"] = "CANDIDATO"
        self.assertEqual(self._run(data)["status"], "UNRESOLVED")

    def test_malformed_source_binding_is_blocked(self) -> None:
        data = source_case()
        data["rule_bindings"].append({"status": "VIGENTE"})
        self.assertEqual(self._run(data)["code"], "RULE_BINDING_MALFORMED")

    def test_another_screen_not_hardcoded(self) -> None:
        data = source_case(screen_id=821)
        self.assertEqual(self._run(data, 821)["status"], "SOURCE_CONSISTENT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
