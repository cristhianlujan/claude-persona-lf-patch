import runpy
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
M = runpy.run_path(str(ROOT / "scripts" / "lf_profile_update_run.py"), run_name="runner_test")
REPO = "o/r"
EX = "EXEC-ACTUALIZACION-PERFIL-LF-OIDC-12345678-aaaa"
A, B = "a" * 40, "b" * 40
PROOF = {"decision": "UPDATE_REQUIRED", "update_basis": ["OPERATIONAL_COVERAGE"], "score": 15, "required": 15,
         "proof_sha256": "c" * 64, "schema": "S26_PROFILE_MEASUREMENT_V1", "profile_slug": "p_x", "blocking_codes": [], "failed_dimensions": []}
OP = {"base_passed": 4, "candidate_passed": 9, "checks_total": 9, "semantic_pending": ["a", "b"]}


class RunnerBuildersTest(unittest.TestCase):
    def valid(self, steps):
        return M["validate_body"](M["steps_batch"](EX, steps), REPO)

    def test_pre_steps_pass_the_real_issue_validator_and_cover_the_chain(self):
        steps = M["build_pre_steps"]("p_x", "PERFIL-X", A, "123", PROOF, [{"path": "profiles/p_x/SKILL.md", "blob_sha": "d" * 40}], ["WEB:OP01"])
        self.assertEqual([s["step_id"] for s in steps], ["router", "profile_resolve", "baseline_read", "method_selection", "evolution_decision", "change_scope", "regression_plan", "pre_write_execution_binding_gate"])
        self.assertEqual(self.valid(steps)["action"], "profile_update_record_batch")

    def test_pre_write_binds_the_anchor_revision_without_rebind(self):
        steps = M["build_pre_steps"]("p_x", "PERFIL-X", A, "123", PROOF, [], ["x"])
        pre = steps[-1]["evidence_payload"]
        self.assertEqual(pre["bound_revision"], {"revision_sha": A})
        self.assertIs(pre["rebind_performed"], False)

    def test_post_and_close_steps_are_valid_and_judge_is_declared_not_independent(self):
        post = M["build_post_steps"](EX, "p_x", A, B, "456", OP)
        self.assertEqual([s["step_id"] for s in post], ["deterministic_validation", "semantic_judge", "regression_after"])
        self.assertIs(post[1]["evidence_payload"]["independent"], False)
        self.valid(post)
        close = M["build_close_steps"]("p_x", "e" * 40, B, "456", "f" * 40, "1" * 40, "PACK", "NO_HABILITADO")
        self.assertEqual([s["step_id"] for s in close], ["post_merge_reconcile", "close", "report_output"])
        self.valid(close)

    def test_unknown_action_is_rejected_by_the_validator(self):
        with self.assertRaises(ValueError):
            M["validate_body"]({"schema_version": "LF_PROFILE_UPDATE_REQUEST_V1", "action": "other"}, REPO)



class GovernedIssueTransportTest(unittest.TestCase):
    def test_transport_emits_labeled_event_after_issue_exists(self):
        class FakeGh:
            repo = REPO
            dry = False

            def __init__(self):
                self.calls = []

            def api(self, path, method="GET", body=None):
                self.calls.append((path, method, body))
                if path == "issues" and method == "POST":
                    return {"number": 99}
                if path == "issues/99/labels" and method == "POST":
                    return [{"name": "lf-profile-update-governed"}]
                if path.startswith("actions/workflows/"):
                    return {"workflow_runs": [{"id": 100, "status": "completed"}]}
                raise AssertionError(("unexpected API call", path, method))

            def wait(self, fn, what, timeout=900, every=15):
                # Simulate a new workflow run only after the issue is labeled.
                self.assert_labeled = any(path == "issues/99/labels" for path, _, _ in self.calls)
                assert self.assert_labeled, "label event missing before polling"
                return {"id": 101, "status": "completed", "conclusion": "success"}

        gh = FakeGh()
        request = {"schema_version": "LF_PROFILE_UPDATE_REQUEST_V1", "action": "profile_evolution_proof",
                   "mode": "measure", "profile_slug": "p_x",
                   "base_sha": A, "candidate_sha": "0" * 40}
        run_id = M["submit"](gh, "Proof", request, [])
        self.assertEqual(run_id, 101)
        creates = [c for c in gh.calls if c[0] == "issues" and c[1] == "POST"]
        labels = [c for c in gh.calls if c[0] == "issues/99/labels" and c[1] == "POST"]
        self.assertEqual(len(creates), 1)
        self.assertNotIn("labels", creates[0][2])
        self.assertEqual(labels, [("issues/99/labels", "POST", {"labels": ["lf-profile-update-governed"]})])
        self.assertLess(gh.calls.index(creates[0]), gh.calls.index(labels[0]))

    def test_dry_run_does_not_open_or_label_issue(self):
        class FakeGh:
            repo = REPO
            dry = True
            def api(self, *args, **kwargs):
                raise AssertionError("dry-run attempted an API call")

        request = {"schema_version": "LF_PROFILE_UPDATE_REQUEST_V1", "action": "profile_evolution_proof",
                   "mode": "measure", "profile_slug": "p_x",
                   "base_sha": A, "candidate_sha": "0" * 40}
        log = []
        self.assertIsNone(M["submit"](FakeGh(), "Proof", request, log))
        self.assertEqual(len(log), 1)


class PreflightTest(unittest.TestCase):
    CASES = {"C1": {}, "C2": {}}

    def run_for(self, case_id, tree):
        return {"case_id": case_id, "profile_tree_sha256": tree}

    def test_nothing_missing_when_both_trees_have_a_run_per_case(self):
        runs = [self.run_for(c, t) for c in self.CASES for t in ("B" * 64, "C" * 64)]
        self.assertEqual(M["plan_missing"]("p_x", self.CASES, runs, "B" * 64, "C" * 64), [])

    def test_missing_candidate_run_says_what_where_and_which_hash(self):
        runs = [self.run_for(c, "B" * 64) for c in self.CASES]
        miss = M["plan_missing"]("p_x", self.CASES, runs, "B" * 64, "C" * 64)
        self.assertEqual(len(miss), 2)
        self.assertEqual({m["bind_to"]["profile_tree_sha256"] for m in miss}, {"C" * 64})
        self.assertTrue(all(m["where"].startswith("skills/profile_creator/operational_cases/p_x/runs/RUN-") for m in miss))
        self.assertTrue(all("profile_tree_sha256 (hash below)" in m["required_fields"] for m in miss))

    def test_a_run_bound_to_another_tree_does_not_count(self):
        runs = [self.run_for("C1", "D" * 64), self.run_for("C2", "D" * 64)]
        self.assertEqual(len(M["plan_missing"]("p_x", self.CASES, runs, "B" * 64, "C" * 64)), 4)

    def test_blocked_carries_code_why_missing_and_how(self):
        b = M["Blocked"]("X", "why", [{"what": "w"}], "how")
        self.assertEqual(set(b.detail), {"status", "code", "why", "missing", "how"})
        self.assertEqual(b.detail["status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
