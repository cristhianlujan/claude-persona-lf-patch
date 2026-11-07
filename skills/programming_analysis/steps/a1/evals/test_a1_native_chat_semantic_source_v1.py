"""A1 GPT/Claude native source-only transport checks; NO real native model run."""
import copy
import importlib.util
import unittest
from pathlib import Path

from test_a1_semantic_candidate_v1 import LOGIN, A1, reviewer, semantic_candidate

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "a1_generic_native_source", BASE / "adapters/native_chat_semantic_source_v1.py"
)
NATIVE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NATIVE)

MODES = (
    ("GPT_NATIVE", "OPENAI_CHATGPT_NATIVE", "CHATGPT_CURRENT_CONVERSATION"),
    ("CLAUDE_NATIVE", "ANTHROPIC_CLAUDE_NATIVE", "CLAUDE_CURRENT_CONVERSATION"),
)


def frozen(mode="GPT_NATIVE", provider="OPENAI_CHATGPT_NATIVE",
           surface="CHATGPT_CURRENT_CONVERSATION", raw=LOGIN):
    return NATIVE.freeze_handoff(
        raw_request=raw, business="LF", executor_mode=mode,
        executor_provider=provider, current_surface=surface
    )


class A1GenericNativeTransport(unittest.TestCase):
    def test_01_both_existing_native_modes(self):
        for mode, provider, surface in MODES:
            with self.subTest(mode=mode):
                packet = frozen(mode, provider, surface)
                self.assertEqual(packet["executor_mode"], mode)
                self.assertFalse(packet["api_invocation"])
                self.assertFalse(packet["session_creation"])
                self.assertFalse(packet["runtime_qualified"])
                self.assertEqual(packet["conversation_scope"], "EXISTING_CONVERSATION_ONLY")

    def test_02_native_modes_share_a1_semantic_contract(self):
        for mode, provider, surface in MODES:
            with self.subTest(mode=mode):
                packet = frozen(mode, provider, surface)
                captured = NATIVE.capture_candidate(
                    handoff=packet, proposed_intent=semantic_candidate(LOGIN),
                    current_surface=surface
                )
                producer = NATIVE.producer_from_capture(packet, captured)
                candidate = A1.run(LOGIN, business="LF", semantic_producer=producer,
                                   semantic_reviewer=reviewer)
                self.assertEqual(candidate["status"], "VALID_OUTPUT", candidate)
                self.assertEqual(candidate["intent_analysis"]["operation"]["kind"], "IMPLEMENT")
                self.assertFalse(candidate["external_authority_verified"])
                self.assertFalse(candidate["semantic_review_identity_verified"])
                self.assertFalse(captured["runtime_provider_attested"])
                self.assertEqual(captured["capture_state"],
                                 "SOURCE_BOUND_NATIVE_CHAT_RAW_UNATTESTED")

    def test_03_provider_mode_mismatch(self):
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_PROVIDER_MODE_MISMATCH"):
            frozen("CLAUDE_NATIVE", "OPENAI_CHATGPT_NATIVE", "CLAUDE_CURRENT_CONVERSATION")

    def test_04_current_surface_mismatch(self):
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_CURRENT_SURFACE_MISMATCH"):
            frozen("GPT_NATIVE", "OPENAI_CHATGPT_NATIVE", "CLAUDE_CURRENT_CONVERSATION")

    def test_05_non_native_mode_rejected(self):
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_EXECUTOR_MODE_INVALID"):
            frozen("REMOTE_API", "REMOTE_API", "REMOTE_API")

    def test_06_source_sha_tamper_rejected(self):
        packet = frozen()
        packet["input_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_HANDOFF_TAMPERED"):
            NATIVE.capture_candidate(handoff=packet,
                                     proposed_intent=semantic_candidate(LOGIN),
                                     current_surface="CHATGPT_CURRENT_CONVERSATION")

    def test_07_native_capture_cross_provider_rejected(self):
        packet = frozen()
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_CROSS_PROVIDER_CAPTURE_FORBIDDEN"):
            NATIVE.capture_candidate(handoff=packet,
                                     proposed_intent=semantic_candidate(LOGIN),
                                     current_surface="CLAUDE_CURRENT_CONVERSATION")

    def test_08_capture_integrity_verified_before_callback(self):
        packet = frozen()
        captured = NATIVE.capture_candidate(
            handoff=packet, proposed_intent=semantic_candidate(LOGIN),
            current_surface="CHATGPT_CURRENT_CONVERSATION"
        )
        captured["intent_analysis"]["operation"]["kind"] = "REMOVE"
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_CAPTURE_DIGEST_DRIFT"):
            NATIVE.producer_from_capture(packet, captured)

    def test_09_false_provider_attestation_rejected(self):
        packet = frozen()
        captured = NATIVE.capture_candidate(
            handoff=packet, proposed_intent=semantic_candidate(LOGIN),
            current_surface="CHATGPT_CURRENT_CONVERSATION"
        )
        captured["runtime_provider_attested"] = True
        captured["capture_sha256"] = NATIVE._json_sha({
            key: value for key, value in captured.items() if key != "capture_sha256"
        })
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_CAPTURE_FALSE_AUTHORITY"):
            NATIVE.producer_from_capture(packet, captured)

    def test_10_callback_must_match_exact_raw(self):
        packet = frozen()
        captured = NATIVE.capture_candidate(
            handoff=packet, proposed_intent=semantic_candidate(LOGIN),
            current_surface="CHATGPT_CURRENT_CONVERSATION"
        )
        producer = NATIVE.producer_from_capture(packet, captured)
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_RAW_REQUEST_DRIFT"):
            producer("Implementa un listado")

    def test_11_input_scope_required(self):
        with self.assertRaisesRegex(ValueError, "NATIVE_A1_BUSINESS_SCOPE_NOT_LF"):
            NATIVE.freeze_handoff(raw_request=LOGIN, business="SALY",
                                  executor_mode="GPT_NATIVE",
                                  executor_provider="OPENAI_CHATGPT_NATIVE",
                                  current_surface="CHATGPT_CURRENT_CONVERSATION")

    def test_12_no_client_or_model_invocation_in_transport(self):
        packet = frozen()
        captured = NATIVE.capture_candidate(
            handoff=packet, proposed_intent=semantic_candidate(LOGIN),
            current_surface="CHATGPT_CURRENT_CONVERSATION"
        )
        for obj in (packet, captured):
            self.assertNotIn("llama", str(obj).lower())
            self.assertNotIn("endpoint_url", obj)
            self.assertNotIn("run_id", obj)
        self.assertEqual(captured["next_authority"],
                         "INDEPENDENT_SEMANTIC_REVIEW_REQUIRED")
        self.assertTrue(captured["no_run_created"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
