from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import pase_f04_f06_control_telemetry_v1 as telemetry


class F04F06TelemetryTest(unittest.TestCase):
    def identity(self, control="F04_SCENARIO_PROFILES"):
        return telemetry.make_run_identity(
            control_id=control, repository="owner/repo", pr="42", head_sha="a" * 40,
            run_id="54321", run_attempt="2", source_path=Path("fixtures/control.json"),
            source_sha256="b" * 64, source_blob="c" * 40)

    def test_success_failure_retry_share_contract_without_attempt_fields(self):
        reports = []
        for returncode in (0, 1, 0):
            result = {"returncode": returncode,
                      "stdout": "PASS_F04_TERMINAL_SCENARIO_PROFILES=11/11" if returncode == 0 else "",
                      "stderr": ""}
            report = telemetry.run_control(
                control_id="F04_SCENARIO_PROFILES", run_identity=self.identity(), execute=lambda r=result: r,
                judge=lambda value: {"status": "PASS" if value["returncode"] == 0 else "FAIL",
                                     "reason": "F04_PRODUCER_FAILED" if value["returncode"] else "CURRENT"},
                setup_ms=12.5)
            reports.append(report)
            envelope = report[telemetry.TELEMETRY_SCHEMA]
            self.assertEqual(set(envelope["stages"]), set(telemetry.TELEMETRY_STAGES))
            self.assertEqual(envelope["run_identity"]["github_run_attempt"], "2")
            self.assertEqual(envelope["run_identity"]["git_head_sha"], "a" * 40)
            self.assertEqual(envelope["run_identity"]["execution_id"], "PASE-CONTROL-PR42-R54321-F04_SCENARIO_PROFILES")
            self.assertNotIn("attempt_number", envelope)
            self.assertNotIn("retry_of_execution_id", envelope)
            self.assertNotIn("verdict", envelope)
            self.assertEqual(envelope["evidence_locator"], "https://github.com/owner/repo/actions/runs/54321")
            self.assertLessEqual(report["envelope_bytes"], telemetry.MAX_ENVELOPE_BYTES)
            self.assertGreaterEqual(envelope["stages"]["control_execution"]["duration_ms"], 12.5)
            self.assertGreaterEqual(report["telemetry_overhead_ms"], 0)
            for name in telemetry.TELEMETRY_STAGES:
                self.assertIsInstance(envelope["stages"][name]["duration_ms"], (int, float))
        self.assertEqual([r["verdict"]["status"] for r in reports], ["PASS", "FAIL", "PASS"])
        self.assertEqual(reports[0][telemetry.TELEMETRY_SCHEMA]["run_identity"],
                         reports[2][telemetry.TELEMETRY_SCHEMA]["run_identity"])

    def test_f06_stale_inventory_blocks_without_refresh(self):
        inventory_path = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"
        original_bytes = inventory_path.read_bytes()
        report = telemetry.run_f06(exact_main_sha="f" * 40, repository="owner/repo", pr="42",
                                   head_sha="9d7bbdd69765cab309638dd88f40a10760ff9394",
                                   run_id="54321", run_attempt="2")
        self.assertEqual(report["verdict"]["status"], "BLOCKED")
        self.assertEqual(report["verdict"]["reason"], "BLOCK_STALE_CURRENTNESS")
        self.assertEqual(inventory_path.read_bytes(), original_bytes)
        self.assertEqual(set(report[telemetry.TELEMETRY_SCHEMA]["stages"]), set(telemetry.TELEMETRY_STAGES))

    def test_independent_judge_can_block_successful_producer(self):
        report = telemetry.run_control(
            control_id="F06_CONTROL_BINDING_INVENTORY", run_identity=self.identity("F06_CONTROL_BINDING_INVENTORY"),
            execute=lambda: {"producer_status": "PASS"},
            judge=lambda _value: {"status": "BLOCKED", "reason": "BLOCK_STALE_CURRENTNESS"})
        self.assertEqual(report["result"]["producer_status"], "PASS")
        self.assertEqual(report["verdict"]["status"], "BLOCKED")
        self.assertEqual(report[telemetry.TELEMETRY_SCHEMA]["failure"]["code"], "BLOCK_STALE_CURRENTNESS")


if __name__ == "__main__":
    unittest.main()
