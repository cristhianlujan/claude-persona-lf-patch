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
                    "supabase/migrations/20261114020000_lf_profile_skill_dynamic_selection_v1.sql")
                operation_sql = migration.read_text(encoding="utf-8")
                operation_sql = operation_sql.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
                generic_setup = r"""
BEGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TEMP TABLE profile_fixture(
 profile_code text PRIMARY KEY,canonical_profile_key text,channel text,channels text[]
) ON COMMIT DROP;
-- Readback of the 10 CURRENT profile registry rows and legal channels (not a
-- list embedded in either operation Step40 or Step50).
INSERT INTO profile_fixture VALUES
 ('ACT-0051','frontend_prototype_architect_lf','PRODUCTO',ARRAY['PRODUCTO','PROGRAMACION']),
 ('PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING','customer_financial_ux_decisioning','PRODUCTO',ARRAY['PRODUCTO']),
 ('PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','cx_trust_experience_architect_lf','PRODUCTO',ARRAY['PRODUCTO']),
 ('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','evidence_lineage_reviewer_lf','OPERACIONES',ARRAY['OPERACIONES']),
 ('PERFIL-GAMIFICATION-SYSTEM-ARCHITECT','gamification_system_architect','PRODUCTO',ARRAY['PRODUCTO']),
 ('PERFIL-PRODUCT-DIRECTOR-LF','product_director_lf','PRODUCTO',ARRAY['PRODUCTO']),
 ('PERFIL-QUALITY-PACK','quality_pack','PRODUCTO',ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']),
 ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','systemic_root_cause_repair_lf','OPERACIONES',ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']),
 ('PERFIL-UI-ARCHITECT','ui_architect','PRODUCTO',ARRAY['PRODUCTO','PROGRAMACION']),
 ('PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531','ux_product_experience_architect_lf','PRODUCTO',ARRAY['PRODUCTO']);
CREATE TABLE public.lf_operation_steps (
 operation_code text,step_order integer,step_id text,active boolean,required boolean,resolver_ref text
);
CREATE TABLE public.lf_operation_step_contracts (
 operation_code text,step_id text,status text,resolver_ref text,required_evidence_keys jsonb,
 next_if_pass text,next_if_blocked text
);
CREATE TABLE public.lf_profile_selection_registry_v1 (
 profile_code text PRIMARY KEY,canonical_profile_key text,descriptor_status text
);
CREATE TABLE public.lf_profile_selector_policy_v1 (
 profile_code text PRIMARY KEY,channels text[]
);
CREATE TABLE public.lf_profile_write_authority_v1 (
 profile_code text,operation_code text,status text
);
CREATE TABLE public.lf_skill_catalog_v1 (
 skill_code text PRIMARY KEY,description text,required_operation text,handler_fn text,effect text,
 input_required text[],status text,opener_fn text,child_caller jsonb
);
CREATE TABLE public.lf_skill_invocation_v1 (
 skill_run_id text PRIMARY KEY,skill_code text,parent_execution_id text,
 profile_code text,status text,input_sha256 text,output jsonb,evidence_ref text
);
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,target_code text,status text,operation_code text,manifest jsonb
);
INSERT INTO public.lf_profile_selection_registry_v1
 SELECT profile_code,canonical_profile_key,'CURRENT' FROM profile_fixture;
INSERT INTO public.lf_profile_selector_policy_v1 SELECT profile_code,channels FROM profile_fixture;
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
 SELECT operation_code,step_id,'ACTIVE_ENFORCEMENT',resolver_ref,
        '["fixture_only"]'::jsonb,
        lead(step_id) OVER(PARTITION BY operation_code ORDER BY step_order),NULL
 FROM public.lf_operation_steps;
-- Two real catalog codes are needed for the candidate seeded OPTIONAL policies;
-- both remain DISABLED and are never called by this laboratory.
INSERT INTO public.lf_skill_catalog_v1
 (skill_code,description,required_operation,handler_fn,effect,input_required,status)
VALUES ('SCREEN_RULES_SNAPSHOT','read screen rules','EJECUCION_PERFIL_LF',
        'lf_skill_h_screen_rules_snapshot_v1','READ_ONLY',ARRAY['pantalla_codigo'],'READY'),
       ('PROFILE_UPDATE_APPLY','governed profile update','ACTUALIZACION_PERFIL_LF',
        'lf_skill_h_profile_update_propose_v1','WRITE_GOVERNED',
        ARRAY['target_code','target_path'],'READY');
"""
                generic_verify = r"""
-- All TEN real registered profile codes must have the candidate binding.
SELECT 'POLICY_10_COVERAGE='||count(*) FROM public.lf_skill_selector_policy_v1
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
SELECT 'POLICY_ENABLED_BEFORE_APPROVAL='||count(*) FROM public.lf_skill_selector_policy_v1
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' AND enabled;
SELECT 'IG_CATALOG_CANDIDATE='||status FROM public.lf_skill_catalog_v1
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
-- Only in ROLLBACK laboratory: simulate approved source, handler and policy.
UPDATE public.lf_skill_catalog_v1 SET status='READY'
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
UPDATE public.lf_skill_selection_registry_v1
 SET descriptor_status='CURRENT',source_revision='fixture-ig-current',stale_reason=NULL
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
INSERT INTO public.lf_skill_catalog_v1
(skill_code,description,required_operation,handler_fn,effect,input_required,status)
VALUES ('FICTICIA_SEMANTICA','semantica','EJECUCION_PERFIL_LF','lf_skill_h_fake_semantic_v1',
        'READ_ONLY',ARRAY['request_text'],'READY'),
       ('FICTICIA_ALTERNA','alternativa','EJECUCION_PERFIL_LF','lf_skill_h_fake_alternate_v1',
        'READ_ONLY',ARRAY['request_text'],'READY');
INSERT INTO public.lf_skill_selection_registry_v1
(skill_code,descriptor,source_kind,source_ref,source_revision,descriptor_status)
SELECT v.code,
 jsonb_build_object('schema_version','LF_SKILL_SELECTION_DESCRIPTOR_V1',
   'description',v.code,
   'selection_evidence',jsonb_build_array(
      jsonb_build_object('kind','PURPOSE','value',v.code,'source_section','fixture'))),
 'FIXTURE','fixture://descriptor/'||v.code,v.revision,'CURRENT'
FROM(VALUES ('FICTICIA_SEMANTICA','fixture-sem-1'),
            ('FICTICIA_ALTERNA','fixture-alt-1'))v(code,revision);
INSERT INTO public.lf_skill_selector_policy_v1
(profile_code,skill_code,channels,required_operation,allowed_effects,selection_mode,
 enabled,owner_decision_required,policy_evidence_ref)
SELECT f.profile_code,x.skill_code,f.channels,'EJECUCION_PERFIL_LF',
       ARRAY['READ_ONLY'],'SEMANTIC_OPTIONAL',false,true,
       'fixture://profile/'||f.profile_code
 FROM profile_fixture f
 CROSS JOIN (VALUES('FICTICIA_SEMANTICA'),('FICTICIA_ALTERNA'))x(skill_code);
-- Negative: merely enabling the candidate without owner approval must BLOCK.
UPDATE public.lf_skill_selector_policy_v1 SET enabled=true
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
SELECT 'OWNER_BLOCK='||(public.lf_profile_execution_plan_v1(
 'PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO')->>'blocking_code');
-- Simulated owner admission ONLY inside ROLLBACK, never a live decision.
UPDATE public.lf_skill_selector_policy_v1
 SET owner_decision_required=false
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
CREATE TEMP TABLE dynamic_10_profile_matrix(
 profile_code text PRIMARY KEY, deterministic text, semantic text,
 ambiguous text, stale text
) ON COMMIT DROP;
CREATE TEMP TABLE simulated_operation_ledger(
 run_id text,profile_code text,step_order int,step_id text,status text,
 PRIMARY KEY(run_id,step_order)
) ON COMMIT DROP;
DO $ten_profile_dynamic$
DECLARE r record; det jsonb; sem jsonb; bad jsonb; old jsonb;
 decision jsonb; state_det text;state_sem text;state_amb text;state_stale text;
BEGIN
 FOR r IN (SELECT * FROM profile_fixture ORDER BY profile_code) LOOP
   det:=public.lf_profile_execution_plan_v1(r.profile_code,r.channel);
   IF det->>'status'<>'READY' OR jsonb_array_length(det->'steps')<>11
      OR jsonb_array_length(det->'skills')<>1
      OR det#>>'{skills,0,skill_code}'<>'INPUT_GOVERNANCE_CONTEXT_PACK'
      OR det#>>'{skills,0,selection_mode}'<>'DETERMINISTIC_POLICY'
   THEN RAISE EXCEPTION 'TEN_PROFILE_DETERMINISTIC_FAIL:%:%',r.profile_code,det::text; END IF;
   INSERT INTO simulated_operation_ledger
   SELECT 'DET-'||r.profile_code,r.profile_code,
          (step->>'step_order')::integer,step->>'step_id','STEP_PASS_WITH_EVIDENCE'
   FROM jsonb_array_elements(det->'steps') step;
   state_det:='11/11 PASS';
   UPDATE public.lf_skill_selector_policy_v1 SET enabled=true,owner_decision_required=false
    WHERE profile_code=r.profile_code AND skill_code IN('FICTICIA_SEMANTICA','FICTICIA_ALTERNA');
   IF public.lf_profile_execution_plan_v1(r.profile_code,r.channel)->>'status'
      <>'SEMANTIC_SELECTION_REQUIRED'
   THEN RAISE EXCEPTION 'TEN_PROFILE_SEMANTIC_REQUIRED_MISSING:%',r.profile_code; END IF;
   decision:=jsonb_build_object('selected_skill_code','FICTICIA_SEMANTICA',
       'reason','fixture documented PURPOSE for scope',
       'evidence_refs',jsonb_build_array('fixture://source/'||r.profile_code),
       'descriptor_revision','fixture-sem-1','review_mode','CURRENT_CONTEXT_REVIEW');
   sem:=public.lf_profile_execution_plan_v1(r.profile_code,r.channel,decision);
   IF sem->>'status'<>'READY' OR jsonb_array_length(sem->'skills')<>2
      OR sem#>>'{skills,1,skill_code}'<>'FICTICIA_SEMANTICA'
      OR sem#>>'{skills,1,selection_mode}'<>'SEMANTIC_DESCRIPTOR'
   THEN RAISE EXCEPTION 'TEN_PROFILE_SEMANTIC_FAIL:%:%',r.profile_code,sem::text; END IF;
   INSERT INTO simulated_operation_ledger
   SELECT 'SEM-'||r.profile_code,r.profile_code,
          (step->>'step_order')::integer,step->>'step_id','STEP_PASS_WITH_EVIDENCE'
   FROM jsonb_array_elements(sem->'steps') step;
   state_sem:='11/11 PASS';
   bad:=public.lf_profile_execution_plan_v1(r.profile_code,r.channel,
     '{"selected_skill_codes":["FICTICIA_SEMANTICA","FICTICIA_ALTERNA"]}'::jsonb);
   IF bad->>'blocking_code'<>'SKILL_SEMANTIC_SELECTION_AMBIGUOUS'
   THEN RAISE EXCEPTION 'TEN_PROFILE_AMBIG_NOT_BLOCKED:%',r.profile_code; END IF;
   state_amb:='BLOCK';
   UPDATE public.lf_skill_selection_registry_v1
      SET descriptor_status='STALE_SOURCE_CHANGED' WHERE skill_code='FICTICIA_ALTERNA';
   old:=public.lf_profile_execution_plan_v1(r.profile_code,r.channel,decision);
   IF old->>'blocking_code'<>'SKILL_DESCRIPTOR_STALE_OR_MISSING'
   THEN RAISE EXCEPTION 'TEN_PROFILE_STALE_NOT_BLOCKED:%',r.profile_code; END IF;
   state_stale:='BLOCK';
   UPDATE public.lf_skill_selection_registry_v1
      SET descriptor_status='CURRENT' WHERE skill_code='FICTICIA_ALTERNA';
   UPDATE public.lf_skill_selector_policy_v1 SET enabled=false,owner_decision_required=true
    WHERE profile_code=r.profile_code AND skill_code IN('FICTICIA_SEMANTICA','FICTICIA_ALTERNA');
   INSERT INTO dynamic_10_profile_matrix VALUES(r.profile_code,state_det,state_sem,state_amb,state_stale);
 END LOOP;
 IF (SELECT count(*) FROM dynamic_10_profile_matrix)<>10 OR
    (SELECT count(*) FROM simulated_operation_ledger)<>220 OR
    (SELECT count(DISTINCT run_id) FROM simulated_operation_ledger)<>20 OR
    EXISTS(SELECT 1 FROM simulated_operation_ledger WHERE status<>'STEP_PASS_WITH_EVIDENCE')
 THEN RAISE EXCEPTION 'TEN_PROFILE_0_80_LEDGER_NOT_CLEAN'; END IF;
END $ten_profile_dynamic$;
SELECT 'TEN_PROFILE_TEST|'||profile_code||'|'||deterministic||'|'||
 semantic||'|'||ambiguous||'|'||stale FROM dynamic_10_profile_matrix ORDER BY profile_code;
SELECT 'TEN_PROFILE_MATRIX_PASS='||count(*)||'/10' FROM dynamic_10_profile_matrix;
SELECT 'TEN_PROFILE_SIMULATED_RUNS='||count(DISTINCT run_id)||'|STEPS='||count(*)
 FROM simulated_operation_ledger;
-- PROD-DIRECTOR source-bound evidence preservation test.
-- Representative completed live RUN was read by SELECT, NOT mutated or re-executed.
-- This does NOT prove a real new IG handler returned the same RAW.
CREATE TEMP TABLE pd_legacy_copy(
 original_execution_id text,legacy_ig_md5 text,legacy_status text,
 consumer text,screen_code text,ig_run_id int
) ON COMMIT DROP;
INSERT INTO pd_legacy_copy VALUES
 ('EXEC-PROFILE-GATE2-EA0514AD005350958C4D6E9C',
  'd9c0ac3a8e917fb67c7d24e7d8d2bf7d','READY','CONTEXT_PACK','B2B-AUTH-001',949);
CREATE TEMP TABLE pd_generic_compat_receipt AS
 SELECT l.*,(p->>'profile_code') AS copied_profile_code,
  (p->'steps') AS copied_steps,
  l.legacy_ig_md5 AS carried_original_ig_md5,
  'SOURCE_PRESERVATION_ONLY_NOT_REEXECUTED'::text AS evidence_limit
 FROM pd_legacy_copy l
 CROSS JOIN LATERAL public.lf_profile_execution_plan_v1(
 'PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO') p
 WHERE p->>'status'='READY';
DO $pd_compare$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pd_generic_compat_receipt
  WHERE copied_profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND jsonb_array_length(copied_steps)=11
    AND carried_original_ig_md5=legacy_ig_md5
    AND legacy_status='READY' AND consumer='CONTEXT_PACK'
    AND screen_code='B2B-AUTH-001' AND ig_run_id=949)
 THEN RAISE EXCEPTION 'PD_LEGACY_EVIDENCE_COPIED_NOT_PRESERVED'; END IF;
END $pd_compare$;
SELECT 'PD_SOURCE_COMPATIBILITY_COPY_PASS=11/11|IG_MD5='||legacy_ig_md5||
 '|LIMIT='||evidence_limit FROM pd_generic_compat_receipt;
-- The candidate invoker must preserve the 17th PRODUCT-DIRECTOR NOT_REQUIRED
-- rather than activating IG just because the profile policy is enabled.
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb
);
INSERT INTO public.lf_operation_execution
(execution_id,target_code,status,operation_code,manifest)
VALUES ('EXEC-PD-NOT-REQUIRED-COPY','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',
'EJECUCION_PERFIL_LF','{"router_profile_handoff":{"channel":"PRODUCTO"}}'::jsonb);
SELECT 'PD_MISSING_APPLICABILITY='||(public.lf_profile_skill_invoke_selected_v1(
 'EXEC-PD-NOT-REQUIRED-COPY','PRODUCTO','INPUT_GOVERNANCE_CONTEXT_PACK','{}'::jsonb
 )->>'blocking_code');
INSERT INTO public.lf_operation_execution_steps VALUES
('EXEC-PD-NOT-REQUIRED-COPY','input_validate','STEP_PASS_WITH_EVIDENCE',
 '{"input_governance":{"applicable":false,"status":"NOT_REQUIRED"}}'::jsonb);
SELECT 'PD_NOT_REQUIRED_BLOCK='||(public.lf_profile_skill_invoke_selected_v1(
 'EXEC-PD-NOT-REQUIRED-COPY','PRODUCTO','INPUT_GOVERNANCE_CONTEXT_PACK','{}'::jsonb
 )->>'blocking_code');
ROLLBACK;
SELECT 'ROLLBACK_GENERIC_EMPTY=' ||
 CASE WHEN to_regclass('public.lf_operation_steps') IS NULL
     AND to_regclass('public.lf_skill_selection_registry_v1') IS NULL THEN 'true' ELSE 'false' END;
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
                self.assertIn("POLICY_10_COVERAGE=10", values)
                self.assertIn("POLICY_ENABLED_BEFORE_APPROVAL=0", values)
                self.assertIn("IG_CATALOG_CANDIDATE=DRAFT", values)
                self.assertIn("OWNER_BLOCK=SKILL_OWNER_DECISION_REQUIRED", values)
                self.assertIn("TEN_PROFILE_MATRIX_PASS=10/10", values)
                self.assertIn("TEN_PROFILE_SIMULATED_RUNS=20|STEPS=220", values)
                matrices = [s for s in values if s.startswith("TEN_PROFILE_TEST|")]
                self.assertEqual(len(matrices), 10, matrices)
                for row in matrices:
                    self.assertEqual(row.split("|")[2:], ["11/11 PASS","11/11 PASS","BLOCK","BLOCK"])
                    print(f"PG_{version}_{row}", flush=True)
                self.assertTrue(any(s.startswith("PD_SOURCE_COMPATIBILITY_COPY_PASS=11/11|IG_MD5=d9c0ac3a8e917fb67c7d24e7d8d2bf7d|LIMIT=SOURCE_PRESERVATION_ONLY_NOT_REEXECUTED") for s in values))
                self.assertIn("PD_MISSING_APPLICABILITY=SKILL_APPLICABILITY_EVIDENCE_NOT_READY", values)
                self.assertIn("PD_NOT_REQUIRED_BLOCK=SKILL_NOT_REQUIRED_BY_INPUT_VALIDATE", values)
                print(f"PASS_PD_NOT_REQUIRED_GUARD_PG_{version} missing=BLOCKED not_required=BLOCKED", flush=True)
                self.assertIn("ROLLBACK_GENERIC_EMPTY=true", values)
                print(f"PASS_PROFILE_MATRIX_PG_{version} 10/10 DET=10 SEM=10 AMBIG_BLOCK=10 STALE_BLOCK=10 SIMULATED=20x11 ROLLBACK=true", flush=True)
                print(f"PASS_PD_COMPAT_COPY_PG_{version} 11/11 SOURCE_PRESERVATION_ONLY_NOT_REEXECUTED", flush=True)
                print(f"PASS_STEP50_SIMULATED_PG_{version} 11/11 ROLLBACK_EMPTY=true", flush=True)
                for step in actual:
                    print(f"PG_{version}_STEP {step}", flush=True)
            finally:
                subprocess.run(["docker", "rm", "-f", name], capture_output=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
