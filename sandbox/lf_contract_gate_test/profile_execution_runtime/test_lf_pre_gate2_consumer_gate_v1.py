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

import copy
import hashlib

# Real Router output is a JSON object with `blocking_code`; free text alone
# is NOT evidence of an observed Router response.
ROUTER_JSON = json.dumps({"status": "BLOCKED",
                          "blocking_code": "BLOCK_SCOPE_SEMANTICS_UNATTESTED"})
RECEIPTS = ROUTER_JSON + " PROPOSE_ONLY_OPEN"
TEXT_ONLY = "ACT-0001 BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN"


def gate2_context(original="Entra por Router y define regla de intentos fallidos B2B LF"):
    sha = hashlib.sha256(original.encode()).hexdigest()
    name = "PERFIL-PRODUCT-DIRECTOR-LF"
    return {
        "schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
        "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
        "transport_mode": "CONTEXT_TRANSPORT",
        "next_action": "HANDOFF_CONTEXT_TO_SELECTED_PROFILE",
        "terminal": False, "effect_authority": False,
        "downstream_execution_allowed": False,
        "stage1_payload": {"schema_version": "LF_ROUTER_STAGE1_V2",
                           "negocio_codigo": "LF", "texto_original": original},
        "semantic_validation": {"status": "VALID", "decision": "SELECTED",
                                "request_sha256": sha,
                                "selected_profile_code": name},
        "gate2_derivation": {"status": "READY", "gate2_result": {
            "decision": "RESOLVED", "request_sha256": sha,
            "positive_target_refs": [name], "allowed_scope": [name]}},
    }
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
                # Same words but only as free text: honest, NOT certified.
                r = self.case(mode, HONEST, TEXT_ONLY)
                self.assertEqual(r["decision"], "REPORT_NOT_EXECUTED_UNVERIFIED")

    def test_actual_gate2_does_not_authorize_completion(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.case(mode, "11/11 COMPLETED",
                              RECEIPTS + json.dumps(gate2_context()))
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
                blocked = ROUTER_JSON
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
                # Honest but with no Router receipt: reported, never certified.
                self.assertEqual(
                    self.case(mode, "NOT_EXECUTED / NO_CANONICAL_EFFECT", "")["decision"],
                    "REPORT_NOT_EXECUTED_UNVERIFIED")

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
                (RECEIPTS + json.dumps(gate2_context("LF B2B")), 3),
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


class IndependentReviewCounterexamples(unittest.TestCase):
    def run_case(self, mode, request, receipts, final, **extra):
        return gate.evaluate({"consumer_mode": mode, "request_text": request,
                              "tool_receipts": receipts, "final_text": final,
                              **extra})

    def test_finding2_scope_is_structural_not_only_the_word_router(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                # LF scope declared by the consumer, request has no keyword.
                r = self.run_case(mode, "define política de intentos", "",
                                  "Definición registrada y lista",
                                  governed_operation=True)
                self.assertEqual(r["decision"], "BLOCK")
                # LF scope observed structurally in a Router payload.
                r = self.run_case(mode, "define política de intentos",
                                  json.dumps({"negocio_codigo": "LF"}),
                                  "Definición registrada y lista")
                self.assertEqual(r["decision"], "BLOCK")
                # LF named in the request, no keyword 'router'.
                r = self.run_case(mode, "LF: define política de intentos", "",
                                  "Definición registrada y lista")
                self.assertEqual(r["decision"], "BLOCK")
                # Non-LF, non-governed chat stays out of scope.
                r = self.run_case(mode, "define un plato de arroz", "",
                                  "Receta registrada")
                self.assertEqual(r["decision"], "NOT_APPLICABLE")

    def test_finding3_no_receipt_report_is_not_certified(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                r = self.run_case(mode, "Entra por Router y define regla", "",
                                  "NOT_EXECUTED NO_CANONICAL_EFFECT")
                self.assertEqual(r["decision"], "REPORT_NOT_EXECUTED_UNVERIFIED")
        payload = {"consumer_mode": "GPT_NATIVE",
                   "request_text": "Entra por Router y define regla",
                   "tool_receipts": "",
                   "final_text": "NOT_EXECUTED NO_CANONICAL_EFFECT"}
        p = subprocess.run([sys.executable, str(MODULE)], input=json.dumps(payload),
                           text=True, capture_output=True, check=False)
        self.assertEqual(p.returncode, 5)

    def test_finding4_gate2_needs_valid_structured_context(self):
        literal = "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION"
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            with self.subTest(mode=mode):
                # Forged free-text literal cannot defer a closure claim.
                r = self.run_case(mode, "Entra por Router y define regla",
                                  literal, "Todo OK, 11/11 COMPLETED")
                self.assertEqual(r["decision"], "BLOCK")
                self.assertEqual(r["reason_code"], "GATE2_CONTEXT_UNAUTHENTICATED")
                # Forged JSON that fails the existing validator is rejected.
                forged = gate2_context()
                forged["effect_authority"] = True
                r = self.run_case(mode, "Entra por Router y define regla",
                                  json.dumps(forged), "Todo OK, 11/11 COMPLETED")
                self.assertEqual(r["decision"], "BLOCK")
                # Valid context bound to another request does not defer.
                other = gate2_context("otra solicitud LF distinta")
                r = self.run_case(mode, "Entra por Router y define regla",
                                  json.dumps(other), "Todo OK, 11/11 COMPLETED",
                                  literal_request="Entra por Router y define regla")
                self.assertNotEqual(r["decision"], "DEFER_TO_GATE2_RECEIPT_GUARD")
                # Valid context bound to the current request defers (not PASS).
                good = gate2_context()
                r = self.run_case(mode, "Entra por Router y define regla",
                                  json.dumps(good), "11/11 COMPLETED",
                                  literal_request=good["stage1_payload"]["texto_original"])
                self.assertEqual(r["decision"], "DEFER_TO_GATE2_RECEIPT_GUARD")
                self.assertFalse(r["canonical_effect_allowed"])

    def test_structured_blocker_must_come_from_a_json_object(self):
        # A blocker string quoted inside prose or a string value is not an object.
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            quoted = json.dumps({"note": "BLOCK_SCOPE_SEMANTICS_UNATTESTED"})
            r = self.run_case(mode, "Entra por Router y define regla", quoted, HONEST)
            self.assertEqual(r["decision"], "REPORT_NOT_EXECUTED_UNVERIFIED")


if __name__ == "__main__":
    unittest.main()
