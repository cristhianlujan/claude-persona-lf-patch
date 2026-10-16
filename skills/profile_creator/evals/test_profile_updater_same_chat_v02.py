"""Regression: native GPT/Claude uses current-chat capture, never API or fake attestation."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_updater_same_chat_v02 import (
    freeze_same_chat_handoff, capture_current_chat_raw, _sha_json,
    _sha_text, ChatRouteBlocked)


def fx(mode="GPT_NATIVE"):
    surface = ("CHATGPT_CURRENT_CONVERSATION" if mode == "GPT_NATIVE"
               else "CLAUDE_CURRENT_CONVERSATION")
    contract = {"executor_mode": mode, "run_id": "PE10-CURRENT-CHAT-CASE-02",
                "profile_slug": "systemic_root_cause_repair_lf"}
    contract["contract_sha256"] = _sha_json(contract)
    plan = {"schema": "PROFILE_EVOLUTION_PLAN_V1",
            "operation_code": "ACTUALIZACION_PERFIL_LF",
            "profile_slug": "systemic_root_cause_repair_lf",
            "profile_source_write_allowed": False,
            "automatic_production_activation": False,
            "blocking_codes": [], "evolution_mode": "ADAPT",
            "profile_assessment": {"assessment_status": "EVIDENCE_SUFFICIENT"},
            "selection": {"execution_authorized": False,
              "method_requirements": [
                  {"method_id": "CAUSAL_ANALYSIS", "eligible_for_composition": True,
                   "within_budget": True},
                  {"method_id": "SELF_REFINE", "eligible_for_composition": True,
                   "within_budget": True}]}}
    profile = "# SRCR\nSource profile."
    sources = [{"ref": "profiles/systemic_root_cause_repair_lf/SKILL.md",
                "content": profile, "content_sha256": _sha_text(profile)}]
    frozen = freeze_same_chat_handoff(
        contract=contract, plan=plan, input_literal="Find the root cause of recurring failure",
        profile_sources=sources, current_surface=surface)
    raw = {"run_id": frozen["run_id"], "evolution_mode": "ADAPT",
           "methods_applied": ["CAUSAL_ANALYSIS", "SELF_REFINE"],
           "deliverable": {"hypothesis": "Check causal chain, then refine against evidence"}}
    return contract, plan, sources, surface, frozen, raw


class SameChatTests(unittest.TestCase):
    def assertBlocked(self, expected, function):
        with self.assertRaises(ChatRouteBlocked) as cm:
            function()
        self.assertEqual(str(cm.exception), expected)

    def freeze(self, contract, plan, sources, surface):
        return freeze_same_chat_handoff(contract=contract, plan=plan,
            input_literal="Test", profile_sources=sources, current_surface=surface)

    def test_gpt_same_chat(self):
        _, _, _, surface, frozen, raw = fx()
        cap = capture_current_chat_raw(frozen, raw, current_surface=surface)
        self.assertFalse(frozen["session_creation"])
        self.assertFalse(frozen["api_invocation"])
        self.assertEqual(cap["capture_status"], "SOURCE_BOUND_NATIVE_CHAT_RAW_UNATTESTED")
        self.assertFalse(cap["method_execution_certified"])

    def test_claude_same_chat(self):
        _, _, _, surface, frozen, raw = fx("CLAUDE_NATIVE")
        self.assertEqual(frozen["executor_mode"], "CLAUDE_NATIVE")
        cap = capture_current_chat_raw(frozen, raw, current_surface=surface)
        self.assertFalse(cap["runtime_provider_attested"])

    def test_provider_cross_surface_blocked(self):
        contract, plan, sources, _, _, _ = fx()
        self.assertBlocked("WRONG_CURRENT_CONVERSATION", lambda:
            self.freeze(contract, plan, sources, "CLAUDE_CURRENT_CONVERSATION"))

    def test_remote_api_not_native(self):
        contract, plan, sources, surface, _, _ = fx()
        contract["executor_mode"] = "REMOTE_API"
        contract["contract_sha256"] = _sha_json(
            {k: v for k, v in contract.items() if k != "contract_sha256"})
        self.assertBlocked("MODE_NOT_NATIVE", lambda:
            self.freeze(contract, plan, sources, surface))

    def test_contract_tamper(self):
        contract, plan, sources, surface, _, _ = fx()
        contract["run_id"] = "swapped"
        self.assertBlocked("FROZEN_CONTRACT_SHA_MISMATCH", lambda:
            self.freeze(contract, plan, sources, surface))

    def test_source_tamper(self):
        contract, plan, sources, surface, _, _ = fx()
        sources[0]["content"] += " changed"
        self.assertBlocked("SOURCE_CONTENT_DRIFT", lambda:
            self.freeze(contract, plan, sources, surface))

    def test_unqualified_methods_allow_authoring_not_cutover(self):
        contract, plan, sources, surface, _, _ = fx()
        plan["blocking_codes"] = ["METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED"]
        frozen = self.freeze(contract, plan, sources, surface)
        self.assertTrue(frozen["authority_pending"])
        self.assertFalse(frozen["cutover_eligible"])
        raw = {"run_id": frozen["run_id"], "evolution_mode": "ADAPT",
               "methods_applied": ["CAUSAL_ANALYSIS", "SELF_REFINE"],
               "deliverable": {"evidence": "bounded test"}}
        cap = capture_current_chat_raw(frozen, raw, current_surface=surface)
        self.assertFalse(cap["method_execution_certified"])

    def test_safety_blocker_rejects_authoring(self):
        contract, plan, sources, surface, _, _ = fx()
        plan["blocking_codes"] = ["BLOCKED_AUTHORITY_REQUIRED"]
        self.assertBlocked("SELECTION_BLOCKED_BY_SAFETY_OR_EVIDENCE", lambda:
            self.freeze(contract, plan, sources, surface))

    def test_budget_block(self):
        contract, plan, sources, surface, _, _ = fx()
        plan["selection"]["method_requirements"][0]["within_budget"] = False
        self.assertBlocked("SELECTED_METHOD_OVER_BUDGET", lambda:
            self.freeze(contract, plan, sources, surface))

    def test_cross_chat_capture_block(self):
        _, _, _, _, frozen, raw = fx()
        self.assertBlocked("CROSS_PROVIDER_CHAT_CAPTURE_FORBIDDEN", lambda:
            capture_current_chat_raw(frozen, raw,
                current_surface="CLAUDE_CURRENT_CONVERSATION"))

    def test_methods_mismatch_block(self):
        _, _, _, surface, frozen, raw = fx()
        raw["methods_applied"] = ["CAUSAL_ANALYSIS"]
        self.assertBlocked("RAW_SELECTED_METHODS_MISMATCH", lambda:
            capture_current_chat_raw(frozen, raw, current_surface=surface))

    def test_forged_attestation_block(self):
        _, _, _, surface, frozen, raw = fx()
        raw["runtime_attestation"] = {"verified": True}
        self.assertBlocked("RAW_CONTAINS_FORGED_AUTHORITY", lambda:
            capture_current_chat_raw(frozen, raw, current_surface=surface))

    def test_handoff_tamper_block(self):
        _, _, _, surface, frozen, raw = fx()
        frozen["run_id"] = "tampered"
        self.assertBlocked("HANDOFF_TAMPERED", lambda:
            capture_current_chat_raw(frozen, raw, current_surface=surface))

    def test_no_change_without_methods(self):
        contract, plan, sources, surface, _, _ = fx()
        plan["evolution_mode"] = "NO_CHANGE"
        plan["selection"]["method_requirements"] = []
        frozen = self.freeze(contract, plan, sources, surface)
        raw = {"run_id": frozen["run_id"], "evolution_mode": "NO_CHANGE",
               "methods_applied": [], "deliverable": {"decision": "NO_CHANGE"}}
        cap = capture_current_chat_raw(frozen, raw, current_surface=surface)
        self.assertEqual(cap["raw_output"]["methods_applied"], [])

    def test_full_selection_not_eight_external_backends(self):
        contract, plan, sources, surface, _, _ = fx()
        methods = ["CAUSAL_ANALYSIS", "HOSTILE_CHALLENGE", "DEEP_RESEARCH",
                   "SELF_REFINE", "EVALUATOR_OPTIMIZER", "VERIFIER_GUIDED_SEARCH",
                   "PARALLEL_EVIDENCE_SEARCH", "PROMPT_OPTIMIZATION"]
        plan["evolution_mode"] = "REARCHITECT"
        plan["selection"]["method_requirements"] = [
            {"method_id": method, "eligible_for_composition": True, "within_budget": True}
            for method in methods]
        plan["blocking_codes"] = ["METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED"]
        frozen = self.freeze(contract, plan, sources, surface)
        raw = {"run_id": frozen["run_id"], "evolution_mode": "REARCHITECT",
               "methods_applied": methods,
               "deliverable": {"result": "same chat authoring"}}
        cap = capture_current_chat_raw(frozen, raw, current_surface=surface)
        self.assertEqual(len(cap["raw_output"]["methods_applied"]), 8)
        self.assertFalse(cap["runtime_provider_attested"])


if __name__ == "__main__":
    unittest.main()
