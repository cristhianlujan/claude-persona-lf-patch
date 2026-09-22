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

    def commit(self) -> None:
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

    def test_srcr_external_authority_manifest_is_bound_into_governed_context(self) -> None:
        manifest = {
            "bundle_id": "SRCR-TEST",
            "evidence": [
                {
                    "evidence_id": "EV-1",
                    "subject": "current authority",
                    "evidence_class": "OBSERVED_LIVE",
                    "source_locator": "supabase://public/example/1",
                    "revision_or_observed_at": "2026-09-22T00:00:00Z",
                    "digest": "sha256:" + "1" * 64,
                    "state": "CURRENT",
                }
            ],
            "query_trace": [
                {
                    "sequence": 1,
                    "tool_permission": "READ_SUPABASE",
                    "resolver_id": "LF_SUPABASE_READBACK_V1",
                    "provider": "SUPABASE",
                    "query_locator": "supabase://public/example/1",
                    "request_digest": "sha256:" + "2" * 64,
                    "result_digest": "sha256:" + "1" * 64,
                    "observed_at": "2026-09-22T00:00:00Z",
                    "evidence_id": "EV-1",
                    "consumer": "$.live_authority_packet",
                    "result_status": "FOUND",
                    "result_count": 1,
                    "claim_support": "CONTENT",
                }
            ],
        }
        payload = {
            "profile": {
                "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
                "evidence_manifest": manifest,
            }
        }
        external_resolution = {
            "mode": "EXTERNAL_AUTHORITY_RESOLVER",
            "resolved_authority_context": {
                "EV-1": {
                    "source_locator": "supabase://public/example/1",
                    "digest": "sha256:" + "1" * 64,
                    "result_status": "FOUND",
                    "result_count": 1,
                    "claim_support": "CONTENT",
                    "resolved_value": {"fact": "live"},
                }
            },
        }
        bound = worker._bind_external_authority_resolution(
            payload, model_governance(), external_resolution=external_resolution
        )
        capsule = bound["context_capsule"]
        self.assertEqual(capsule["query_trace_count"], 1)
        self.assertEqual(capsule["evidence_count"], 1)
        self.assertEqual(
            capsule["evidence_manifest_sha256"],
            "sha256:" + worker._canonical_json_sha256(manifest),
        )
        self.assertEqual(
            capsule["resolved_authority_context"]["EV-1"]["source_locator"],
            "supabase://public/example/1",
        )
        self.assertEqual(capsule["research_execution_mode"], "EXTERNAL_AUTHORITY_RESOLVER")
        self.assertEqual(capsule["resolved_authority_count"], 1)
        self.assertEqual(
            capsule["resolved_authority_context"]["EV-1"]["resolved_value"]["fact"],
            "live",
        )

    def test_srcr_external_authority_binding_fails_closed_without_resolver_execution(self) -> None:
        manifest = {
            "bundle_id": "SRCR-TEST",
            "evidence": [{
                "evidence_id": "EV-1",
                "subject": "current authority",
                "evidence_class": "OBSERVED_LIVE",
                "source_locator": "supabase://public/example/1",
                "revision_or_observed_at": "2026-09-22T00:00:00Z",
                "digest": "sha256:" + "1" * 64,
                "state": "CURRENT",
            }],
            "query_trace": [{
                "sequence": 1,
                "tool_permission": "READ_SUPABASE",
                "resolver_id": "LF_SUPABASE_READBACK_V1",
                "provider": "SUPABASE",
                "query_locator": "supabase://public/example/1",
                "request_digest": "sha256:" + "2" * 64,
                "result_digest": "sha256:" + "1" * 64,
                "observed_at": "2026-09-22T00:00:00Z",
                "evidence_id": "EV-1",
                "consumer": "$.live_authority_packet",
                "result_status": "FOUND",
                "result_count": 1,
                "claim_support": "CONTENT",
            }],
        }
        payload = {"profile": {
            "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            "evidence_manifest": manifest,
        }}
        with self.assertRaisesRegex(
            RuntimeError, "SRCR_LIVE_RESEARCH_EXECUTION_PATH_MISSING"
        ):
            worker._bind_external_authority_resolution(payload, model_governance())

    def test_srcr_research_queue_payload_transports_manifest_and_resolved_values(self) -> None:
        manifest = {
            "bundle_id": "SRCR-TEST",
            "evidence": [{"evidence_id": "EV-1"}],
            "query_trace": [{"evidence_id": "EV-1"}],
        }
        claimed_payload = claimed()
        claimed_payload.update({
            "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            "profile_slug": "systemic_root_cause_repair_lf",
            "profile_source_paths": ["profiles/systemic_root_cause_repair_lf/SKILL.md"],
            "runtime_request_envelope": {
                "schema": "LF_PROFILE_RUNTIME_QUEUE_RESEARCH_V1",
                "route_kind": "QUEUE_NATIVE_RESEARCH",
                "research_execution_mode": "EXTERNAL_AUTHORITY_RESOLVER",
                "evidence_manifest": manifest,
                "resolved_authority_context": {
                    "EV-1": {
                        "source_locator": "supabase://public/example/1",
                        "digest": "sha256:" + "1" * 64,
                        "resolved_value": {"fact": "live"},
                    }
                },
            },
        })
        payload = worker._queue_native_payload(claimed_payload)
        self.assertEqual(payload["profile"]["evidence_manifest"], manifest)
        self.assertEqual(
            payload["_external_authority_resolution"]["mode"],
            "EXTERNAL_AUTHORITY_RESOLVER",
        )

    def test_srcr_external_authority_binding_fails_closed_without_manifest(self) -> None:
        payload = {
            "profile": {
                "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            }
        }
        with self.assertRaisesRegex(
            RuntimeError, "SRCR_EVIDENCE_MANIFEST_REQUIRED_BEFORE_MODEL"
        ):
            worker._bind_external_authority_resolution(payload, model_governance())

    def test_non_srcr_profile_keeps_governed_context_unchanged(self) -> None:
        governed = model_governance()
        payload = {"profile": {"profile_code": "PERFIL-QUALITY-PACK"}}
        self.assertIs(
            worker._bind_external_authority_resolution(payload, governed),
            governed,
        )

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
            patch.object(worker, "_reconcile_governed_pending", return_value=0),
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
            patch.object(worker, "_reconcile_governed_pending", return_value=0),
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


    def test_output_validate_persists_required_canonical_quality_boundary(self) -> None:
        profile = {
            "runtime_completion": {"status": "PASS", "receipt": {}},
            "profile_contract_valid": {"status": "PASS", "blocking_codes": []},
            "semantic_utility": {"status": "PASS", "blocking_codes": []},
            "canonical_quality": {
                "applicability": "REQUIRED",
                "status": "PENDING_INDEPENDENT_SEMANTIC_REVIEW",
                "deterministic_floors_can_accept_quality": False,
                "receipt_required_for_pass_to_quality_pack": True,
            },
            "raw_output": '{"profile_pack_id":"SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"}',
        }
        job = {"result": {"result": profile}}
        captured: dict[str, dict] = {}

        class Cursor:
            def __enter__(self): return self
            def __exit__(self, *_args): return None

        class Conn(FakeConn):
            def cursor(self): return Cursor()

        def fetch(_cur, _query, params):
            step_id = params[1]
            payload = params[3].obj
            captured[step_id] = payload
            return {"outcome": "STEP_RECORDED"}

        governed = {
            "execution_id": model_governance()["execution_id"],
            "source": {
                "profile_source_digest": "sha256:" + "b" * 64,
                "source_revision": "c" * 40,
            },
        }
        with (
            patch.object(worker, "_profile_result", return_value=profile),
            patch.object(worker, "_read_model_governance", return_value=model_governance()),
            patch.object(worker, "_fetch_json_scalar", side_effect=fetch),
        ):
            result = worker._record_post_model_governance(
                Conn(),
                claimed=claimed(),
                governed=governed,
                job=job,
            )
        self.assertEqual(result["status"], "READY_FOR_SEMANTIC_JUDGE")
        self.assertEqual(result["canonical_quality"]["applicability"], "REQUIRED")
        self.assertEqual(
            captured["output_validate"]["canonical_quality"]["status"],
            "PENDING_INDEPENDENT_SEMANTIC_REVIEW",
        )

    def test_invalid_required_canonical_quality_boundary_blocks(self) -> None:
        profile = {
            "runtime_completion": {"status": "PASS", "receipt": {}},
            "profile_contract_valid": {"status": "PASS", "blocking_codes": []},
            "semantic_utility": {"status": "PASS", "blocking_codes": []},
            "canonical_quality": {
                "applicability": "REQUIRED",
                "status": "PASS",
                "deterministic_floors_can_accept_quality": True,
                "receipt_required_for_pass_to_quality_pack": False,
            },
            "raw_output": '{}',
        }
        job = {"result": {"result": profile}}
        class Cursor:
            def __enter__(self): return self
            def __exit__(self, *_args): return None
        class Conn(FakeConn):
            def cursor(self): return Cursor()
        governed = {
            "execution_id": model_governance()["execution_id"],
            "source": {
                "profile_source_digest": "sha256:" + "b" * 64,
                "source_revision": "c" * 40,
            },
        }
        with (
            patch.object(worker, "_profile_result", return_value=profile),
            patch.object(worker, "_read_model_governance", return_value=model_governance()),
            patch.object(worker, "_fetch_json_scalar", return_value={"outcome": "STEP_RECORDED"}),
        ):
            result = worker._record_post_model_governance(
                Conn(), claimed=claimed(), governed=governed, job=job
            )
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(
            result["error_code"],
            "HETZNER_CANONICAL_QUALITY_BOUNDARY_INVALID",
        )



    def test_validated_semantic_quality_records_judge_then_report_output(self) -> None:
        captured: list[tuple[str, dict]] = []

        class Cursor:
            def __enter__(self): return self
            def __exit__(self, *_args): return None

        class Conn(FakeConn):
            def __init__(self): self.commits = 0
            def cursor(self): return Cursor()
            def commit(self): self.commits += 1

        def fetch(_cur, _query, params):
            step_id = params[1]
            payload = params[3].obj
            captured.append((step_id, payload))
            return {"outcome": "STEP_RECORDED"}

        finalize = {
            "status": "PASS",
            "canonical_quality_accepted": True,
            "quality_receipt": {"decision": "PASS_TO_QUALITY_PACK"},
        }
        semantic = {
            "verdict": "PASS_INDEPENDENT_SEMANTIC",
            "candidate_sha256": "a" * 64,
            "scope_packet_sha256": "b" * 64,
            "blocking_codes": [],
            "unsupported_claims": [],
        }
        conn = Conn()
        with patch.object(worker, "_fetch_json_scalar", side_effect=fetch):
            result = worker._record_semantic_quality_result(
                conn,
                execution_id=model_governance()["execution_id"],
                profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
                semantic_execution_receipt_ref="native-review://receipt/1",
                semantic_result=semantic,
                finalize_result=finalize,
            )

        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual([step for step, _payload in captured], ["semantic_judge", "report_output"])
        self.assertEqual(captured[0][1]["semantic_judge_result"]["status"], "PASS")
        self.assertEqual(captured[0][1]["unsupported_claims"], [])
        self.assertTrue(captured[1][1]["no_write_performed"])
        self.assertTrue(captured[1][1]["canonical_quality_accepted"])
        self.assertEqual(conn.commits, 1)

    def test_semantic_quality_never_records_when_review_is_not_independent_pass(self) -> None:
        class Conn(FakeConn):
            def cursor(self):
                raise AssertionError("DB must not be touched for rejected review")

        base = {
            "status": "PASS",
            "canonical_quality_accepted": True,
            "quality_receipt": {"decision": "PASS_TO_QUALITY_PACK"},
        }
        rejected = worker._record_semantic_quality_result(
            Conn(),
            execution_id=model_governance()["execution_id"],
            profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            semantic_execution_receipt_ref="native-review://receipt/1",
            semantic_result={
                "verdict": "RETURN_TO_WORKER_FOR_SELF_REPAIR",
                "unsupported_claims": [],
            },
            finalize_result=base,
        )
        self.assertEqual(rejected["status"], "BLOCKED")
        self.assertEqual(rejected["error_code"], "SEMANTIC_REVIEW_VERDICT_NOT_PASS")

        rejected_claim = worker._record_semantic_quality_result(
            Conn(),
            execution_id=model_governance()["execution_id"],
            profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            semantic_execution_receipt_ref="native-review://receipt/1",
            semantic_result={
                "verdict": "PASS_INDEPENDENT_SEMANTIC",
                "unsupported_claims": [{"claim": "unresolved"}],
            },
            finalize_result=base,
        )
        self.assertEqual(rejected_claim["status"], "BLOCKED")
        self.assertEqual(
            rejected_claim["error_code"],
            "SEMANTIC_REVIEW_UNSUPPORTED_CLAIMS_PRESENT",
        )


    def test_ready_for_semantic_judge_never_persists_queue_success(self) -> None:
        runtime_profile = {
            "runtime_completion": {"status": "PASS", "receipt": {}},
            "profile_contract_valid": {"status": "PASS", "blocking_codes": []},
            "semantic_utility": {"status": "PASS", "blocking_codes": []},
            "raw_output": "{}",
        }
        job = {"result": {"result": runtime_profile}}
        class Cursor:
            rowcount = 1
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def execute(self, _query, params=None):
                self.params = params
        class Conn(FakeConn):
            def __init__(self): self.cursor_obj = Cursor()
            def cursor(self): return self.cursor_obj
        conn = Conn()
        with patch.object(
            worker,
            "_record_post_model_governance",
            return_value={
                "status": "READY_FOR_SEMANTIC_JUDGE",
                "next_gate": "semantic_judge",
                "execution_id": model_governance()["execution_id"],
            },
        ):
            worker._persist_success(
                conn,
                claimed()["request_id"],
                job,
                claimed=claimed(),
                governed={"execution_id": model_governance()["execution_id"]},
            )
        params = conn.cursor_obj.params
        self.assertEqual(params[0], "BLOCKED")
        self.assertEqual(params[7], "HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING")

    def test_runtime_block_is_not_relabelled_as_semantic_pending(self) -> None:
        profile = {
            "runtime_completion": {"status": "PASS", "receipt": {}},
            "profile_contract_valid": {
                "status": "FAIL",
                "blocking_codes": ["PROFILE_CONTRACT_FAILED"],
            },
            "semantic_utility": {"status": "PASS", "blocking_codes": []},
            "raw_output": "{}",
        }
        job = {"result": {"result": profile}}
        class Cursor:
            rowcount = 1
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def execute(self, _query, params=None): self.params = params
        class Conn(FakeConn):
            def __init__(self): self.cursor_obj = Cursor()
            def cursor(self): return self.cursor_obj
        conn = Conn()
        with patch.object(
            worker,
            "_record_post_model_governance",
            return_value={
                "status": "READY_FOR_SEMANTIC_JUDGE",
                "next_gate": "semantic_judge",
                "execution_id": model_governance()["execution_id"],
            },
        ):
            worker._persist_success(
                conn,
                claimed()["request_id"],
                job,
                claimed=claimed(),
                governed={"execution_id": model_governance()["execution_id"]},
            )
        self.assertEqual(conn.cursor_obj.params[0], "BLOCKED")
        self.assertEqual(conn.cursor_obj.params[7], "PROFILE_CONTRACT_FAILED")

    def test_reconcile_requires_exact_terminal_judge_pass(self) -> None:
        self.assertIn("v_lf_operation_execution_judge", Path(worker.__file__).read_text())
        self.assertIn("required_steps_pass == required_steps", Path(worker.__file__).read_text())
        self.assertIn('judge_result == "PASS"', Path(worker.__file__).read_text())
        self.assertIn('execution_status == "COMPLETED"', Path(worker.__file__).read_text())

    def test_reconcile_promotes_only_completed_canonical_pass(self) -> None:
        class Cursor:
            def __init__(self):
                self.rowcount = 0
                self.calls = []
                self._rows = [(
                    claimed()["request_id"],
                    model_governance()["execution_id"],
                    "COMPLETED",
                    11,
                    11,
                    0,
                    0,
                    "PASS",
                )]
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def execute(self, query, params=None):
                self.calls.append((query, params))
                if "select q.request_id" in query:
                    self.rowcount = len(self._rows)
                elif "set status='SUCCEEDED'" in query:
                    self.rowcount = 1
                else:
                    self.rowcount = 0
            def fetchall(self): return list(self._rows)
        class Conn(FakeConn):
            def __init__(self):
                self.cursor_obj = Cursor()
                self.commits = 0
            def cursor(self): return self.cursor_obj
            def commit(self): self.commits += 1
        conn = Conn()
        self.assertEqual(worker._reconcile_governed_pending(conn), 1)
        self.assertTrue(
            any("set status='SUCCEEDED'" in query for query, _params in conn.cursor_obj.calls)
        )
        self.assertEqual(conn.commits, 1)

    def test_reconcile_never_promotes_in_progress_or_failed_judge(self) -> None:
        class Cursor:
            def __init__(self, rows):
                self.rowcount = 0
                self.calls = []
                self._rows = rows
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def execute(self, query, params=None):
                self.calls.append((query, params))
                self.rowcount = 1 if "error_code='HETZNER_GOVERNED_TERMINAL_JUDGE_FAILED'" in query else 0
            def fetchall(self): return list(self._rows)
        class Conn(FakeConn):
            def __init__(self, rows):
                self.cursor_obj = Cursor(rows)
            def cursor(self): return self.cursor_obj
            def commit(self): return None

        in_progress = [(
            claimed()["request_id"],
            model_governance()["execution_id"],
            "IN_PROGRESS",
            11,
            9,
            0,
            0,
            "FAIL",
        )]
        conn = Conn(in_progress)
        self.assertEqual(worker._reconcile_governed_pending(conn), 0)
        self.assertFalse(
            any("set status='SUCCEEDED'" in query for query, _params in conn.cursor_obj.calls)
        )

        failed_terminal = [(
            claimed()["request_id"],
            model_governance()["execution_id"],
            "COMPLETED",
            11,
            10,
            1,
            0,
            "FAIL",
        )]
        conn = Conn(failed_terminal)
        self.assertEqual(worker._reconcile_governed_pending(conn), 0)
        self.assertFalse(
            any("set status='SUCCEEDED'" in query for query, _params in conn.cursor_obj.calls)
        )
        self.assertTrue(
            any("HETZNER_GOVERNED_TERMINAL_JUDGE_FAILED" in query for query, _params in conn.cursor_obj.calls)
        )

    def test_failure_persistence_reconciles_queue_terminal_to_canonical_execution(self) -> None:
        class Cursor:
            def __init__(self):
                self.rowcount = 0
                self.calls = []
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def execute(self, query, params=None):
                self.calls.append((query, params))
                if "set status='FAILED'" in query:
                    self.rowcount = 1
                else:
                    self.rowcount = 1
        class Conn(FakeConn):
            def __init__(self):
                self.cursor_obj = Cursor()
                self.commits = 0
            def cursor(self): return self.cursor_obj
            def commit(self): self.commits += 1

        conn = Conn()
        request_id = claimed()["request_id"]
        terminal = {
            "result": "CANONICAL_TERMINAL_RECONCILED",
            "queue_status": "FAILED",
            "canonical_status_after": "BLOCKED",
        }
        with patch.object(worker, "_reconcile_queue_terminal", return_value=terminal) as reconcile:
            result = worker._persist_failure(
                conn, request_id, RuntimeError("HETZNER_BASELINE_API_FAILED:fixture")
            )
        self.assertEqual(result, terminal)
        reconcile.assert_called_once_with(conn.cursor_obj, request_id)
        self.assertEqual(conn.commits, 1)
        self.assertTrue(
            any("set status='FAILED'" in query for query, _params in conn.cursor_obj.calls)
        )

    def test_queue_terminal_helper_calls_single_canonical_reconciler_rpc(self) -> None:
        request_id = claimed()["request_id"]
        expected = {
            "result": "CANONICAL_TERMINAL_RECONCILED",
            "canonical_status_after": "BLOCKED",
        }
        cursor = object()
        with patch.object(worker, "_fetch_json_scalar", return_value=expected) as fetch:
            result = worker._reconcile_queue_terminal(cursor, request_id)
        self.assertEqual(result, expected)
        fetch.assert_called_once_with(
            cursor,
            "select public.lf_profile_execution_reconcile_queue_terminal_v1(%s::uuid,%s)",
            (request_id, worker._governed_execution_id(request_id)),
        )

    def test_terminal_reconciler_source_is_fail_closed_and_semantic_pending_is_nonterminal(self) -> None:
        sql = (
            ROOT / "supabase" / "migrations"
            / "20260922162500_lf_profile_execution_queue_terminal_reconcile_v1.sql"
        ).read_text(encoding="utf-8")
        self.assertIn("q.status='FAILED'", sql)
        self.assertIn("target_status := 'BLOCKED'", sql)
        self.assertIn("q.status='CANCELLED'", sql)
        self.assertIn("target_status := 'CANCELLED'", sql)
        self.assertIn("HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING", sql)
        self.assertIn("NON_TERMINAL_SEMANTIC_REVIEW_PENDING", sql)
        self.assertIn("QUEUE_SUCCESS_CANONICAL_NOT_COMPLETED", sql)
        self.assertIn("CANONICAL_TERMINAL_CONFLICT", sql)
        self.assertIn("and status='IN_PROGRESS'", sql)
        self.assertIn("PROFILE_RUNTIME_QUEUE_TERMINAL_RECONCILIATION_V1", sql)

    def test_execution_identity_is_stable(self) -> None:
        request_id = claimed()["request_id"]
        self.assertEqual(
            worker._governed_execution_id(request_id),
            worker._governed_execution_id(request_id),
        )


if __name__ == "__main__":
    unittest.main()
