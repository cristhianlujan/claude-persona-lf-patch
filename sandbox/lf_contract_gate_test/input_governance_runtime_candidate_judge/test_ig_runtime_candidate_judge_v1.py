import pathlib
import tempfile
import unittest

import ig_runtime_candidate_judge_v1 as judge


def cap(**kw):
    base = dict(
        phase="BASELINE",
        error=None,
        statuses=("VALIDATOR_RUNTIME_REQUIRED", "COMPLETED", "NOOP_COMPLETED"),
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
        self.assertFalse(receipt["production_authorized"])
        self.assertFalse(receipt["runtime_activation_authorized"])
        self.assertEqual(receipt["mutation_policy"], "ROLLBACK_ONLY_NO_PERSISTENT_EFFECT")


if __name__ == "__main__":
    unittest.main()
