from __future__ import annotations

import importlib.util
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any

DEPS_AVAILABLE = all(
    importlib.util.find_spec(name) is not None for name in ("fastapi", "httpx", "jsonschema")
)

if DEPS_AVAILABLE:
    from fastapi.testclient import TestClient

    from profile_runtime_api.app import create_app
    from profile_runtime_api.settings import Settings


class FakeAPIEngine:
    def __init__(self) -> None:
        self.initialized = False

    def initialize(self) -> None:
        self.initialized = True

    def run_execute(self, payload: Any) -> dict[str, Any]:
        return {
            "kind": "execute",
            "request_id": payload.profile.request_id,
            "downstream_authorized": False,
        }

    def run_batch(self, payload: Any) -> dict[str, Any]:
        return {
            "kind": "batch",
            "batch_id": payload.batch_id,
            "downstream_authorized": False,
        }

    def run_artifact_set_execute(self, payload: Any) -> dict[str, Any]:
        return {
            "kind": "artifact_set_execute",
            "request_id": payload.profile.request_id,
            "artifact_count": len(payload.artifact_set.artifacts),
            "downstream_authorized": False,
        }

    def runtime_snapshot(self) -> dict[str, Any]:
        return {
            "deployment_classification": "INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY",
            "operational_ready": False,
        }


