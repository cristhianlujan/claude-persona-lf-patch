import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

RUN = load(ROOT / "validators/run.py", "a1_skill_run")
JUDGE = load(ROOT / "judges/semantic_guard.py", "a1_skill_judge")


def valid():
    return json.loads((ROOT / "fixtures/valid_lf.json").read_text(encoding="utf-8"))


class SkillA1Tests(unittest.TestCase):
    def test_01_valid_lf(self):
        r = RUN.run(valid())
        self.assertEqual(r["status"], "VALID_OUTPUT")
        self.assertEqual(r["payload"]["schema_version"], "REQUEST_CONTEXT_V1")
        self.assertEqual(r["next_capability"], "A2")
        self.assertFalse(r["operationally_integrated"])
        self.assertEqual(JUDGE.check(valid(), r), [])

    def test_02_no_profile_or_run_required(self):
        r = RUN.run(valid())
        self.assertNotIn("profile_code", r)
        self.assertNotIn("execution_id", r)
        self.assertNotIn("profile_code", r["payload"])

    def test_03_source_identity_preserved(self):
        x=valid();r=RUN.run(x)
        self.assertEqual(r["payload"]["provided_facts"], x["provided_facts"])
        self.assertFalse(r["external_authority_verified"])

    def test_04_material_open_question(self):
        x=valid();x["ambiguities"]=[{"code":"OPEN-1","statement":"Quién autoriza la regla","materiality":"MATERIAL","resolution_state":"OPEN"}]
        r=RUN.run(x)
        self.assertEqual(r["status"],"REQUIRES_DECISION")
        self.assertIsNone(r["next_capability"])

    def test_05_missing_target(self):
        x=valid();x["target_hints"]=[]
        r=RUN.run(x)
        self.assertEqual(r["status"],"NEED_MORE_EVIDENCE")
        self.assertIn("TARGET_HINT_MISSING",r["blocking_codes"])

    def test_06_lf_to_saly_fail_closed(self):
        x=valid();x["business"]="SALY"
        r=RUN.run(x)
        self.assertEqual(r["status"],"BLOCKED")
        self.assertTrue(any("BUSINESS_BINDING_NOT_QUALIFIED" in c for c in r["blocking_codes"]))

    def test_07_no_source_invention(self):
        x=valid();r=RUN.run(x)
        r["payload"]["source_refs"].append("forged://authority")
        self.assertIn("SOURCE_REF_INVENTED",JUDGE.check(x,r))

    def test_08_no_target_invention(self):
        x=valid();r=RUN.run(x)
        r["payload"]["target_hints"].append("OTHER")
        self.assertIn("TARGET_INVENTED",JUDGE.check(x,r))

    def test_09_objective_rewrite_rejected(self):
        x=valid();r=RUN.run(x)
        r["payload"]["objective"]["desired_outcome"]="Programar un backend"
        self.assertIn("OBJECTIVE_REWRITTEN",JUDGE.check(x,r))

    def test_10_fact_ref_not_declared(self):
        x=valid();x["provided_facts"][0]["source_ref"]="forged://ref"
        r=RUN.run(x)
        self.assertEqual(r["status"],"BLOCKED")
        self.assertIn("UNSUPPORTED_PROVIDED_FACT_REF",r["blocking_codes"])

    def test_11_immutable_source(self):
        x=valid();original=copy.deepcopy(x)
        RUN.run(x)
        self.assertEqual(x,original)

    def test_12_unknown_intent_stays_declared(self):
        r=RUN.run(valid())
        self.assertEqual(r["declared_intent_kind"],"UNKNOWN")
        self.assertNotIn("development_class",r)

    def test_13_invalid_fields_fail_closed(self):
        x=valid();x["unexpected"]="foo"
        r=RUN.run(x)
        self.assertEqual(r["status"],"BLOCKED")

    def test_14_prohibited_profile_injection(self):
        x=valid();x["profile_code"]="PERFIL-PROGRAMMING-ANALYSIS-LF"
        self.assertEqual(RUN.run(x)["status"],"BLOCKED")

    def test_15_false_runtime_claim(self):
        x=valid();r=RUN.run(x);r["effects_executed"]=True
        self.assertIn("FALSE_RUNTIME_OR_EFFECTS",JUDGE.check(x,r))

    def test_16_normalize_whitespace_and_deduplicate(self):
        x=valid();x["target_hints"]=[" B2B-AUTH-001 ","B2B-AUTH-001"]
        r=RUN.run(x)
        self.assertEqual(r["status"],"VALID_OUTPUT")
        self.assertEqual(r["payload"]["target_hints"],["B2B-AUTH-001"])

    def test_17_missing_essential_intent(self):
        x=valid();x["objective"]["desired_outcome"]="  "
        r=RUN.run(x)
        self.assertEqual(r["status"],"BLOCKED")
        self.assertIn("ESSENTIAL_OBJECTIVE_MISSING",r["blocking_codes"])

    def test_18_invalid_object(self):
        self.assertEqual(RUN.run(None)["status"],"BLOCKED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
