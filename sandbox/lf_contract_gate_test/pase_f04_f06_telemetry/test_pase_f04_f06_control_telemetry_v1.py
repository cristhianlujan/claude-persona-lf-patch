from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pase_f04_f06_control_telemetry_v1 as telemetry


class F04F06TelemetryTest(unittest.TestCase):
    def identity(self, control="F04_SCENARIO_PROFILES"):
        return telemetry.make_run_identity(
            control_id=control, repository="owner/repo", pr="42", head_sha="a" * 40,
            run_id="54321", run_attempt="2", source_path=Path("fixtures/control.json"), source_sha256="b" * 64)

    def test_success_failure_and_retry_keep_six_stages_and_same_run_identity(self):
        reports = []
        for attempt, returncode in ((1, 0), (2, 1), (3, 0)):
            result = {"returncode": returncode, "stdout": "PASS_F04_TERMINAL_SCENARIO_PROFILES=11/11" if returncode == 0 else "",
                      "stderr": ""}
            report = telemetry.run_control(
                control_id="F04_SCENARIO_PROFILES", run_identity=self.identity(), execute=lambda r=result: r,
                judge=lambda value: {"status": "PASS" if value["returncode"] == 0 else "FAIL"})
            reports.append(report)
            envelope = report[telemetry.TELEMETRY_SCHEMA]
            self.assertEqual(set(envelope["stages"]), set(telemetry.TELEMETRY_STAGES))
            self.assertEqual(envelope["run_identity"]["github_run_attempt"], "2")
            self.assertEqual(envelope["run_identity"]["git_head_sha"], "a" * 40)
            for stage in telemetry.TELEMETRY_STAGES:
                self.assertIsInstance(envelope["stages"][stage]["duration_ms"], (int, float))
        self.assertEqual([r["verdict"]["status"] for r in reports], ["PASS", "FAIL", "PASS"])

    def test_f06_stale_inventory_blocks_without_refresh(self):
        original_read = Path.read_text
        original_sha = telemetry.sha256_file
        inventory_path = telemetry.ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"
        original_bytes = inventory_path.read_bytes()
        try:
            # Exercise stale policy with the checked-in stale SHA; the fixture bytes are unchanged.
            report = telemetry.run_f06(exact_main_sha="f" * 40, repository="owner/repo", pr="42",
                                       head_sha="a" * 40, run_id="54321", run_attempt="2")
            self.assertEqual(report["verdict"]["status"], "BLOCKED")
            self.assertEqual(report["verdict"]["reason"], "BLOCK_STALE_CURRENTNESS")
            self.assertEqual(inventory_path.read_bytes(), original_bytes)
            self.assertEqual(set(report[telemetry.TELEMETRY_SCHEMA]["stages"]), set(telemetry.TELEMETRY_STAGES))
        finally:
            self.assertEqual(inventory_path.read_bytes(), original_bytes)

    def test_independent_judge_can_block_successful_producer(self):
        report = telemetry.run_control(
            control_id="F06_CONTROL_BINDING_INVENTORY", run_identity=self.identity("F06_CONTROL_BINDING_INVENTORY"),
            execute=lambda: {"producer_status": "PASS"},
            judge=lambda _value: {"status": "BLOCKED", "reason": "BLOCK_STALE_CURRENTNESS"})
        self.assertEqual(report["result"]["producer_status"], "PASS")
        self.assertEqual(report["verdict"]["status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
