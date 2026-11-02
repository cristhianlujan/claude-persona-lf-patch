import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

MODULE = Path(__file__).with_name("lf_pre_gate2_consumer_gate_v1.py")
spec = importlib.util.spec_from_file_location("lf_shared_gate", MODULE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

RECEIPTS = "ACT-0001 BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN"
HONEST = ("BLOCK_SCOPE_SEMANTICS_UNATTESTED / NOT_EXECUTED / "
          "NO_CANONICAL_EFFECT. No se creó política oficial.")


class BothNativeConsumers(unittest.TestCase):
    def case(self, mode, final, receipts=RECEIPTS):
        return gate.evaluate({
            "consumer_mode": mode,
            "request_text": "Entra por Router y define regla de intentos fallidos B2B LF",
            "tool_receipts": receipts,
            "final_text": final,
        })

    def test_pre_gate2_is_blocked_for_both_consumers(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, "Definición registrada — 100%. Issue #3505.")
                self.assertEqual(r["decision"], "BLOCK")
                self.assertFalse(r["canonical_effect_allowed"])

    def test_manual_issue_cannot_close_governed_run(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, "El Issue #3505 completó el recorrido.")
                self.assertEqual(r["decision"], "BLOCK")

    def test_explicit_honest_block_can_end_without_effect(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, HONEST)
                self.assertEqual(r["decision"], "ALLOW_TRUTHFUL_BLOCK")
                self.assertFalse(r["canonical_effect_allowed"])

    def test_actual_gate2_does_not_authorize_completion(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, "11/11 COMPLETED", RECEIPTS + " GATE2_DERIVED_PENDING_GOVERNED_ADMISSION")
                self.assertEqual(r["decision"], "DEFER_TO_GATE2_RECEIPT_GUARD")
                self.assertFalse(r["canonical_effect_allowed"])

    def test_denial_requires_observed_evidence(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                final = "NOT_EXECUTED: TOOL_ACCESS_DENIED"
                self.assertEqual(self.case(mode, final)["decision"], "BLOCK")
                r = self.case(mode, final, RECEIPTS + " TOOL_ACCESS_DENIED")
                self.assertEqual(r["decision"], "ALLOW_TRUTHFUL_BLOCK")

    def test_trusted_pre_gate2_block_alone_is_not_advisory_detour(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, "Bloqueado por el Router", "BLOCK_SCOPE_SEMANTICS_UNATTESTED")
                self.assertEqual(r["decision"], "NOT_APPLICABLE")
                self.assertFalse(r["canonical_effect_allowed"])

    def test_invalid_consumer_or_missing_evidence_fails_closed(self):
        for mode in ("GPT", "CLAUDE", None):
            self.assertEqual(self.case(mode, "COMPLETED")["decision"], "BLOCK")
        self.assertEqual(gate.evaluate({})["decision"], "BLOCK")

    def test_cli_same_decision_and_exit_code_for_both(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            payload = {"consumer_mode": mode, "request_text": "LF B2B",
                       "tool_receipts": RECEIPTS,
                       "final_text": "Issue #3505 es el cierre."}
            p = subprocess.run([sys.executable, str(MODULE)], input=json.dumps(payload),
                               text=True, capture_output=True, check=False)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(json.loads(p.stdout)["reason_code"],
                             "PRE_GATE2_ROUTE_CONTINUITY_BLOCK")


if __name__ == "__main__":
    unittest.main()
