#!/usr/bin/env python3
"""Checks physical model-context delivery and guardrails, not simulated LLM quality."""
from __future__ import annotations
import importlib.util, json, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
import sys
sys.path.insert(0,str(HERE))
import build_shadow_v1 as runner

class ShadowDeliveryTests(unittest.TestCase):
    def test_six_real_tasks_not_multiple_choice(self):
        obj=json.loads((HERE/"cases_v1.json").read_text())
        rows=obj["cases"]
        self.assertEqual(len(rows),6)
        self.assertEqual(len({x["case_id"] for x in rows}),6)
        self.assertEqual(sum(x["category"]=="SPECIALIZE" for x in rows),3)
        self.assertEqual(sum(x["category"]=="ADAPT" for x in rows),2)
        self.assertEqual(sum(x["category"]=="PRESERVATION" for x in rows),1)
        self.assertTrue(all(len(x["prompt"])>100 and not x.get("options") for x in rows))
    def test_both_arms_same_prompt_and_methods_physically_projected(self):
        with tempfile.TemporaryDirectory(prefix="pe10c3-shadow-") as tmp:
            repo=HERE.parents[3]
            revision=runner.git(repo,"rev-parse","HEAD^{commit}")
            r=runner.compile_pair(repo,revision,Path(tmp))
            self.assertEqual(r["status"],"PROJECTION_PASS_EXECUTION_PENDING")
            self.assertEqual(r["paired_run_count"],12)
            for name,p in r["profiles"].items():
                self.assertEqual(p["model_source_delivery"],"PASS")
                self.assertTrue(p["source_unchanged"])
                b=Path(p["baseline_model_context_path"]).read_text()
                d=Path(p["candidate_model_context_path"]).read_text()
                self.assertNotEqual(runner.sha(b),runner.sha(d))
                self.assertNotIn("### Behavioral method:",b)
                self.assertIn("### Behavioral method:",d)
                self.assertGreater(len(d),len(b))
            by_case={}
            for row in r["paired_assignments"]:
                by_case.setdefault(row["case_id"],[]).append(row)
                self.assertEqual(row["raw_response_status"],"NOT_EXECUTED")
                self.assertIs(row["model_provider_attested"],False)
                self.assertEqual(row["runtime_binding_status"],"REQUEST_PREVIEW_PASS")
                self.assertEqual(len(row["runtime_request_sha256"]),64)
                self.assertEqual(len(row["runtime_profile_source_sha256"]),64)
            self.assertEqual(len(by_case),6)
            for pair in by_case.values():
                self.assertEqual(len(pair),2)
                self.assertEqual({x["arm"] for x in pair},{"A_ORIGINAL","D_SHADOW"})
                self.assertEqual(pair[0]["input_sha256"],pair[1]["input_sha256"])
    def test_frozen_projection_snapshot_exact(self):
        with tempfile.TemporaryDirectory(prefix="pe10c3-frozen-") as tmp:
            repo=HERE.parents[3]
            revision=runner.git(repo,"rev-parse","HEAD^{commit}")
            result=runner.compile_pair(repo,revision,Path(tmp))
            for slug,meta in result["profiles"].items():
                for arm in ("baseline","candidate"):
                    projected=Path(meta[arm+"_model_context_path"]).read_text()
                    frozen=(HERE/"frozen_contexts"/(slug+"_"+arm+"_model_context.md")).read_text()
                    self.assertEqual(projected,frozen)
                    self.assertEqual(runner.sha(projected),meta[arm+"_context_sha256"])
    def test_bad_heading_rejected(self):
        with self.assertRaisesRegex(ValueError,"METHOD_HEADING_INVALID"):
            runner.inject("# Demo\n## Purpose\nabc\n","Purpose","## Not projected\n")
    def test_missing_section_rejected(self):
        with self.assertRaisesRegex(ValueError,"TARGET_SECTION_NOT_UNIQUE"):
            runner.inject("# Demo\n## Purpose\nabc\n","Different","### Behavioral method: x\n1. Test")
    def test_duplicate_section_rejected(self):
        with self.assertRaisesRegex(ValueError,"DUPLICATE_H2"):
            runner.sections("# Demo\n## Purpose\n## Purpose\n")
    def test_projection_fails_for_missing_section(self):
        with self.assertRaisesRegex(ValueError,"PROJECTION_SECTION_MISSING"):
            runner.projected("# Demo\n## Purpose\nabc\n",["Not listed"])
    def test_rubric_frozen_no_auto_pass(self):
        rubric=json.loads((HERE/"private_oracle_v1.json").read_text())
        self.assertEqual(len(rubric["case_rubrics"]),6)
        self.assertEqual(sum(len(r["criteria"]) for r in rubric["case_rubrics"]),30)
        self.assertEqual(rubric["admission_rules"]["critical_regressions_max"],0)
        self.assertTrue(rubric["admission_rules"]["original_and_candidate_outputs_must_be_real"])
        self.assertTrue(rubric["blind_evaluator_required"])

if __name__=="__main__":unittest.main()
