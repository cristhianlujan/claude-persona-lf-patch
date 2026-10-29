import json, shutil, tempfile, unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent))
import operational_coverage_v1 as opc
import compare_s26_profile_evolution_v1 as cmp

ROOT = Path(__file__).resolve().parents[3]
SLUG = "customer_financial_ux_decisioning"


class Checks(unittest.TestCase):
    DOC = {"output": {"status": "OK", "items": [1, 2, 3], "owner": {"kind": "DERIVED", "ref": "R"}, "n": {"x": [{"status": "UNRESOLVED"}]}},
           "validator": {"valid": True}}

    def ev(self, **check):
        return opc.evaluate_check(self.DOC, check)

    def test_ops(self):
        self.assertTrue(self.ev(op="eq", pointer="/output/status", value="OK"))
        self.assertFalse(self.ev(op="eq", pointer="/output/status", value="NO"))
        self.assertTrue(self.ev(op="in", pointer="/output/status", value=["OK", "X"]))
        self.assertTrue(self.ev(op="nonempty", pointer="/output/items"))
        self.assertFalse(self.ev(op="nonempty", pointer="/output/missing"))
        self.assertTrue(self.ev(op="min_len", pointer="/output/items", value=3))
        self.assertFalse(self.ev(op="min_len", pointer="/output/items", value=4))
        self.assertTrue(self.ev(op="eq", pointer="/output/items/0", value=1))

    def test_no_node_sweeps_the_whole_subtree(self):
        self.assertFalse(self.ev(op="no_node", pointer="/output", key="status", values=["UNRESOLVED"]))
        self.assertTrue(self.ev(op="no_node", pointer="/output", key="status", values=["NEEDS_MORE_EVIDENCE"]))
        self.assertFalse(self.ev(op="no_node", pointer="/output/absent", key="status", values=["UNRESOLVED"]))

    def test_if_then(self):
        then = {"op": "nonempty", "pointer": "/output/owner/ref"}
        self.assertTrue(self.ev(op="if_then", **{"if": {"op": "eq", "pointer": "/output/owner/kind", "value": "DERIVED"}}, then=then))
        self.assertTrue(self.ev(op="if_then", **{"if": {"op": "eq", "pointer": "/output/owner/kind", "value": "OTHER"}}, then={"op": "eq", "pointer": "/x", "value": 1}))
        self.assertFalse(self.ev(op="if_then", **{"if": {"op": "eq", "pointer": "/output/owner/kind", "value": "DERIVED"}}, then={"op": "eq", "pointer": "/x", "value": 1}))


def make_root(tmp, base_dir, cand_dir, base_out, cand_out, tamper=False):
    d = tmp / SLUG
    shutil.rmtree(tmp, ignore_errors=True)
    (d / "runs").mkdir(parents=True)
    case = {"schema_version": opc.CASE_SCHEMA, "profile_slug": SLUG, "case_id": "C1", "checks": [
        {"id": "K1", "pointer": "/output/status", "op": "eq", "value": "DONE"},
        {"id": "K2", "pointer": "/output/plan", "op": "nonempty"}]}
    (d / "C1.case.json").write_text(json.dumps(case))
    for name, tree, out in (("base", opc.tree_sha256(base_dir), base_out), ("cand", opc.tree_sha256(cand_dir), cand_out)):
        run = {"schema_version": opc.RUN_SCHEMA, "run_id": name, "case_id": "C1", "profile_slug": SLUG,
               "profile_tree_sha256": tree, "attestation": "NONE", "validator": {"valid": True},
               "output": out, "output_sha256": opc.canonical_sha256(out)}
        if tamper and name == "cand":
            run["output_sha256"] = "0" * 64
        (d / "runs" / f"{name}.json").write_text(json.dumps(run))
    return tmp


