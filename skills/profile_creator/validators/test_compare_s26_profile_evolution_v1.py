import shutil, tempfile, unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent))
import compare_s26_profile_evolution_v1 as cmp

ROOT = Path(__file__).resolve().parents[3]
SLUG = "customer_financial_ux_decisioning"


class Proof(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.base, self.cand = self.tmp / "base", self.tmp / "cand"
        shutil.copytree(ROOT / "profiles" / SLUG, self.base)
        self._degrade(self.base)
        shutil.copytree(self.base, self.cand)

    @staticmethod
    def _degrade(profile):
        """Recreate the pre-update (2/13) profile so these tests do not depend on the live profile state."""
        for rel in ("contracts/runtime_binding.json", "validators/runtime_validate.py", "validators/runtime_semantic_utility.py"):
            (profile / rel).unlink(missing_ok=True)
        skill = profile / "SKILL.md"
        text = skill.read_text(encoding="utf-8")
        text = text.split("## Update route")[0].rstrip() + "\n"
        skill.write_text(text, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cmp(self):
        return cmp.compare(ROOT, SLUG, self.base, self.cand)

    def test_improvement_is_demonstrated(self):
        with open(self.cand / "contracts/main_contract.md", "a") as f:
            f.write("\nRuta: ACTUALIZACION_PERFIL_LF\n")
        r = self.run_cmp()
        self.assertEqual(r["verdict"], "EVOLUTION_DEMONSTRATED")
        self.assertEqual(r["improved_dimensions"], ["B02_UPDATE_GOVERNANCE"])
        self.assertEqual(r["regressed_dimensions"], [])

    def test_identical_is_not_evolution(self):
        r = self.run_cmp()
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")
        self.assertFalse(r["structural_ceiling_reached"])

    def test_regression_blocks_even_with_an_improvement(self):
        with open(self.cand / "contracts/main_contract.md", "a") as f:
            f.write("\nRuta: ACTUALIZACION_PERFIL_LF\n")
        (self.cand / "validators/validate_pack.py").unlink()
        r = self.run_cmp()
        self.assertEqual(r["verdict"], "REGRESSION")
        self.assertIn("B07_CI_PACK_VALIDATOR", r["regressed_dimensions"])
        self.assertIn("B02_UPDATE_GOVERNANCE", r["improved_dimensions"])

    def test_symlink_in_candidate_is_blocked(self):
        (self.cand / "link.md").symlink_to(self.cand / "SKILL.md")
        r = self.run_cmp()
        self.assertEqual(r["verdict"], "BLOCKED")
        self.assertIn("CANDIDATE_PROFILE_SYMLINK_FORBIDDEN", r["blocking_codes"])

    def test_missing_dirs_and_bad_slug_block(self):
        shutil.rmtree(self.cand)
        self.assertIn("CANDIDATE_PROFILE_DIR_MISSING", self.run_cmp()["blocking_codes"])
        shutil.copytree(self.base, self.cand)
        r = cmp.compare(ROOT, "../x", self.base, self.cand)
        self.assertEqual(r["verdict"], "BLOCKED")

    def test_candidate_cannot_replace_the_rules(self):
        # A candidate that ships its own evaluator or baseline contract is judged by the trusted ones.
        (self.cand / "skills/profile_creator/contracts").mkdir(parents=True)
        (self.cand / "skills/profile_creator/contracts/s26_profile_baseline_v1.json").write_text('{"dimensions":{}}')
        r = self.run_cmp()
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")
        self.assertEqual(r["required"], 13)

    def test_ceiling_flag_when_base_is_already_complete(self):
        # Base already at the structural ceiling cannot show structural improvement.
        class E:
            def evaluate(self, root, slug):
                dims = {f"B{i:02d}": {"pass": True, "code": "PASS", "evidence": None} for i in range(13)}
                return {"dimensions": dims, "score": 13, "required": 13, "blocking_codes": []}
        orig = cmp._load_evaluator
        cmp._load_evaluator = lambda _root: E()
        try:
            r = self.run_cmp()
        finally:
            cmp._load_evaluator = orig
        self.assertEqual(r["verdict"], "NO_DEMONSTRATED_IMPROVEMENT")
        self.assertTrue(r["structural_ceiling_reached"])

    def test_measure_reports_real_baseline(self):
        r = cmp.measure(ROOT, SLUG, self.base)
        self.assertEqual(r["schema"], "S26_PROFILE_MEASUREMENT_V1")
        self.assertEqual((r["score"], r["required"]), (2, 13))
        self.assertEqual(r["decision"], "UPDATE_REQUIRED")
        self.assertEqual(len(r["failed_dimensions"]), 11)
        self.assertEqual(r["proof_sha256"], cmp.measure(ROOT, SLUG, self.base)["proof_sha256"])

    def test_measure_blocks_symlink_and_missing(self):
        (self.base / "l.md").symlink_to(self.base / "SKILL.md")
        self.assertEqual(cmp.measure(ROOT, SLUG, self.base)["decision"], "BLOCKED")
        self.assertIn("PROFILE_DIR_MISSING", cmp.measure(ROOT, SLUG, self.tmp / "nope")["blocking_codes"])

    def test_proof_digest_is_deterministic(self):
        self.assertEqual(self.run_cmp()["proof_sha256"], self.run_cmp()["proof_sha256"])


if __name__ == "__main__":
    unittest.main()
