"""Unit tests for governed step 70 consumer: never execute a real Supabase write."""
import importlib.util
import pathlib
import unittest
import tempfile
import json
import sys
from unittest.mock import patch
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "lf_profile_step70_consume_v3.py"
spec = importlib.util.spec_from_file_location("step70", SCRIPT)
step70 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(step70)


def verdict():
    return {
        "verdict": "PASS_INDEPENDENT_SEMANTIC",
        "decision_checks": {k: {"result": True, "reason": "Verified against source", "source_refs": ["supabase://test"]} for k in step70.CHECKS},
        "producer_independence_proven": True,
        "model_call_count": 1,
        "unsupported_claims": [],
        "blocking_codes": [],
        "source_refs": ["supabase://test"],
        "resolved_context_refs": ["supabase://context"],
        "independent_semantic_receipt_ref": "github://independent-review",
        "router_direct_consistency": "NOT_TESTED",
        "counterfactual_result": "PASS",
    }


class Step70Tests(unittest.TestCase):
    def test_complete_v3_verdict(self):
        step70.check_verdict(verdict())

    def test_missing_one_of_twelve_checks_blocks(self):
        v = verdict()
        del v["decision_checks"]["counterfactual_trajectory"]
        with self.assertRaisesRegex(ValueError, "Exactly 12"):
            step70.check_verdict(v)

    def test_self_judgment_rejected(self):
        v = verdict()
        v["producer_independence_proven"] = False
        with self.assertRaisesRegex(ValueError, "Independence"):
            step70.check_verdict(v)

    def test_missing_model_call_blocks(self):
        v = verdict()
        v["model_call_count"] = 0
        with self.assertRaisesRegex(ValueError, "model call"):
            step70.check_verdict(v)

    def test_unsupported_claim_blocks(self):
        v = verdict()
        v["unsupported_claims"] = ["invented endpoint"]
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            step70.check_verdict(v)

    def test_route_divergence_blocks(self):
        v = verdict()
        v["router_direct_consistency"] = "FAIL"
        with self.assertRaisesRegex(ValueError, "divergence"):
            step70.check_verdict(v)

    def test_dry_run_with_existing_nine_steps_does_not_write(self):
        from types import SimpleNamespace
        from contextlib import redirect_stdout
        import io
        v = verdict()
        v.update({
            "execution_id": "EXEC-TEST-70",
            "candidate_sha256": "a" * 64,
            "scope_packet_sha256": "b" * 64,
        })
        steps = ["init_execution","router","profile_resolve","profile_source_read",
                 "input_validate","context_admission","research_baseline_freeze",
                 "execute_profile","output_validate"]
        rows = [{"step_id": s, "status": "STEP_PASS_WITH_EVIDENCE",
                 "evidence_payload": {}} for s in steps]
        rows[4]["evidence_payload"]["scope_authority_packet_sha256"] = "sha256:" + "b" * 64
        rows[7]["evidence_payload"]["candidate_digest"] = "sha256:" + "a" * 64
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", encoding="utf-8") as f:
            json.dump(v, f)
            f.flush()
            with patch.object(sys, "argv", ["consumer", "--execution-id", "EXEC-TEST-70", "--verdict", f.name, "--dry-run"]), \
                 patch.object(step70, "api", return_value=rows) as api, \
                 redirect_stdout(io.StringIO()) as captured:
                step70.main()
            result = json.loads(captured.getvalue())
            self.assertEqual(result["status"], "DRY_RUN_VALID")
            self.assertEqual(result["validated_payload"]["semantic_judge_result"]["verdict"], "PASS_INDEPENDENT_SEMANTIC")
            self.assertEqual(api.call_count, 1)
            self.assertEqual(api.call_args.args[0], "GET")

    def test_missing_predecessor_blocks_before_write(self):
        import io
        from contextlib import redirect_stdout
        v = verdict()
        v.update({"execution_id": "EXEC-TEST-70", "candidate_sha256": "a"*64, "scope_packet_sha256": "b"*64})
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", encoding="utf-8") as f:
            json.dump(v, f)
            f.flush()
            with patch.object(sys, "argv", ["consumer", "--execution-id", "EXEC-TEST-70", "--verdict", f.name]), \
                 patch.object(step70, "api", return_value=[]) as api:
                with self.assertRaisesRegex(ValueError, "9 predecessor"):
                    step70.main()
            self.assertEqual(api.call_count, 1)


if __name__ == "__main__":
    unittest.main()
