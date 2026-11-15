"""Negative PG17.6/PG18.7: Quality 497B Step70 never authorizes promotion.

Source projection: SELECT public.lf_operation_execution_steps for the actual
Quality RUN, 2026-11-15. A synthetic Product Director parent is used ONLY to
reach the promotion judge gate: Quality itself has no promotion authority.
All SQL effects in ephemeral PostgreSQL containers run under BEGIN/ROLLBACK.
No production, real-rule promotion, judge invocation or receipt is simulated.
"""
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid

from test_rule_promotion_independent_step70_pgdual_v1 import (
    MIG, PREIMAGE, SCHEMA, SOURCE,
)

QUALITY_STEP70_SELECT = {
    "execution_id": "EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C",
    "step_order": 70,
    "step_status": "STEP_PASS_WITH_EVIDENCE",
    "review_mode": "CURRENT_CONTEXT_REVIEW",
    "verdict": "PASS_REVIEWED_CURRENT_CONTEXT",
    "reviewer_is_producer": True,
    "producer_independence_proven": False,
    "model_call_count": 0,
    "judge_independence_status": "NOT_PROVEN",
    "judge_invocation_kind": None,
    "judge_role": None,
    "candidate_sha256": "b9eea058ded0fc36be2a8d178162078d8f710018fc32fbc0d298632698bff443",
    "scope_sha256": "3d9e59d6725949dab79d3b4e758b10fd6b11267195d8c4161fa282d430b08a41",
    "unsupported_claims": [],
}
EXPECTED_CODE = "PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED"


def quote(s):
    return "'" + s.replace("'", "''") + "'"


