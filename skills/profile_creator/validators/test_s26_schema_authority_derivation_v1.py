import shutil, tempfile, unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent))
import evaluate_s26_profile_baseline as ev

ROOT = Path(__file__).resolve().parents[3]


class Derivation(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "schemas").mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def make(self, schemas, skill_text):
        for n in schemas:
            (self.tmp / "schemas" / n).write_text("{}")
        (self.tmp / "SKILL.md").write_text(skill_text)
        return ev.schema_authority_derivation(self.tmp)

    def test_skill_enumerating_exactly_all_schemas_is_derivable(self):
        r = self.make(["a.schema.json", "b.schema.json"], "use `schemas/a.schema.json` and `schemas/b.schema.json`")
        self.assertEqual(r["status"], "DERIVED_FROM_SKILL")
        self.assertEqual(r["schemas"], ["a.schema.json", "b.schema.json"])
        self.assertTrue(r["requires_semantic_confirmation"])

    def test_missing_reference_is_not_derivable(self):
        self.assertIsNone(self.make(["a.schema.json", "b.schema.json"], "only `schemas/a.schema.json`"))

    def test_reference_to_a_schema_that_does_not_exist_is_not_derivable(self):
        self.assertIsNone(self.make(["a.schema.json", "b.schema.json"],
                                    "schemas/a.schema.json schemas/b.schema.json schemas/c.schema.json"))

    def test_single_schema_or_no_skill_is_not_derivable(self):
        self.assertIsNone(self.make(["a.schema.json"], "schemas/a.schema.json"))
        shutil.rmtree(self.tmp / "schemas")
        self.assertIsNone(ev.schema_authority_derivation(self.tmp))


class RealProfiles(unittest.TestCase):
    def test_ui_architect_is_no_longer_blocked_but_still_needs_update(self):
        r = ev.evaluate(ROOT, "ui_architect")
        self.assertEqual(r["decision"], "UPDATE_REQUIRED")
        self.assertEqual(r["blocking_codes"], [])
        self.assertEqual(r["authority_derivation"]["status"], "DERIVED_FROM_SKILL")
        self.assertFalse(r["dimensions"]["B03_RUNTIME_BINDING"]["pass"])
        self.assertEqual(r["dimensions"]["B04_RUNTIME_SCHEMA"]["code"], "RUNTIME_SCHEMA_BINDING_DERIVED_FROM_SKILL")

    def test_profiles_with_a_binding_are_unchanged(self):
        for slug in ("product_director_lf", "systemic_root_cause_repair_lf"):
            r = ev.evaluate(ROOT, slug)
            self.assertNotIn("authority_derivation", r, slug)


if __name__ == "__main__":
    unittest.main()