class Integration(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.base, self.cand = self.tmp / "base", self.tmp / "cand"
        shutil.copytree(ROOT / "profiles" / SLUG, self.base)
        shutil.copytree(self.base, self.cand)
        with open(self.cand / "contracts/main_contract.md", "a") as f:
            f.write("\nnote that changes the tree but not the structural score\n")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cmp(self, base_out, cand_out, tamper=False):
        op_root = make_root(self.tmp / "ops", self.base, self.cand, base_out, cand_out, tamper)
        return cmp.compare(ROOT, SLUG, self.base, self.cand, operational_root=op_root)

    def test_operational_improvement_alone_demonstrates_evolution(self):
        r = self.run_cmp({"status": "NEEDS", "plan": []}, {"status": "DONE", "plan": [1]})
        self.assertEqual(r["verdict"], "EVOLUTION_DEMONSTRATED")
        self.assertEqual(r["evolution_basis"], ["OPERATIONAL_COVERAGE"])
        self.assertEqual((r["operational"]["base_passed"], r["operational"]["candidate_passed"]), (0, 2))

    def test_any_rise_counts_without_a_threshold(self):
        r = self.run_cmp({"status": "NEEDS", "plan": [1]}, {"status": "DONE", "plan": [1]})
        self.assertEqual(r["verdict"], "EVOLUTION_DEMONSTRATED")

    def test_operational_regression_blocks_even_with_an_improvement(self):
        r = self.run_cmp({"status": "DONE", "plan": [1]}, {"status": "NEEDS", "plan": [1]})
        self.assertEqual(r["verdict"], "REGRESSION")
        self.assertEqual(r["operational"]["regressed_checks"], ["C1:K1"])
        r = self.run_cmp({"status": "NEEDS", "plan": [1]}, {"status": "DONE", "plan": []})
        self.assertEqual(r["verdict"], "REGRESSION")
        self.assertEqual(r["operational"]["improved_checks"], ["C1:K1"])

    def test_no_change_is_not_evolution(self):
        r = self.run_cmp({"status": "DONE", "plan": [1]}, {"status": "DONE", "plan": [1]})
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")

    def test_tampered_run_is_rejected_and_the_case_stays_unmeasured(self):
        r = self.run_cmp({"status": "NEEDS", "plan": []}, {"status": "DONE", "plan": [1]}, tamper=True)
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")
        self.assertEqual(r["operational"]["cases_unmeasured"], ["C1"])
        self.assertTrue(any(p.startswith("RUN_REJECTED") for p in r["operational"]["problems"]))

    def test_run_bound_to_another_tree_does_not_count(self):
        op_root = make_root(self.tmp / "ops", self.base, self.cand, {"status": "NEEDS", "plan": []}, {"status": "DONE", "plan": [1]})
        with open(self.cand / "contracts/main_contract.md", "a") as f:
            f.write("\nlater edit that unbinds the recorded run\n")
        r = cmp.compare(ROOT, SLUG, self.base, self.cand, operational_root=op_root)
        self.assertEqual(r["operational"]["cases_unmeasured"], ["C1"])
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")

    def test_slug_without_cases_is_not_applicable(self):
        r = cmp.compare(ROOT, SLUG, self.base, self.cand, operational_root=self.tmp / "none")
        self.assertEqual(r["operational"]["status"], "NOT_APPLICABLE")


class RepoData(unittest.TestCase):
    def test_committed_cases_and_runs_are_valid(self):
        root = ROOT / opc.OPERATIONAL_REL
        for slug_dir in sorted(p for p in root.iterdir() if p.is_dir()):
            cases, problems = opc.load_cases(root, slug_dir.name)
            runs, rejected = opc.load_runs(root, slug_dir.name, cases)
            self.assertEqual((problems, rejected), ([], []), slug_dir.name)
            self.assertTrue(cases)
            self.assertTrue(all(r["attestation"] in opc.ATTESTATIONS for r in runs))


if __name__ == "__main__":
    unittest.main()
