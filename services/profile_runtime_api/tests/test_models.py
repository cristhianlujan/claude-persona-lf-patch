from __future__ import annotations

import base64
import unittest

from pydantic import ValidationError

from profile_runtime_api.hashing import canonical_json_sha256, sha256_bytes
from profile_runtime_api.models import Artifact, InputGovernanceReceipt, ProfileTask


class ModelGovernanceTest(unittest.TestCase):
    def test_known_profile_slug_is_bound_to_canonical_profile_code(self) -> None:
        with self.assertRaises(ValidationError):
            ProfileTask(
                request_id="bad-binding",
                profile_code="PERFIL-UI-ARCHITECT",
                profile_slug="quality_pack",
                profile_source_paths=["profiles/quality_pack/SKILL.md"],
                input_literal="Evaluate current evidence.",
            )

    def test_governance_requires_current_ready_and_exact_context_hash(self) -> None:
        context = {"screen": "B2B-CARGA-001", "scope": ["read"]}
        valid = {
            "receipt_ref": "receipt://current/1",
            "current": True,
            "ready": True,
            "context_sha256": canonical_json_sha256(context),
            "context": context,
            "status": "READY",
        }
        self.assertEqual(InputGovernanceReceipt.model_validate(valid).context, context)
        for change in (
            {"current": False},
            {"ready": False},
            {"context_sha256": "0" * 64},
        ):
            with self.assertRaises(ValidationError):
                InputGovernanceReceipt.model_validate(valid | change)

    def test_attached_image_bytes_are_bound_to_declared_sha(self) -> None:
        raw = b"not-a-real-png-but-model-binding-does-not-decode-it"
        payload = {
            "screen_code": "B2B-CARGA-001",
            "filename": "candidate.png",
            "image_sha256": sha256_bytes(raw),
            "width_px": 1600,
            "height_px": 1000,
            "image_base64": base64.b64encode(raw).decode("ascii"),
            "image_media_type": "image/png",
        }
        self.assertEqual(Artifact.model_validate(payload).image_bytes(), raw)
        with self.assertRaises(ValidationError):
            Artifact.model_validate(payload | {"image_sha256": "f" * 64})


if __name__ == "__main__":
    unittest.main()
