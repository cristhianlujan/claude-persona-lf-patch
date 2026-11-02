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

    def test_router_block_without_advisory_never_justifies_success(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                blocked = "BLOCK_SCOPE_SEMANTICS_UNATTESTED"
                r = self.case(mode, HONEST, blocked)
                self.assertEqual(r["decision"], "ALLOW_TRUTHFUL_BLOCK")
                self.assertFalse(r["canonical_effect_allowed"])
                r = self.case(mode, "Definición registrada — 100%", blocked)
                self.assertEqual(r["decision"], "BLOCK")


    def test_missing_router_receipt_blocks_completion_for_both(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                self.assertEqual(
                    self.case(mode, "La política está VIGENTE en Supabase", "")["decision"],
                    "BLOCK")
                self.assertEqual(
                    self.case(mode, "Definición registrada — 100%", "")["reason_code"],
                    "ROUTER_RECEIPT_MISSING")
                self.assertEqual(
                    self.case(mode, "NOT_EXECUTED / NO_CANONICAL_EFFECT", "")["decision"],
                    "ALLOW_TRUTHFUL_BLOCK")

    def test_no_advisory_block_cannot_claim_official_policy(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                blocked = "BLOCK_SCOPE_SEMANTICS_UNATTESTED"
                self.assertEqual(
                    self.case(mode, "La política quedó VIGENTE en Supabase", blocked)["decision"],
                    "BLOCK")
                self.assertEqual(
                    self.case(mode, "Bloqueado por el Router", blocked)["decision"],
                    "BLOCK")

    def test_cli_defer_and_unknown_are_not_success_exit_zero(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            for receipts, code in [
                (RECEIPTS + " GATE2_DERIVED_PENDING_GOVERNED_ADMISSION", 3),
                ("Router responde ruta autorizada", 4),
            ]:
                payload = {"consumer_mode": mode, "request_text": "LF B2B",
                           "tool_receipts": receipts, "final_text": "Aún pendiente"}
                p = subprocess.run([sys.executable, str(MODULE)],
                                   input=json.dumps(payload), text=True,
                                   capture_output=True, check=False)
                self.assertEqual(p.returncode, code)

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
