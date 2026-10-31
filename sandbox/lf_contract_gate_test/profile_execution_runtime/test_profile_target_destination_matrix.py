"""Read-only matrix tests: actual source structures are different across profiles."""
import hashlib
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
import operational_control_matrix_v1 as matrix


def bind(slug, section, index, title, change="MODIFICAR"):
    source = (ROOT / "profiles" / slug / "SKILL.md").read_bytes()
    return {
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "section_title": section, "ordered_item": index,
        "item_title": title, "change_type": change,
    }


class ProfileTargetDestinationTest(unittest.TestCase):
    PRODUCT = "product_director_lf"
    REPAIR = "systemic_root_cause_repair_lf"

    def test_product_director_anchor_from_its_own_zero_based_gate(self):
        profile = ROOT / "profiles" / self.PRODUCT
        control = bind(self.PRODUCT,
                       "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
                       0, "AUTHORITY RESOLUTION FIRST.")
        outcome = matrix.resolve_destination(profile, control)
        self.assertEqual(outcome["destination_status"], "SOURCE_ANCHORED_NOT_CANONICAL")
        self.assertEqual(outcome["destination_profile_step_id"],
                         control["section_title"] + "::0")
        self.assertEqual(outcome["blocking_code"], "CANONICAL_STEP_AUTHORITY_NOT_VERIFIED")

    def test_systemic_repair_anchor_from_its_own_capsule(self):
        profile = ROOT / "profiles" / self.REPAIR
        control = bind(self.REPAIR, "Runtime method capsule", 4,
                       "Use the smallest search strategy that can falsify the hypothesis.")
        outcome = matrix.resolve_destination(profile, control)
        self.assertEqual(outcome["destination_status"], "SOURCE_ANCHORED_NOT_CANONICAL")
        self.assertEqual(outcome["destination_profile_step_id"], "Runtime method capsule::4")

    def test_number_from_other_profile_is_not_inherited(self):
        profile = ROOT / "profiles" / self.REPAIR
        foreign = bind(self.PRODUCT,
                       "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
                       0, "AUTHORITY RESOLUTION FIRST.")
        outcome = matrix.resolve_destination(profile, foreign)
        self.assertEqual(outcome["destination_status"], "DESTINO_PENDIENTE")
        self.assertEqual(outcome["blocking_code"], "DESTINATION_SOURCE_SHA_MISMATCH")

    def test_missing_ambiguous_or_stale_destination_never_passes(self):
        profile = ROOT / "profiles" / self.PRODUCT
        valid = bind(self.PRODUCT,
                     "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
                     0, "AUTHORITY RESOLUTION FIRST.")
        for payload in [None, {}, {**valid, "source_sha256": "0" * 64},
                        {**valid, "ordered_item": 99},
                        {**valid, "change_type": "DELETE_ALL"},
                        {**valid, "section_title": "Runtime method capsule"}]:
            outcome = matrix.resolve_destination(profile, payload)
            self.assertEqual(outcome["destination_status"], "DESTINO_PENDIENTE", payload)

    def test_group2_projection_preserves_real_measurement_and_reports_unresolved(self):
        profile = ROOT / "profiles" / self.REPAIR
        cases = {"WEB-001": {"checks": [{"id": "OP01"}, {"id": "OP02"}, {"id": "OP03"}]}}
        before = {"WEB-001": {"measured": True, "run_ids": ["original-run"],
                               "attestation": ["NONE"],
                               "checks": {"OP01": False, "OP02": True, "OP03": True}}}
        after = {"WEB-001": {"measured": True, "run_ids": ["candidate-run"],
                              "attestation": ["NONE"],
                              "checks": {"OP01": True, "OP02": True, "OP03": False}}}
        mappings = {"WEB-001:OP01": bind(self.REPAIR, "Runtime method capsule", 4,
                                        "Use the smallest search strategy that can falsify the hypothesis.")}
        report = matrix.build_control_matrix(cases, before, after, mappings, profile)
        self.assertEqual(report["status"], "READ_ONLY_REPORT_NOT_AUTHORITY")
        self.assertEqual(report["summary"], {"total": 3, "mejorados": 1, "preservados": 1,
                                               "regresados": 1, "no_verificados": 0,
                                               "destinos_pendientes": 2, "destinos_solo_textuales": 1})
        self.assertEqual([r["comparison"] for r in report["rows"]],
                         ["MEJORA", "CONSERVADO", "REGRESION"])
        self.assertEqual(report["rows"][0]["original_attestation"], ["NONE"])

    def test_missing_run_never_becomes_failure_or_success(self):
        out = matrix.build_control_matrix(
            {"CASE": {"checks": [{"id": "C1"}]}},
            {"CASE": {"measured": True, "run_ids": ["base"], "checks": {"C1": True}}},
            {"CASE": {"measured": False, "run_ids": [], "checks": {}}},
            {}, ROOT / "profiles" / self.PRODUCT)
        self.assertEqual(out["rows"][0]["comparison"], "NO_VERIFICADO")
        self.assertEqual(out["rows"][0]["evolved_result"], "NO_VERIFICADO")
        self.assertEqual(out["summary"]["no_verificados"], 1)


if __name__ == "__main__":
    unittest.main()
