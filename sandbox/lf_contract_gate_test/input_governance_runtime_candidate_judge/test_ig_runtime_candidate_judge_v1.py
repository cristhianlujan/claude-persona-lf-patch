import pathlib
from copy import deepcopy
import tempfile
import unittest

import ig_runtime_candidate_judge_v1 as judge


def cap(**kw):
    base = dict(
        phase="BASELINE",
        error=None,
        statuses=("CURATOR_RUNTIME_REQUIRED", "VALIDATOR_RUNTIME_REQUIRED", "COMPLETED", "NOOP_COMPLETED"),
        terminal_payload={"status": "COMPLETED", "promotion_authorized": False},
        proposal_validation_keys=("a", "b"),
        assessment_digest="a" * 32,
        family_count=47,
        pass_count=47,
        run_status="COMPLETED",
        timing_rows=6,
        timing={"rows": 6, "families_processed": 47, "duration_ms": 50000},
        elapsed_ms=51000,
        retry_status="NOOP_COMPLETED",
    )
    base.update(kw)
    return judge.FlowCapture(**base)


def graph_terminal(nonce: int) -> dict:
    def rid(n: int) -> str:
        return f"00000000-0000-4000-8000-{n:012x}"

    def sha(n: int) -> str:
        return f"{n:064x}"

    return {
        "status": "COMPLETED",
        "graph_receipts": {
            "status": "PASS",
            "ledger_execution_id": f"EXEC-IG-GRAPH-LEDGER-RUN-{nonce}-{nonce:x}",
            "orchestrator_execution_id": f"EXEC-IG-GRAPH-ORCH-RUN-{nonce}-{nonce:x}",
            "dispatch_receipt": {
                "decision": "DISPATCH_RECEIPT_ISSUED",
                "ready": True,
                "receipt_id": rid(nonce * 10 + 1),
                "receipt_sha256": sha(nonce),
            },
            "graph_receipt": {
                "status": "PASS",
                "graph_sha256": "a" * 64,
                "source_head_sha": "b" * 40,
                "consumer_readback_count": 2,
                "ledger_execution_id": f"EXEC-IG-GRAPH-LEDGER-RUN-{nonce}-{nonce:x}",
                "producer_execution_id": f"EXEC-IG-GRAPH-ORCH-RUN-{nonce}-{nonce:x}",
                "dispatch_receipt_sha256": sha(nonce),
                "receipt_ids": [rid(nonce * 10 + 2), rid(nonce * 10 + 3)],
            },
            "consumer_readback": {"status": "PASS", "matched_receipts": 2, "consumer_graph_sha256": "c" * 64},
        },
        "non_graph_evidence": {"receipt_sha256": "d" * 64},
    }


class FakeCursor:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []
        self.current = None

    def execute(self, sql, params=()):
        self.calls.append((sql, tuple(params)))
        if not self.responses:
            raise AssertionError("unexpected execute")
        self.current = self.responses.pop(0)

    def fetchone(self):
        return self.current


