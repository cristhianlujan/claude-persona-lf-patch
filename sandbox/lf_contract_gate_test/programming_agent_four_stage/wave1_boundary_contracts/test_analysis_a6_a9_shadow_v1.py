"""Local shadow adapter tests; complete inputs are explicitly synthetic."""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

import analysis_a6_a9_shadow_v1 as shadow
from analysis_a6_a9_preview_v1 import canonical_sha256

HERE = Path(__file__).resolve().parent


class ShadowAdapterTests(unittest.TestCase):
    def setUp(self):
        self.draft = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]["extensions"]["programming_context_snapshot"]
        self.a6 = deepcopy(self.draft["implementability_schema"])
        self.response = b'{"paso":"ORIGINAL","canal":"PRODUCTO","dispatch":false}'
        self.real_popen = subprocess.Popen
        self.children = []

    def dispatch(self, **options):
        return shadow.shadow_after_response_v1(
            self.response, self.draft, self.a6, canonical_sha256(self.a6),
            enabled=True, **options)

    def observe(self, **options):
        result = self.dispatch(**options)
        self.assertIs(result.active_response, self.response)
        observation = result.observation.wait(3)
        self.assertNotEqual(observation["state"], "PENDING")
        self.assertEqual(observation["schema_version"], "A6_A9_SHADOW_OBSERVATION_V1")
        for key in ("route_effect_allowed", "planning_allowed", "execution_allowed", "operational_admission", "persistence_allowed"):
            self.assertIs(observation[key], False)
        return result, observation

    def test_disabled_does_not_spawn_or_serialize(self):
        with patch.object(shadow.subprocess, "Popen") as popen:
            obj = object()
            result = shadow.shadow_after_response_v1(self.response, obj, obj, obj)
            self.assertIs(result.active_response, self.response)
            self.assertEqual(result.observation.read()["state"], "DISABLED")
            popen.assert_not_called()

    def test_complete_synthetic_input_observed_and_original_response_preserved(self):
        before = deepcopy((self.draft, self.a6))
        result, observation = self.observe()
        self.assertEqual(observation["state"], "OBSERVED")
        self.assertEqual(observation["preview_status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(observation["ready_scope_ids"], ["S1"])
        self.assertEqual((self.draft, self.a6), before)
        self.assertNotIn("candidate_snapshot", observation)
        self.assertEqual(result.active_response, self.response)

    def test_missing_a6_returns_advisory_only(self):
        self.a6.pop("requirements")
        _, observation = self.observe()
        self.assertEqual(observation["preview_status"], "RETURN_TO_ANALYSIS")
        self.assertGreater(observation["issue_count"], 0)

    def test_capacity_limit_skips_without_waiting_or_spawning(self):
        lease = shadow._CAPACITY
        self.assertTrue(lease.acquire(False))
        self.assertTrue(lease.acquire(False))
        try:
            with patch.object(shadow.subprocess, "Popen") as popen:
                result = self.dispatch()
                self.assertIs(result.active_response, self.response)
                self.assertEqual(result.observation.read()["state"], "SKIPPED_CAPACITY")
                popen.assert_not_called()
        finally:
            lease.release()
            lease.release()

    def test_bad_inputs_do_not_exhaust_capacity(self):
        for _ in range(5):
            result = shadow.shadow_after_response_v1(self.response, object(), None, None, enabled=True)
            self.assertEqual(result.observation.read()["state"], "INPUT_REJECTED")
        _, observation = self.observe()
        self.assertEqual(observation["state"], "OBSERVED")

    def test_non_json_input_does_not_replace_response(self):
        result = shadow.shadow_after_response_v1(self.response, object(), None, None, enabled=True)
        self.assertIs(result.active_response, self.response)
        self.assertEqual(result.observation.read()["state"], "INPUT_REJECTED")

    def test_nonfinite_and_oversized_input(self):
        for value in ({"x": float("nan")}, {"x": "x" * (shadow.MAX_INPUT_BYTES + 1)}):
            result = shadow.shadow_after_response_v1(self.response, value, None, None, enabled=True)
            self.assertIs(result.active_response, self.response)
            self.assertEqual(result.observation.read()["state"], "INPUT_REJECTED")

    def test_invalid_controls_do_not_launch(self):
        for value in (0, -1, float("nan"), 100, True):
            with patch.object(shadow.subprocess, "Popen") as popen:
                result = self.dispatch(timeout_seconds=value)
                self.assertEqual(result.observation.read()["state"], "INPUT_REJECTED")
                self.assertIs(result.active_response, self.response)
                popen.assert_not_called()

    def test_process_start_failure_is_advisory(self):
        with patch.object(shadow.subprocess, "Popen", side_effect=OSError("test failure")):
            _, observation = self.observe()
        self.assertEqual(observation["state"], "ERROR")

    def child(self, source):
        def launch(args, **kwargs):
            child = self.real_popen([sys.executable, "-I", "-B", "-c", source], **kwargs)
            self.children.append(child)
            return child
        return launch

    def test_crashed_child_does_not_change_response(self):
        with patch.object(shadow.subprocess, "Popen", side_effect=self.child("raise RuntimeError('synthetic')")):
            _, observation = self.observe()
        self.assertEqual(observation["state"], "ERROR")
        self.assertTrue(all(p.poll() is not None for p in self.children))

    def test_timeout_child_reaped_without_collecting_on_response_path(self):
        with patch.object(shadow.subprocess, "Popen", side_effect=self.child("import time;time.sleep(5)")):
            started = time.monotonic()
            result = self.dispatch(timeout_seconds=0.15)
            self.assertIs(result.active_response, self.response)
            self.assertLess(time.monotonic() - started, 1.0)
            # Waiting for telemetry is explicitly separate from the response.
            observed = result.observation.wait(2)
        self.assertEqual(observed["state"], "TIMEOUT")
        self.assertTrue(all(p.poll() is not None for p in self.children))

    def test_malformed_worker_output_is_advisory(self):
        for source in ("print('not json')", "print('{}')", "import os;os._exit(4)"):
            with patch.object(shadow.subprocess, "Popen", side_effect=self.child(source)):
                _, observation = self.observe()
            self.assertEqual(observation["state"], "ERROR")

    def test_worker_env_excludes_inherited_credentials(self):
        seen = []
        def launch(args, **kwargs):
            seen.append(kwargs["env"])
            return self.real_popen(args, **kwargs)
        with patch.dict(os.environ, {"SHADOW_TEST_SECRET": "never-forward"}):
            with patch.object(shadow.subprocess, "Popen", side_effect=launch):
                _, observed = self.observe()
        self.assertEqual(observed["state"], "OBSERVED")
        self.assertEqual(set(seen[0]), {"PATH", "LANG"})
        self.assertNotIn("SHADOW_TEST_SECRET", seen[0])

    def test_observation_reader_cannot_modify_saved_diagnostic(self):
        result, observed = self.observe()
        observed["ready_scope_ids"].append("SPOOF")
        self.assertEqual(result.observation.read()["ready_scope_ids"], ["S1"])

    def test_active_response_is_not_serialized_or_normalized(self):
        self.response = object()
        result, _ = self.observe()
        self.assertIs(result.active_response, self.response)


if __name__ == "__main__":
    unittest.main()
