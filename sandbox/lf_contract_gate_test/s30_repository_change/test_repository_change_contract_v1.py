#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / "LF_REPOSITORY_CHANGE_CONTRACT_V1.json").read_text(encoding="utf-8"))
INVENTORY = json.loads((HERE / "live_repository_change_inventory_20260914.json").read_text(encoding="utf-8"))


class RepositoryChangeContractV1Test(unittest.TestCase):
    def test_live_has_seven_operational_consumers(self) -> None:
        consumers = INVENTORY["operational_consumers_with_active_github_write"]
        self.assertEqual(7, len(consumers))
        self.assertEqual(7, len({row["operation_code"] for row in consumers}))
        self.assertTrue(all(row["write_order"] < row["readback_order"] for row in consumers))

    def test_known_owner_admission_gaps_are_not_hidden(self) -> None:
        rows = {row["operation_code"]: row for row in INVENTORY["operational_consumers_with_active_github_write"]}
        self.assertFalse(rows["CREACION_CARD_LF"]["write_binding"])
        self.assertFalse(rows["CREACION_CARD_LF"]["readback_binding"])
        self.assertFalse(rows["CREACION_SKILL_LF"]["write_binding"])
        self.assertFalse(rows["CREACION_SKILL_LF"]["readback_binding"])

    def test_existing_s30_broker_is_not_claimed_universal(self) -> None:
        broker = INVENTORY["existing_governance_assets"]["s30_git_write_broker"]
        self.assertFalse(broker["universal_provider_claim"])
        self.assertEqual("lf/s30-", broker["protected_target_prefix"])
        provider = CONTRACT["provider_interface"]["existing_s30_provider"]
        self.assertTrue(provider["not_claimed_as_universal"])

    def test_attestation_and_currentness_are_consumed_not_reimplemented(self) -> None:
        separation = CONTRACT["separation_of_concerns"]
        self.assertIn("S31/Git Broker", separation["currentness_and_attestation_owned_elsewhere"])
        self.assertIn("Merge to main", separation["merge_owned_elsewhere"])

    def test_unknown_outcome_and_merge_are_fail_closed(self) -> None:
        results = set(CONTRACT["result_vocabulary"])
        self.assertIn("RECONCILIATION_REQUIRED_UNKNOWN_OUTCOME", results)
        forbidden = set(CONTRACT["provider_interface"]["forbidden_consumer_behaviors"])
        self.assertIn("blind_retry_after_unknown_outcome", forbidden)
        self.assertIn("write_to_main", forbidden)


if __name__ == "__main__":
    unittest.main()