class JudgeUnitTests(unittest.TestCase):
    def test_sql_guard_rejects_transaction_escape(self):
        for sql in (
            "COMMIT;",
            " rollback;",
            "CREATE DATABASE x;",
            "ALTER SYSTEM SET x='y';",
            "select 1; COMMIT;",
            "select 1; /* evasive */ COMMIT;",
            "PREPARE TRANSACTION 'x';",
        ):
            with self.assertRaises(judge.JudgeError):
                judge.validate_transaction_bound_sql(sql)

    def test_sql_guard_rejects_server_io_and_external_effects(self):
        for sql in (
            "select pg_read_file('/etc/passwd');",
            "select lo_import('/tmp/x');",
            "select dblink_exec('x','delete from t');",
            "select net.http_post(url := 'https://example.test');",
        ):
            with self.assertRaises(judge.JudgeError):
                judge.validate_transaction_bound_sql(sql)

    def test_sql_guard_accepts_transactional_ddl(self):
        judge.validate_transaction_bound_sql("create or replace function x() returns int language sql as $$ select 1 $$;")

    def test_load_sql_pins_sha(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "x.sql"
            p.write_text("select 1;", encoding="utf-8")
            digest = judge.sha256_bytes(p.read_bytes())
            text, actual = judge.load_sql(p, digest)
            self.assertEqual(text, "select 1;")
            self.assertEqual(actual, digest)
            with self.assertRaises(judge.JudgeError):
                judge.load_sql(p, "0" * 64)

    def test_normalize_terminal_removes_only_volatile_identity(self):
        raw = {"run_id": 5, "validator_identity": "v", "status": "COMPLETED", "x": 1}
        self.assertEqual(judge.normalize_terminal(raw), {"status": "COMPLETED", "x": 1})

    def test_normalize_terminal_removes_nested_volatile_identity(self):
        baseline = {
            "status": "COMPLETED",
            "proposal_validation": {
                "run_id": 312,
                "validated_proposal_count": 37,
                "details": [{"latest_run_id": 311, "decision": "KEEP"}],
            },
        }
        candidate = {
            "status": "COMPLETED",
            "proposal_validation": {
                "run_id": 313,
                "validated_proposal_count": 37,
                "details": [{"latest_run_id": 999, "decision": "KEEP"}],
            },
        }
        self.assertEqual(judge.normalize_terminal(baseline), judge.normalize_terminal(candidate))
        self.assertEqual(
            judge.normalize_terminal(baseline),
            {
                "status": "COMPLETED",
                "proposal_validation": {
                    "validated_proposal_count": 37,
                    "details": [{"decision": "KEEP"}],
                },
            },
        )

    def test_graph_receipt_run_local_identities_do_not_create_false_drift(self):
        baseline = judge.normalize_terminal(graph_terminal(1))
        candidate = judge.normalize_terminal(graph_terminal(2))
        self.assertEqual(baseline, candidate)
        self.assertEqual(
            judge.compare_captures(
                cap(terminal_payload=baseline),
                cap(phase="CANDIDATE", terminal_payload=candidate),
            ),
            [],
        )
        self.assertEqual(
            baseline["graph_receipts"]["graph_receipt"]["receipt_ids"],
            ["RUN_LOCAL_RECEIPT_ORDINAL_0", "RUN_LOCAL_RECEIPT_ORDINAL_1"],
        )
        self.assertEqual(baseline["graph_receipts"]["graph_receipt"]["graph_sha256"], "a" * 64)

    def test_graph_receipt_semantic_drift_remains_blocking(self):
        baseline = judge.normalize_terminal(graph_terminal(1))
        for mutate in (
            lambda p: p["graph_receipts"]["graph_receipt"].update(graph_sha256="e" * 64),
            lambda p: p["graph_receipts"]["consumer_readback"].update(matched_receipts=1),
            lambda p: p["graph_receipts"]["dispatch_receipt"].update(ready=False),
            lambda p: p["non_graph_evidence"].update(receipt_sha256="e" * 64),
        ):
            changed = graph_terminal(2)
            mutate(changed)
            candidate = judge.normalize_terminal(changed)
            findings = judge.compare_captures(
                cap(terminal_payload=baseline),
                cap(phase="CANDIDATE", terminal_payload=candidate),
            )
            self.assertIn("TERMINAL_PAYLOAD_DRIFT", {f["code"] for f in findings})

    def test_graph_receipt_identity_list_shape_and_invalid_values_remain_blocking(self):
        baseline = judge.normalize_terminal(graph_terminal(1))
        for mutate in (
            lambda p: p["graph_receipts"]["graph_receipt"]["receipt_ids"].pop(),
            lambda p: p["graph_receipts"]["graph_receipt"]["receipt_ids"].__setitem__(
                1, p["graph_receipts"]["graph_receipt"]["receipt_ids"][0]
            ),
            lambda p: p["graph_receipts"]["dispatch_receipt"].update(receipt_id="MALFORMED"),
            lambda p: p["graph_receipts"]["graph_receipt"].update(dispatch_receipt_sha256="BAD_HASH"),
        ):
            changed = graph_terminal(2)
            mutate(changed)
            candidate = judge.normalize_terminal(changed)
            findings = judge.compare_captures(
                cap(terminal_payload=baseline),
                cap(phase="CANDIDATE", terminal_payload=candidate),
            )
            self.assertIn("TERMINAL_PAYLOAD_DRIFT", {f["code"] for f in findings})

    def test_real_flow_entrypoint_is_dispatcher_then_curator(self):
        cur = FakeCursor([
            ({"status": "CURATOR_RUNTIME_REQUIRED"},),
            ({"status": "VALIDATOR_RUNTIME_REQUIRED", "run_id": 77},),
        ])
        run_id, statuses = judge._start_governed_flow(cur, 1, "STORY_CREATOR", "INPUT_CURATOR:EDGE:input-governance-curator-v1:n9-test")
        self.assertEqual(run_id, 77)
        self.assertEqual(statuses, ("CURATOR_RUNTIME_REQUIRED", "VALIDATOR_RUNTIME_REQUIRED"))
        self.assertIn("fn_input_governance_execute", cur.calls[0][0])
        self.assertIn("fn_input_governance_curator_materialize_v1", cur.calls[1][0])
        self.assertNotIn("curator_rebind", " ".join(call[0] for call in cur.calls))

    def test_real_flow_entrypoint_fails_closed_when_dispatcher_not_ready(self):
        cur = FakeCursor([({"status": "NOOP_COMPLETED"},)])
        with self.assertRaisesRegex(judge.JudgeError, "DISPATCH_NOT_READY"):
            judge._start_governed_flow(cur, 1, "STORY_CREATOR", "INPUT_CURATOR:EDGE:input-governance-curator-v1:n9-test")

    def test_equal_flow_has_no_blocking_findings(self):
        self.assertEqual(judge.compare_captures(cap(), cap(phase="CANDIDATE")), [])

    def test_semantic_drift_blocks(self):
        candidate = cap(phase="CANDIDATE", assessment_digest="b" * 32)
        findings = judge.compare_captures(cap(), candidate)
        self.assertIn("ASSESSMENT_DIGEST_DRIFT", {f["code"] for f in findings})
        self.assertTrue(all(f["blocking"] for f in findings))

    def test_candidate_error_blocks_and_names_candidate(self):
        findings = judge.compare_captures(cap(), cap(phase="CANDIDATE", error="X:boom"))
        self.assertEqual(findings[0]["code"], "CANDIDATE_FLOW_ERROR")

    def test_timing_evidence_required(self):
        findings = judge.compare_captures(cap(), cap(phase="CANDIDATE", timing_rows=0, timing={}))
        self.assertIn("CANDIDATE_TIMING_EVIDENCE_MISSING", {f["code"] for f in findings})

    def test_receipt_never_authorizes_runtime_or_production(self):
        identity = judge.CandidateIdentity("a" * 40, "x.sql", "b" * 64)
        receipt = judge.build_receipt(identity, 1, "STORY_CREATOR", cap(), cap(phase="CANDIDATE"), [])
        self.assertEqual(receipt["verdict"], "NO_BLOCKING_FINDINGS")
        self.assertEqual(receipt["flow_entrypoint"], "DISPATCHER_CURATOR_VALIDATOR")
        self.assertFalse(receipt["production_authorized"])
        self.assertFalse(receipt["runtime_activation_authorized"])
        self.assertEqual(receipt["mutation_policy"], "ROLLBACK_ONLY_NO_PERSISTENT_EFFECT")


if __name__ == "__main__":
    unittest.main()
