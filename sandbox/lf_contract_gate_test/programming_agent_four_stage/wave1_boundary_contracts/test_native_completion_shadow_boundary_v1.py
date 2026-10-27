"""Synthetic readbacks only; no profile/runtime/DB execution."""
import copy
import unittest
from native_completion_shadow_boundary_v1 import ExpectedNativeContext, prepare_native_shadow_notice


class NativeShadowBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.expected = ExpectedNativeContext("EXEC-SYNTHETIC", "PROFILE-SYNTHETIC",
            "aaaaaaaa-0000-4000-8000-000000000001", "a" * 64)
        self.execution = {
            "execution_id": self.expected.execution_id,
            "operation_code": "EJECUCION_PERFIL_LF", "target_type": "PERFIL",
            "target_code": self.expected.profile_code, "status": "COMPLETED",
            "manifest": {"executor_mode": "GPT_NATIVE",
                "executor_provider": "OPENAI_CHATGPT_NATIVE",
                "router_profile_handoff": {"channel": "PROGRAMACION",
                    "profile_code": self.expected.profile_code},
                "raw_output": {"context_id": "UNTRUSTED", "secret": "DO_NOT_COPY"}}}
        self.steps = [{"execution_id": self.expected.execution_id, "step_id": s,
            "status": "STEP_PASS_WITH_EVIDENCE"} for s in ("semantic_judge", "report_output")]

    def plan(self, **kwargs):
        return prepare_native_shadow_notice(self.execution, self.steps, self.expected, **kwargs)

    def test_default_is_off(self):
        self.assertEqual(self.plan()["state"], "DISABLED")

    def test_positive_is_advisory_and_inputs_unchanged(self):
        before = copy.deepcopy((self.execution, self.steps))
        result = self.plan(enabled=True)
        self.assertEqual(result["state"], "NOTICE_PREPARED")
        self.assertFalse(result["effect_authority"])
        self.assertFalse(result["downstream_execution_allowed"])
        self.assertEqual(before, (self.execution, self.steps))
        self.assertEqual(result["notice"]["context_id"], self.expected.context_id)
        self.assertNotIn("raw_output", result["notice"])
        self.assertNotIn("secret", str(result))

    def test_producer_validated_is_too_early(self):
        self.execution["status"] = "IN_PROGRESS"
        self.assertEqual(self.plan(enabled=True)["state"], "SKIPPED_EXECUTION_MISMATCH")

    def test_terminal_identity_and_native_mode_are_exact(self):
        for key, value in [("execution_id", "OTHER"), ("operation_code", "OTHER"),
                           ("target_type", "OTHER"), ("target_code", "OTHER"),
                           ("status", "FAILED")]:
            with self.subTest(key=key):
                changed = copy.deepcopy(self.execution); changed[key] = value
                self.assertIsNone(prepare_native_shadow_notice(changed, self.steps,
                    self.expected, enabled=True)["notice"])
        for key in ("executor_mode", "executor_provider"):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.execution); changed["manifest"][key] = "OTHER"
                self.assertIsNone(prepare_native_shadow_notice(changed, self.steps,
                    self.expected, enabled=True)["notice"])

    def test_wrong_channel_or_profile_is_skipped(self):
        for key in ("channel", "profile_code"):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.execution)
                changed["manifest"]["router_profile_handoff"][key] = "OTHER"
                self.assertIsNone(prepare_native_shadow_notice(changed, self.steps,
                    self.expected, enabled=True)["notice"])

    def test_missing_failed_duplicate_or_foreign_step_is_skipped(self):
        cases = [self.steps[:1], self.steps + [self.steps[0]],
                 [dict(s, status="STEP_BLOCKED") for s in self.steps],
                 [dict(s, execution_id="OTHER") for s in self.steps]]
        for steps in cases:
            with self.subTest(steps=steps):
                result = prepare_native_shadow_notice(self.execution, steps, self.expected, enabled=True)
                self.assertEqual(result["state"], "SKIPPED_TERMINAL_STEPS_NOT_CLEAN")

    def test_invalid_readback_is_skipped(self):
        for row in (None, {}, {"manifest": None}, {"manifest": {}}):
            with self.subTest(row=row):
                self.assertIsNone(prepare_native_shadow_notice(row, self.steps,
                    self.expected, enabled=True)["notice"])

    def test_truthy_string_cannot_enable(self):
        with self.assertRaisesRegex(ValueError, "SHADOW_ENABLED_MUST_BE_BOOL"):
            self.plan(enabled="true")

    def test_expected_pin_is_validated(self):
        for context_id, sha in [("latest", "a"*64), (self.expected.context_id, "x"*64)]:
            with self.subTest(context_id=context_id, sha=sha):
                with self.assertRaises(ValueError):
                    ExpectedNativeContext("E", "P", context_id, sha)

    def test_repeated_readback_does_not_mint_new_identity(self):
        self.assertEqual(self.plan(enabled=True), self.plan(enabled=True))


if __name__ == "__main__":
    unittest.main()
