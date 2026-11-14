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
    psycopg_pq = types.ModuleType("psycopg.pq")

    class TransactionStatus:
        IDLE = "IDLE"

    psycopg_pq.TransactionStatus = TransactionStatus

    class Jsonb:
        def __init__(self, value):
            self.obj = value

    psycopg_json.Jsonb = Jsonb
    sys.modules["psycopg"] = psycopg_stub
    sys.modules["psycopg.pq"] = psycopg_pq
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
        "router_profile_handoff": None,
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
            self.assertTrue(worker.run_once(FakeConn()))
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
            self.assertTrue(worker.run_once(FakeConn()))

        self.assertLess(events.index("/v1/profile/research-baseline"), events.index("baseline-persisted"))
        self.assertLess(events.index("baseline-persisted"), events.index("/v1/profile/queue-execute"))
        self.assertLess(events.index("/v1/profile/queue-execute"), events.index("main-persisted"))

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
        with (
            patch.object(
                worker,
                "_record_post_model_governance",
                return_value={
                    "status": "READY_FOR_SEMANTIC_JUDGE",
                    "next_gate": "semantic_judge",
                    "execution_id": model_governance()["execution_id"],
                },
            ),
            patch.object(
                worker,
                "_reconcile_terminal_queue",
                return_value={"result": "CANONICAL_TERMINAL_RECONCILED"},
            ) as reconcile,
        ):
            worker._persist_success(
                conn,
                claimed()["request_id"],
                job,
                claimed=claimed(),
                governed={"execution_id": model_governance()["execution_id"]},
            )
        reconcile.assert_not_called()
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
        with (
            patch.object(
                worker,
                "_record_post_model_governance",
                return_value={
                    "status": "READY_FOR_SEMANTIC_JUDGE",
                    "next_gate": "semantic_judge",
                    "execution_id": model_governance()["execution_id"],
                },
            ),
            patch.object(
                worker,
                "_reconcile_terminal_queue",
                return_value={"result": "CANONICAL_TERMINAL_RECONCILED"},
            ) as reconcile,
        ):
            worker._persist_success(
                conn,
                claimed()["request_id"],
                job,
                claimed=claimed(),
                governed={"execution_id": model_governance()["execution_id"]},
            )
        reconcile.assert_called_once_with(
            conn.cursor_obj,
            claimed()["request_id"],
            allow_missing_canonical=False,
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
        terminal = {
            "result": "TERMINAL_AUTHORITY_RECEIPT_ATTACHED",
            "terminal_authority_receipt": {
                "schema_version": "LF_PROFILE_RUNTIME_TERMINAL_AUTHORITY_RECEIPT_V1",
                "canonical_execution_id": model_governance()["execution_id"],
            },
            "terminal_authority_receipt_sha256": "sha256:" + "f" * 64,
        }
        with patch.object(worker, "_fetch_json_scalar", return_value=terminal) as attach:
            self.assertEqual(worker._reconcile_governed_pending(conn), 1)
        attach.assert_called_once()
        self.assertTrue(
            any("set status='SUCCEEDED'" in query for query, _params in conn.cursor_obj.calls)
        )
        update_call = next(
            (params for query, params in conn.cursor_obj.calls if "set status='SUCCEEDED'" in query),
            None,
        )
        self.assertIsNotNone(update_call)
        self.assertEqual(update_call[0].obj["terminal_authority_receipt_sha256"], "sha256:" + "f" * 64)
        self.assertEqual(update_call[1].obj["terminal_authority_receipt_sha256"], "sha256:" + "f" * 64)
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


    def test_pre_model_materializes_server_owned_scope_packet(self) -> None:
        source = Path(worker.__file__).read_text()
        self.assertIn("lf_profile_execution_scope_authority_packet_v1", source)
        self.assertIn('"scope_authority_packet": scope_packet["scope_authority_packet"]', source)
        self.assertIn('"scope_authority_packet_sha256": scope_packet["scope_packet_sha256"]', source)
        self.assertIn("HETZNER_SCOPE_AUTHORITY_PACKET_NOT_READY", source)

    def test_pre_model_consumes_authorized_handoff_without_rerouting(self) -> None:
        source = Path(worker.__file__).read_text()
        self.assertIn("lf_router_profile_execution_handoff_validate_v1", source)
        self.assertIn('"router_read": "AUTHORIZED_HANDOFF_VALIDATED"', source)
        self.assertIn('"reentered_router": False', source)
        self.assertIn("legacy_without_handoff", source)
        handoff_pos = source.index("handoff = claimed.get(\"router_profile_handoff\")")
        legacy_pos = source.index("Legacy compatibility only", handoff_pos)
        validator_pos = source.index("lf_router_profile_execution_handoff_validate_v1", handoff_pos)
        router_call_pos = source.index("select public.lf_router_resolve_v1", handoff_pos)
        self.assertLess(validator_pos, legacy_pos)
        self.assertGreater(router_call_pos, legacy_pos)

    def test_channel_context_hydration_occurs_inside_profile_execution(self) -> None:
        source = Path(worker.__file__).read_text()
        self.assertIn("lf_profile_execution_channel_context_v1", source)
        self.assertIn("context.get(\"status\") == \"READY\" and handoff is not None", source)

    def test_input_governance_is_owned_by_input_validate_for_handoff_rows(self) -> None:
        source = Path(worker.__file__).read_text()
        self.assertIn("lf_profile_execution_input_validate_v1", source)
        self.assertIn("HETZNER_PROFILE_INPUT_VALIDATE_NOT_READY", source)
        self.assertIn("Legacy compatibility for queue rows created before router handoffs", source)
        handoff_pos = source.index("if handoff is not None:", source.index("input_evidence_ref"))
        input_gate_pos = source.index("lf_profile_execution_input_validate_v1", handoff_pos)
        legacy_scope_pos = source.index("Legacy compatibility for queue rows created before router handoffs", handoff_pos)
        self.assertLess(input_gate_pos, legacy_scope_pos)

    def test_terminal_failure_reconciler_accepts_only_canonical_outcomes(self) -> None:
        request_id = claimed()["request_id"]
        class Cursor:
            pass
        cur = Cursor()
        with patch.object(
            worker,
            "_fetch_json_scalar",
            return_value={"result": "CANONICAL_TERMINAL_RECONCILED"},
        ):
            result = worker._reconcile_terminal_queue(
                cur, request_id, allow_missing_canonical=False
            )
        self.assertEqual(result["result"], "CANONICAL_TERMINAL_RECONCILED")

        with patch.object(
            worker,
            "_fetch_json_scalar",
            return_value={"result": "NO_CANONICAL_EXECUTION"},
        ):
            result = worker._reconcile_terminal_queue(
                cur, request_id, allow_missing_canonical=True
            )
        self.assertEqual(result["result"], "NO_CANONICAL_EXECUTION")

        with patch.object(
            worker,
            "_fetch_json_scalar",
            return_value={
                "result": "CANONICAL_TERMINAL_CONFLICT",
                "blocking_code": "PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED",
            },
        ):
            with self.assertRaisesRegex(RuntimeError, "HETZNER_QUEUE_TERMINAL_RECONCILE_FAILED"):
                worker._reconcile_terminal_queue(
                    cur, request_id, allow_missing_canonical=False
                )


    def test_execution_identity_is_stable(self) -> None:
        request_id = claimed()["request_id"]
        self.assertEqual(
            worker._governed_execution_id(request_id),
            worker._governed_execution_id(request_id),
        )



class NativeChatSameRunChainingRegression(unittest.TestCase):
    """Prove the official Issue runner unit tests run in the PR CI, not only Issue Actions."""
    def test_native_raw_and_v3_single_resume_issue(self) -> None:
        import io
        root = Path(__file__).resolve().parents[3]
        tests = root / "sandbox/lf_contract_gate_test/profile_execution_runtime"
        suite = unittest.defaultTestLoader.discover(
            start_dir=str(tests), pattern="test_profile_resume_issue_request.py",
        )
        self.assertGreater(suite.countTestCases(), 0)
        stream = io.StringIO()
        result = unittest.TextTestRunner(stream=stream, verbosity=1).run(suite)
        self.assertTrue(result.wasSuccessful(), stream.getvalue())
        self.assertGreaterEqual(result.testsRun, 36, stream.getvalue())
        print(f"PASS_NATIVE_SAME_RUN_ISSUE_REGRESSION tests={result.testsRun}", flush=True)


class Step50PgDualIsolatedSimulation(unittest.TestCase):
    """Real PostgreSQL 17.6/18.7 engines, simulated RUN, rollback; NOT real writer."""
    def test_step50_sequence_rollback_pg176_pg187(self) -> None:
        import shutil
        import subprocess
        import time
        import uuid

        self.assertIsNotNone(shutil.which("docker"), "NOT_TESTED_NO_DOCKER")
        labels = [
            (0, "init_execution"), (10, "router"), (20, "profile_resolve"),
            (30, "profile_source_read"), (40, "input_validate"),
            (45, "context_admission"), (47, "research_baseline_freeze"),
            (50, "execute_profile"), (60, "output_validate"),
            (70, "semantic_judge"), (80, "report_output"),
        ]
        expected = [f"{n}|{key}|STEP_PASS_WITH_EVIDENCE" for n, key in labels]
        for image, version in (("postgres:17.6", "17.6"), ("postgres:18.7", "18.7")):
            name = "lf-step50-simulation-" + uuid.uuid4().hex[:12]
            proc = subprocess.run([
                "docker", "run", "-d", "--rm", "--name", name,
                "-e", "POSTGRES_PASSWORD=step50-isolated-fixture", image,
            ], capture_output=True, text=True, timeout=240)
            self.assertEqual(proc.returncode, 0, "PG_IMAGE_START_FAILED:" + proc.stderr[:400])
            try:
                for _ in range(60):
                    ready = subprocess.run(["docker", "exec", name, "pg_isready", "-U", "postgres"],
                                          capture_output=True, text=True, timeout=10)
                    if ready.returncode == 0:
                        break
                    time.sleep(1)
                else:
                    self.fail("PG_ISOLATED_START_TIMEOUT")
                sql = """\\set ON_ERROR_STOP on
SELECT 'PG_VERSION=' || current_setting('server_version');
BEGIN;
CREATE TEMP TABLE lf_step50_simulated_steps(
  execution_id text NOT NULL, step_order integer PRIMARY KEY,
  step_id text UNIQUE NOT NULL, status text NOT NULL,
  evidence_payload jsonb NOT NULL
) ON COMMIT DROP;
INSERT INTO lf_step50_simulated_steps
SELECT 'EXEC-STEP50-SIMULATED-NO-LIVE-WRITER', n, code,
       'STEP_PASS_WITH_EVIDENCE',
       jsonb_build_object('simulation',true,'evidence_ref','fixture://isolated')
FROM (VALUES
  (0,'init_execution'),(10,'router'),(20,'profile_resolve'),
  (30,'profile_source_read'),(40,'input_validate'),
  (45,'context_admission'),(47,'research_baseline_freeze')
) AS src(n,code);
DO $pre$
BEGIN
 IF (SELECT count(*) FROM lf_step50_simulated_steps)<>7 OR
    NOT EXISTS(SELECT 1 FROM lf_step50_simulated_steps WHERE step_id='context_admission' AND status='STEP_PASS_WITH_EVIDENCE') OR
    NOT EXISTS(SELECT 1 FROM lf_step50_simulated_steps WHERE step_id='research_baseline_freeze' AND status='STEP_PASS_WITH_EVIDENCE') THEN
   RAISE EXCEPTION 'STEP50_SIM_PREDECESSORS_NOT_READY';
 END IF;
END $pre$;
INSERT INTO lf_step50_simulated_steps
VALUES ('EXEC-STEP50-SIMULATED-NO-LIVE-WRITER',50,'execute_profile',
        'STEP_PASS_WITH_EVIDENCE',
        '{"simulation":true,"profile_output":{"traceability":{"producer":"GPT_NATIVE","source":"fixture","review_mode":"CURRENT_CONTEXT_REVIEW"}}}'::jsonb);
-- Simulate the SAME native operation transitioning 50 -> 60 -> 70 -> 80;
-- every successor requires the exact clean predecessor, never an invented pass.
INSERT INTO lf_step50_simulated_steps
SELECT 'EXEC-STEP50-SIMULATED-NO-LIVE-WRITER',60,'output_validate',
       'STEP_PASS_WITH_EVIDENCE',jsonb_build_object('simulation',true,'validator','SOURCE_BOUND')
WHERE EXISTS (SELECT 1 FROM lf_step50_simulated_steps
              WHERE step_order=50 AND status='STEP_PASS_WITH_EVIDENCE');
INSERT INTO lf_step50_simulated_steps
SELECT 'EXEC-STEP50-SIMULATED-NO-LIVE-WRITER',70,'semantic_judge',
       'STEP_PASS_WITH_EVIDENCE',jsonb_build_object('simulation',true,'review_mode','CURRENT_CONTEXT_REVIEW')
WHERE EXISTS (SELECT 1 FROM lf_step50_simulated_steps
              WHERE step_order=60 AND status='STEP_PASS_WITH_EVIDENCE');
INSERT INTO lf_step50_simulated_steps
SELECT 'EXEC-STEP50-SIMULATED-NO-LIVE-WRITER',80,'report_output',
       'STEP_PASS_WITH_EVIDENCE',jsonb_build_object('simulation',true,'terminal_simulated',true)
WHERE EXISTS (SELECT 1 FROM lf_step50_simulated_steps
              WHERE step_order=70 AND status='STEP_PASS_WITH_EVIDENCE');
DO $post$
BEGIN
 IF (SELECT count(*) FROM lf_step50_simulated_steps)<>11 OR
    (SELECT count(*) FROM lf_step50_simulated_steps WHERE status='STEP_PASS_WITH_EVIDENCE')<>11 OR
    (SELECT count(DISTINCT execution_id) FROM lf_step50_simulated_steps)<>1 OR
    EXISTS (SELECT 1 FROM lf_step50_simulated_steps WHERE evidence_payload->>'simulation' IS DISTINCT FROM 'true')
 THEN RAISE EXCEPTION 'NATIVE_SAME_RUN_0_TO_80_SIMULATION_NOT_CLEAN'; END IF;
END $post$;
SELECT step_order || '|' || step_id || '|' || status
 FROM lf_step50_simulated_steps ORDER BY step_order;
ROLLBACK;
SELECT 'ROLLBACK_EMPTY=' ||
 CASE WHEN to_regclass('pg_temp.lf_step50_simulated_steps') IS NULL THEN 'true' ELSE 'false' END;
"""
                # The minimal user string supplies NO step IDs or skill names.
                # Candidate operation SQL resolves both from isolated PostgreSQL tables
                # seeded with the exact 11-step SELECT readback (not the user prompt).
                minimum = "Ejecuta EJECUCION_PERFIL_LF para <solicitud + contexto>"
                self.assertNotIn("step 40", minimum)
                self.assertNotIn("IG_CONTEXT_PACK", minimum)
                migration = Path(__file__).resolve().parents[3] / (
                    "supabase/migrations/20261114020000_lf_profile_step40_ig_profile_owned_v1.sql")
                operation_sql = migration.read_text(encoding="utf-8")
                operation_sql = operation_sql.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
                generic_setup = r"""
BEGIN;
CREATE TABLE public.lf_activos(
 codigo_activo text, tipo_activo text, archived_at timestamptz, metadata jsonb
);
CREATE TABLE public.lf_operation_steps(
 operation_code text, step_order integer, step_id text, active boolean,
 required boolean, resolver_ref text
);
CREATE TABLE public.lf_operation_step_contracts(
 operation_code text, step_id text, status text, resolver_ref text,
 required_evidence_keys jsonb, next_if_pass text, next_if_blocked text
);
CREATE TABLE public.lf_activo_relaciones(
 id integer GENERATED ALWAYS AS IDENTITY, codigo_activo text,
 relacionado_codigo text, relacion_tipo text
);
CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text, required_operation text, handler_fn text, effect text, status text
);
INSERT INTO public.lf_activos VALUES
 ('PERFIL-IG-TEST','PERFIL',NULL,'{"input_governance_binding_mode":"DIRECT_PROFILE"}'),
 ('PERFIL-OTRA-SKILL-TEST','PERFIL',NULL,'{}');
-- Exact 11 row STEP ORDER/NAME read from active canonical DB via SELECT.
INSERT INTO public.lf_operation_steps VALUES
 ('EJECUCION_PERFIL_LF',0,'init_execution',true,true,'public.lf_profile_execution_begin_v1'),
 ('EJECUCION_PERFIL_LF',10,'router',true,true,'public.lf_router_resolve_v1'),
 ('EJECUCION_PERFIL_LF',20,'profile_resolve',true,true,'CANONICAL_PROFILE_ASSET_RESOLUTION'),
 ('EJECUCION_PERFIL_LF',30,'profile_source_read',true,true,'EXACT_PROFILE_SOURCE_READBACK'),
 ('EJECUCION_PERFIL_LF',40,'input_validate',true,true,'OPERATION_BOUND_INPUT_VALIDATE'),
 ('EJECUCION_PERFIL_LF',45,'context_admission',true,true,'OPERATION_CONTEXT_ADMISSION'),
 ('EJECUCION_PERFIL_LF',47,'research_baseline_freeze',true,true,'OPERATION_RESEARCH_BASELINE'),
 ('EJECUCION_PERFIL_LF',50,'execute_profile',true,true,'SELECTED_PROFILE_MODEL_RUNTIME'),
 ('EJECUCION_PERFIL_LF',60,'output_validate',true,true,'BOUND_PROFILE_OUTPUT_VALIDATOR'),
 ('EJECUCION_PERFIL_LF',70,'semantic_judge',true,true,'BOUND_SEMANTIC_JUDGE'),
 ('EJECUCION_PERFIL_LF',80,'report_output',true,true,'DETERMINISTIC_REPORT_OUTPUT');
INSERT INTO public.lf_operation_step_contracts
 SELECT operation_code,step_id,'ACTIVE_ENFORCEMENT',resolver_ref,'["fixture_only"]'::jsonb,
        lead(step_id) OVER (PARTITION BY operation_code ORDER BY step_order),NULL
 FROM public.lf_operation_steps;
INSERT INTO public.lf_skill_catalog_v1 VALUES
 ('IG_CONTEXT_PACK','EJECUCION_PERFIL_LF','mock_readonly_ig','READ_ONLY','READY'),
 ('OTRA_SKILL_FICTICIA','EJECUCION_PERFIL_LF','mock_readonly_other','READ_ONLY','READY');
"""
                generic_verify = r"""
SELECT 'BLOCKED_LEGACY=' || (public.lf_profile_execution_plan_v1('PERFIL-IG-TEST')->>'blocking_code');
INSERT INTO public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo) VALUES
 ('PERFIL-IG-TEST','IG_CONTEXT_PACK','USA_SKILL'),
 ('PERFIL-OTRA-SKILL-TEST','OTRA_SKILL_FICTICIA','USA_SKILL');
SELECT 'PLAN_IG=' || (p->>'status') || '|' ||
       jsonb_array_length(p->'steps') || '|' || (p#>>'{skills,0,skill_code}')
 FROM (SELECT public.lf_profile_execution_plan_v1('PERFIL-IG-TEST') AS p) x;
SELECT 'PLAN_OTHER=' || (p->>'status') || '|' ||
       jsonb_array_length(p->'steps') || '|' || (p#>>'{skills,0,skill_code}')
 FROM (SELECT public.lf_profile_execution_plan_v1('PERFIL-OTRA-SKILL-TEST') AS p) x;
CREATE TEMP TABLE simulated_operation_ledger(
 run_id text, step_order int, step_id text, status text
) ON COMMIT DROP;
INSERT INTO simulated_operation_ledger
 SELECT pr.run_id, (step->>'step_order')::int,step->>'step_id','STEP_PASS_WITH_EVIDENCE'
 FROM (VALUES ('SIM-IG','PERFIL-IG-TEST'),('SIM-OTHER','PERFIL-OTRA-SKILL-TEST'))
 pr(run_id,profile_code)
 CROSS JOIN LATERAL public.lf_profile_execution_plan_v1(pr.profile_code) plan
 CROSS JOIN LATERAL jsonb_array_elements(plan->'steps') step;
DO $generic_check$
DECLARE r record; p jsonb; n int;
BEGIN
 FOR r IN (SELECT * FROM (VALUES('SIM-IG','PERFIL-IG-TEST','IG_CONTEXT_PACK'),
                        ('SIM-OTHER','PERFIL-OTRA-SKILL-TEST','OTRA_SKILL_FICTICIA'))
           AS x(run_id,profile_code,expected_skill)) LOOP
   p:=public.lf_profile_execution_plan_v1(r.profile_code);
   SELECT count(*) INTO n FROM simulated_operation_ledger WHERE run_id=r.run_id;
   IF n<>11 OR jsonb_array_length(p->'skills')<>1
      OR p#>>'{skills,0,skill_code}' IS DISTINCT FROM r.expected_skill
      OR p->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
      OR (p->>'model_external_api')::boolean IS DISTINCT FROM false
      OR EXISTS(SELECT 1 FROM
         (SELECT step->>'next_if_pass' next_id,
           lead(step->>'step_id') OVER(ORDER BY ord) expected_next
          FROM jsonb_array_elements(p->'steps') WITH ORDINALITY AS z(step,ord)) c
        WHERE c.next_id IS DISTINCT FROM c.expected_next)
   THEN RAISE EXCEPTION 'GENERIC_DB_PLAN_NOT_VERIFIED:%',r.run_id; END IF;
 END LOOP;
END $generic_check$;
SELECT 'GENERIC_DB_PLAN_PASS='||run_id||'|'||count(*)||'/11' FROM simulated_operation_ledger
 GROUP BY run_id ORDER BY run_id;
ROLLBACK;
SELECT 'ROLLBACK_GENERIC_EMPTY=' ||
 CASE WHEN to_regclass('public.lf_operation_steps') IS NULL
     AND to_regclass('pg_temp.simulated_operation_ledger') IS NULL THEN 'true' ELSE 'false' END;
"""
                sql += "\n" + generic_setup + "\n" + operation_sql + "\n" + generic_verify

                for readiness_attempt in range(25):
                    run = subprocess.run(
                        ["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
                         "-U", "postgres", "-d", "postgres"],
                        input=sql, capture_output=True, text=True, timeout=180,
                    )
                    if run.returncode == 0:
                        break
                    # Docker's initdb starts a temporary postmaster, then stops it.
                    # pg_isready may report that temporary server; retry ONLY
                    # transport-not-ready, never a SQL/schema assertion failure.
                    if not any(marker in run.stderr for marker in (
                        "the database system is shutting down",
                        "the database system is starting up",
                        "Connection refused",
                        "No such file or directory",
                    )):
                        break
                    time.sleep(1)
                self.assertEqual(run.returncode, 0, "PG_ISOLATED_TEST_FAILED:" + run.stderr[-600:])
                values = [s.strip() for s in run.stdout.splitlines() if s.strip()]
                self.assertTrue(any(s.startswith("PG_VERSION=" + version) for s in values), values[:8])
                actual = [s for s in values if s.startswith(tuple(str(n) + "|" for n, _ in labels))]
                self.assertEqual(actual, expected)
                self.assertIn("ROLLBACK_EMPTY=true", values)
                self.assertIn("BLOCKED_LEGACY=PROFILE_LEGACY_DEPENDENCY_NOT_EXECUTABLE", values)
                self.assertIn("PLAN_IG=READY|11|IG_CONTEXT_PACK", values)
                self.assertIn("PLAN_OTHER=READY|11|OTRA_SKILL_FICTICIA", values)
                self.assertIn("GENERIC_DB_PLAN_PASS=SIM-IG|11/11", values)
                self.assertIn("GENERIC_DB_PLAN_PASS=SIM-OTHER|11/11", values)
                self.assertIn("ROLLBACK_GENERIC_EMPTY=true", values)
                print(f"PASS_GENERIC_DB_PLAN_PG_{version} IG=11/11 OTHER=11/11 ROLLBACK=true", flush=True)
                print(f"PASS_STEP50_SIMULATED_PG_{version} 11/11 ROLLBACK_EMPTY=true", flush=True)
                for step in actual:
                    print(f"PG_{version}_STEP {step}", flush=True)
            finally:
                subprocess.run(["docker", "rm", "-f", name], capture_output=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