class QualityCurrentContextPromotionDenialPGDual(unittest.TestCase):
    def test_pg17_pg18_current_context_denied_with_rollback(self):
        self.assertEqual(QUALITY_STEP70_SELECT["judge_independence_status"], "NOT_PROVEN")
        self.assertFalse(QUALITY_STEP70_SELECT["producer_independence_proven"])
        self.assertTrue(QUALITY_STEP70_SELECT["reviewer_is_producer"])
        self.assertEqual(QUALITY_STEP70_SELECT["model_call_count"], 0)
        self.assertEqual(QUALITY_STEP70_SELECT["review_mode"], "CURRENT_CONTEXT_REVIEW")
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED")

        migration = MIG.read_text(encoding="utf-8")
        self.assertIn(EXPECTED_CODE, migration)
        self.assertIn("NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE", migration)
        self.assertIn("PASS_INDEPENDENT_SEMANTIC", migration)
        self.assertEqual(migration.count(PREIMAGE), 1)
        # Strip transactional envelope for reversible execution on fixtures.
        body = migration.split("\nBEGIN;\n", 1)[1].rsplit("\nCOMMIT;\n", 1)[0]

        quality_review = {
            "verdict": QUALITY_STEP70_SELECT["verdict"],
            "review_mode": QUALITY_STEP70_SELECT["review_mode"],
            "reviewer_is_producer": QUALITY_STEP70_SELECT["reviewer_is_producer"],
            "producer_independence_proven": QUALITY_STEP70_SELECT["producer_independence_proven"],
            "model_call_count": QUALITY_STEP70_SELECT["model_call_count"],
            "candidate_sha256": QUALITY_STEP70_SELECT["candidate_sha256"],
            "scope_packet_sha256": QUALITY_STEP70_SELECT["scope_sha256"],
            "unsupported_claims": QUALITY_STEP70_SELECT["unsupported_claims"],
            "judge_v3_evidence": {
                "unsupported_claims": QUALITY_STEP70_SELECT["unsupported_claims"],
            },
        }
        evidence = json.dumps({
            "semantic_judge_result": quality_review,
            "judge_independence_status": QUALITY_STEP70_SELECT["judge_independence_status"],
        }, sort_keys=True, separators=(",", ":"))

        for pg in ("17.6", "18.7"):
            with self.subTest(postgres=pg):
                name = "lf-quality-promotion-negative-" + uuid.uuid4().hex[:8]
                started = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", name,
                     "-e", "POSTGRES_PASSWORD=fixture-only", "postgres:" + pg],
                    capture_output=True, text=True, timeout=180,
                )
                self.assertEqual(started.returncode, 0, started.stderr[-2000:])
                try:
                    for _ in range(90):
                        ready = subprocess.run(
                            ["docker", "exec", name, "pg_isready", "-U", "postgres"],
                            capture_output=True, text=True, timeout=10,
                        )
                        if ready.returncode == 0:
                            logs = subprocess.run(
                                ["docker", "logs", name],
                                capture_output=True, text=True, timeout=10,
                            )
                            if "PostgreSQL init process complete; ready for start up." in (
                                logs.stdout + logs.stderr
                            ):
                                break
                        time.sleep(0.6)
                    self.assertEqual(ready.returncode, 0, "POSTGRES_NOT_READY")

                    def psql(sql):
                        result = subprocess.run(
                            ["docker", "exec", "-i", name, "psql",
                             "-X", "-A", "-t", "-U", "postgres", "-d", "postgres",
                             "-v", "ON_ERROR_STOP=1"],
                            input=sql, capture_output=True, text=True, timeout=120,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr[-4000:])
                        return result.stdout

                    psql(
                        SCHEMA + "\n" + SOURCE.read_text(encoding="utf-8")
                        + "\nCREATE TRIGGER lf_rule_promotion_guard "
                        "BEFORE UPDATE ON lf_ops.reglas FOR EACH ROW "
                        "EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();"
                    )
                    livehash = psql(
                        "SELECT md5(pg_get_functiondef("
                        "'public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure));"
                    ).strip()
                    self.assertRegex(livehash, r"^[0-9a-f]{32}$")
                    governed = body.replace(PREIMAGE, livehash)

                    # Make 40/50/60 exact-hash consistent. The only semantic
                    # disqualifier is the observed same-context Step70 evidence.
                    setup = f"""
UPDATE public.lf_operation_execution_steps
   SET evidence_payload=jsonb_set(evidence_payload,
       '{{scope_authority_packet_sha256}}',
       to_jsonb('sha256:{QUALITY_STEP70_SELECT["scope_sha256"]}'::text))
 WHERE execution_id='PARENT-1' AND step_order=40;
UPDATE public.lf_operation_execution_steps
   SET evidence_payload=jsonb_set(evidence_payload,
       '{{raw_output_sha256}}',
       to_jsonb('{QUALITY_STEP70_SELECT["candidate_sha256"]}'::text))
 WHERE execution_id='PARENT-1' AND step_order IN (50,60);
UPDATE public.lf_operation_execution_steps
   SET evidence_payload={quote(evidence)}::jsonb
 WHERE execution_id='PARENT-1' AND step_order=70;
"""
                    call = """
SELECT 'PROMOTION_RESULT=' ||
 (result->>'status') || ':' || (result->>'blocking_code')
 FROM (
    SELECT public.lf_rule_promotion_request_v1(
      'PARENT-1','RULE-CAND-001',
      'negative proof from Quality current-context Step70') AS result
 ) x;
SELECT 'PROMOTION_ROWS_IN_TX=' || count(*)
 FROM public.lf_rule_promotion_v1;
"""
                    output = psql(
                        "BEGIN;\n" + governed + "\n" + setup + "\n" + call
                        + "\nROLLBACK;\n"
                        "SELECT 'PROMOTION_ROWS_AFTER_ROLLBACK=' || count(*) "
                        "FROM public.lf_rule_promotion_v1;\n"
                        "SELECT 'RULE_STATUS_AFTER_ROLLBACK=' || estado "
                        "FROM lf_ops.reglas WHERE codigo='RULE-CAND-001';"
                    )
                    expected = (
                        "PROMOTION_RESULT=BLOCKED:" + EXPECTED_CODE,
                        "PROMOTION_ROWS_IN_TX=0",
                        "PROMOTION_ROWS_AFTER_ROLLBACK=0",
                        "RULE_STATUS_AFTER_ROLLBACK=CANDIDATO",
                    )
                    for marker in expected:
                        self.assertIn(marker, output, output)
                    print(
                        f"PASS_QUALITY_497B_STEP70_PG{pg}_"
                        "PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED_ROLLBACK",
                        flush=True,
                    )
                finally:
                    subprocess.run(
                        ["docker", "rm", "-f", name],
                        capture_output=True, text=True, timeout=30,
                    )


if __name__ == "__main__":
    unittest.main()
