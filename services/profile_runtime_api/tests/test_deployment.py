from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.deployment import PENDING_CLASSIFICATION, VERIFIED_CLASSIFICATION, deployment_state, marker_digest
from profile_runtime_api.settings import Settings


class DeploymentStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.source_sha = "a" * 40
        self.settings = Settings(repo_root=Path(__file__).resolve().parents[3], state_dir=Path(self.temp.name), api_token="x", source_sha=self.source_sha)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_marker(self, **overrides) -> None:
        payload = {
            "schema": "lf-profile-runtime-live-reverify/v1",
            "source_sha": self.source_sha,
            "request_id": "471946b9-6e53-4cf5-b9b0-ee6c4ce18f8b",
            "queue_status": "SUCCEEDED",
            "runtime_completion": "PASS",
            "profile_contract_valid": "PASS",
            "semantic_utility": "PASS",
            "downstream_authorized": False,
            "canonical_registration_required": False,
            "read_only": True,
            "no_write": True,
            "no_promotion": True,
            "verified_at": "2026-09-13T03:31:49Z",
        }
        payload.update(overrides)
        payload["evidence_sha256"] = marker_digest(payload)
        (Path(self.temp.name) / "live_reverify.json").write_text(json.dumps(payload), encoding="utf-8")

    def test_missing_marker_stays_pending(self) -> None:
        state = deployment_state(self.settings)
        self.assertEqual(state["deployment_classification"], PENDING_CLASSIFICATION)
        self.assertFalse(state["operational_ready"])

    def test_matching_governed_marker_promotes_read_only_operational_state(self) -> None:
        self.write_marker()
        state = deployment_state(self.settings)
        self.assertEqual(state["deployment_classification"], VERIFIED_CLASSIFICATION)
        self.assertTrue(state["operational_ready"])
        self.assertFalse(state["downstream_authorized"])
        self.assertEqual(state["live_reverify_request_id"], "471946b9-6e53-4cf5-b9b0-ee6c4ce18f8b")

    def test_tampered_marker_digest_fails_closed(self) -> None:
        self.write_marker()
        path = Path(self.temp.name) / "live_reverify.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["semantic_utility"] = "FAIL"
        path.write_text(json.dumps(payload), encoding="utf-8")
        state = deployment_state(self.settings)
        self.assertEqual(state["deployment_classification"], PENDING_CLASSIFICATION)

    def test_stale_or_unsafe_marker_fails_closed(self) -> None:
        for overrides in ({"source_sha": "b" * 40}, {"downstream_authorized": True}, {"semantic_utility": "FAIL"}, {"no_promotion": False}):
            self.write_marker(**overrides)
            state = deployment_state(self.settings)
            self.assertEqual(state["deployment_classification"], PENDING_CLASSIFICATION)
            self.assertFalse(state["operational_ready"])


if __name__ == "__main__":
    unittest.main()