@unittest.skipUnless(DEPS_AVAILABLE, "FastAPI integration dependencies are not installed")
class APITest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        repo = Path(__file__).resolve().parents[3]
        settings = Settings(
            repo_root=repo,
            state_dir=Path(self.temp.name),
            api_token="secret-test-token",
        )
        self.engine = FakeAPIEngine()
        self.client_context = TestClient(  # type: ignore[name-defined]
            create_app(  # type: ignore[name-defined]
                settings, engine_factory=lambda _settings: self.engine
            )
        )
        self.client = self.client_context.__enter__()

    def tearDown(self) -> None:
        self.client_context.__exit__(None, None, None)
        self.temp.cleanup()

    @staticmethod
    def payload(request_id: str = "api-request-1") -> dict[str, Any]:
        context = {"screen": "B2B-CARGA-001"}
        import hashlib
        import json

        context_sha = hashlib.sha256(
            json.dumps(context, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        return {
            "artifact": {
                "screen_code": "B2B-CARGA-001",
                "filename": "candidate.png",
                "image_sha256": "e" * 64,
                "width_px": 1600,
                "height_px": 1000,
                "observations": [],
            },
            "input_governance": {
                "receipt_ref": "receipt://test/current",
                "current": True,
                "ready": True,
                "context_sha256": context_sha,
                "context": context,
                "status": "READY",
            },
            "profile": {
                "request_id": request_id,
                "profile_code": "PERFIL-QUALITY-PACK",
                "profile_slug": "quality_pack",
                "profile_source_paths": ["profiles/quality_pack/SKILL.md"],
                "input_literal": "Evaluate the governed candidate.",
            },
        }

    @staticmethod
    def artifact_set_payload(request_id: str = "api-artifact-set-1") -> dict[str, Any]:
        import hashlib
        import json

        context = {"router": "ACT-0001", "scope": "visual_artifact_review_only"}
        context_sha = hashlib.sha256(
            json.dumps(context, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        return {
            "artifact_set": {
                "schema": "NON_CANONICAL_ARTIFACT_SET_V1",
                "subject_mode": "NON_CANONICAL_ARTIFACT",
                "artifacts": [
                    {
                        "artifact_ref": "approved://payment-single",
                        "artifact": {
                            "screen_code": "PAYMENT-SINGLE-APPROVED",
                            "filename": "single.png",
                            "image_sha256": "1" * 64,
                            "width_px": 1600,
                            "height_px": 1000,
                            "observations": [],
                        },
                    },
                    {
                        "artifact_ref": "approved://payment-installments",
                        "artifact": {
                            "screen_code": "PAYMENT-INSTALLMENTS-APPROVED",
                            "filename": "installments.png",
                            "image_sha256": "2" * 64,
                            "width_px": 1600,
                            "height_px": 1000,
                            "observations": [],
                        },
                    },
                ],
            },
            "input_governance": {
                "receipt_ref": "router://ACT-0001/noncanonical/api",
                "current": True,
                "ready": True,
                "context_sha256": context_sha,
                "context": context,
                "status": "ADVISORY_READ_ONLY",
                "decision": "ADVISORY",
                "subject_mode": "NON_CANONICAL_ARTIFACT",
                "required_artifact_binding": ["artifact_ref", "artifact_sha256", "dimensions"],
                "constraints": {
                    "operation_must_equal": "EJECUCION_PERFIL_LF",
                    "read_only": True,
                    "no_write": True,
                    "no_promotion": True,
                    "canonical_registration_required": False,
                    "artifact_binding_required_before_profile_execution": True,
                },
            },
            "profile": {
                "request_id": request_id,
                "profile_code": "PERFIL-UI-ARCHITECT",
                "profile_slug": "ui_architect",
                "profile_source_paths": ["profiles/ui_architect/SKILL.md"],
                "input_literal": "Compare approved visual artifacts without changing canon.",
                "runtime_output_mode": "UI_FOCUSED_DECISION",
                "send_image_to_model": False,
            },
        }

    def auth(self) -> dict[str, str]:
        return {"Authorization": "Bearer secret-test-token"}

    def test_health_is_minimal_and_runtime_requires_auth(self) -> None:
        health = self.client.get("/health")
        self.assertEqual(health.status_code, 200)
        self.assertEqual(
            health.json()["classification"],
            "INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY",
        )
        self.assertEqual(self.client.get("/runtime").status_code, 401)
        runtime = self.client.get("/runtime", headers=self.auth())
        self.assertEqual(runtime.status_code, 200)
        self.assertFalse(runtime.json()["operational_ready"])

    def test_execute_is_async_idempotent_and_queryable(self) -> None:
        response = self.client.post(
            "/v1/profile/execute", json=self.payload(), headers=self.auth()
        )
        self.assertEqual(response.status_code, 202)
        accepted = response.json()
        for _ in range(100):
            job = self.client.get(accepted["status_url"], headers=self.auth()).json()
            if job["status"] in {"COMPLETED", "FAILED"}:
                break
            time.sleep(0.01)
        self.assertEqual(job["status"], "COMPLETED")
        self.assertNotIn("image_base64", job["request_meta"])
        self.assertNotIn("input_literal", job["request_meta"])
        repeated = self.client.post(
            "/v1/profile/execute", json=self.payload(), headers=self.auth()
        ).json()
        self.assertTrue(repeated["reused"])
        self.assertEqual(repeated["job_id"], accepted["job_id"])
        changed = self.payload()
        changed["profile"]["input_literal"] = "A different payload with the same request id."
        self.assertEqual(
            self.client.post(
                "/v1/profile/execute", json=changed, headers=self.auth()
            ).status_code,
            409,
        )

    def test_artifact_set_execute_is_first_class_and_idempotent(self) -> None:
        payload = self.artifact_set_payload()
        response = self.client.post(
            "/v1/profile/artifact-set-execute", json=payload, headers=self.auth()
        )
        self.assertEqual(response.status_code, 202)
        accepted = response.json()
        for _ in range(100):
            job = self.client.get(accepted["status_url"], headers=self.auth()).json()
            if job["status"] in {"COMPLETED", "FAILED"}:
                break
            time.sleep(0.01)
        self.assertEqual(job["status"], "COMPLETED")
        self.assertEqual(job["request_meta"]["artifact_count"], 2)
        self.assertEqual(
            job["request_meta"]["artifact_refs"],
            ["approved://payment-single", "approved://payment-installments"],
        )
        repeated = self.client.post(
            "/v1/profile/artifact-set-execute", json=payload, headers=self.auth()
        ).json()
        self.assertTrue(repeated["reused"])
        self.assertEqual(repeated["job_id"], accepted["job_id"])

    def test_validation_error_does_not_echo_literal_input(self) -> None:
        invalid = self.payload("api-invalid-1")
        invalid["profile"]["profile_slug"] = "quality_pack"
        invalid["profile"]["profile_code"] = "PERFIL-UI-ARCHITECT"
        response = self.client.post(
            "/v1/profile/execute", json=invalid, headers=self.auth()
        )
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("Evaluate the governed candidate", response.text)
        self.assertEqual(response.json()["detail"], "REQUEST_VALIDATION_FAILED")


if __name__ == "__main__":
    unittest.main()
