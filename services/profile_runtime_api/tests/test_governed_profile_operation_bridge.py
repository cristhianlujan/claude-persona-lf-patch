from __future__ import annotations

import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

if importlib.util.find_spec("psycopg") is None:
    psycopg_stub = types.ModuleType("psycopg")
    psycopg_stub.connect = lambda **_kwargs: None
    psycopg_types = types.ModuleType("psycopg.types")
    psycopg_json = types.ModuleType("psycopg.types.json")

    class Jsonb:
        def __init__(self, value):
            self.obj = value

    psycopg_json.Jsonb = Jsonb
    sys.modules["psycopg"] = psycopg_stub
    sys.modules["psycopg.types"] = psycopg_types
    sys.modules["psycopg.types.json"] = psycopg_json

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "services/profile_runtime_api/scripts/hetzner_queue_worker.py"
SCRIPT_DIR = SCRIPT.parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
spec = importlib.util.spec_from_file_location("hetzner_queue_worker_tested", SCRIPT)
assert spec and spec.loader
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class FakeConn:
    def close(self) -> None:
        return None

    def rollback(self) -> None:
        return None


def claimed() -> dict:
    return {
        "request_id": "11111111-2222-3333-4444-555555555555",
        "operation_code": "EJECUCION_PERFIL_LF",
        "profile_code": "PERFIL-QUALITY-PACK",
        "profile_slug": "quality_pack",
        "profile_source_paths": ["profiles/quality_pack/SKILL.md"],
        "input_literal": "Evaluate a governed candidate.",
        "input_image_base64": None,
        "input_image_sha256": None,
        "input_image_media_type": None,
        "runtime_request_envelope": None,
        "lf_adapter_sources": [],
    }


def model_governance() -> dict:
    return {
        "execution_id": "EXEC-PROFILE-RUNTIME-11111111-2222-3333-4444-555555555555",
        "context_receipt_ref": "supabase://public.lf_eventos/1#context_receipt",
        "context_receipt_digest": "sha256:" + "a" * 64,
        "context_capsule": {"delivery": {"jit_only": True}},
        "research_baseline": {
            "applicability": "NOT_APPLICABLE",
            "baseline_receipt_ref": "supabase://baseline/1",
            "baseline_digest": "NOT_APPLICABLE",
            "baseline_snapshot": {},
            "research_baseline_contract": None,
        },
    }


class GovernedBridgeOrderingTest(unittest.TestCase):
    def test_not_required_skips_baseline_model_endpoint(self) -> None:
        calls: list[tuple[str, str]] = []
        governed = {
            "execution_id": model_governance()["execution_id"],
            "baseline_first": {"outcome": "STEP_RECORDED"},
        }
        accepted = {"job_id": "main-job"}
        job = {"status": "COMPLETED", "result": {"result": {}}}
        with (
            patch.object(worker, "_connect", return_value=FakeConn()),
            patch.object(worker, "_claim", return_value=claimed()),
            patch.object(worker, "_begin_governed_pre_model", return_value=governed),
            patch.object(worker, "_read_model_governance", return_value=model_governance()),
            patch.object(worker, "_queue_native_payload", return_value={"profile": {}}),
            patch.object(worker, "_attach_governed_operation", side_effect=lambda payload, _g: payload),
            patch.object(worker, "_api_json", side_effect=lambda method, path, payload=None: (calls.append((method, path)) or accepted)),
            patch.object(worker, "_wait_job", return_value=job),
            patch.object(worker, "_persist_success"),
        ):
            self.assertTrue(worker.run_once())
        self.assertEqual(calls, [("POST", "/v1/profile/queue-execute")])

    def test_required_baseline_is_persisted_before_main_dispatch(self) -> None:
        events: list[str] = []
        governed = {
            "execution_id": model_governance()["execution_id"],
            "baseline_first": {"outcome": "BASELINE_REQUIRED"},
            "research_baseline_contract": {
                "contract_version": "PROFILE_RESEARCH_BASELINE_BINDING_V1"
            },
            "input_digest": "sha256:" + "1" * 64,
            "source": {"profile_source_digest": "sha256:" + "2" * 64},
        }
        baseline_job = {"status": "COMPLETED", "result": {"result": {"status": "PASS"}}}
        main_job = {"status": "COMPLETED", "result": {"result": {}}}

        def api_json(_method: str, path: str, _payload=None):
            events.append(path)
            return {"job_id": "baseline-job" if path.endswith("research-baseline") else "main-job"}

        def wait_job(job_id: str):
            events.append("wait:" + job_id)
            return baseline_job if job_id == "baseline-job" else main_job

        with (
            patch.object(worker, "_connect", return_value=FakeConn()),
            patch.object(worker, "_claim", return_value=claimed()),
            patch.object(worker, "_begin_governed_pre_model", return_value=governed),
            patch.object(worker, "_baseline_api_payload", return_value={"request_id": claimed()["request_id"]}),
            patch.object(worker, "_api_json", side_effect=api_json),
            patch.object(worker, "_wait_job", side_effect=wait_job),
            patch.object(worker, "_baseline_envelope_from_job", side_effect=lambda _job: (events.append("baseline-envelope") or {"snapshot": {}})),
            patch.object(worker, "_persist_required_baseline", side_effect=lambda *_args: (events.append("baseline-persisted") or {"outcome": "STEP_RECORDED"})),
            patch.object(worker, "_read_model_governance", return_value=model_governance()),
            patch.object(worker, "_queue_native_payload", return_value={"profile": {}}),
            patch.object(worker, "_attach_governed_operation", side_effect=lambda payload, _g: payload),
            patch.object(worker, "_persist_success", side_effect=lambda *_args, **_kwargs: events.append("main-persisted")),
        ):
            self.assertTrue(worker.run_once())

        self.assertLess(events.index("/v1/profile/research-baseline"), events.index("baseline-persisted"))
        self.assertLess(events.index("baseline-persisted"), events.index("/v1/profile/queue-execute"))
        self.assertLess(events.index("/v1/profile/queue-execute"), events.index("main-persisted"))

    def test_execution_identity_is_stable(self) -> None:
        request_id = claimed()["request_id"]
        self.assertEqual(
            worker._governed_execution_id(request_id),
            worker._governed_execution_id(request_id),
        )


if __name__ == "__main__":
    unittest.main()
