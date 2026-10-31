"""Regression tests: problem-by-problem read-only projection on the EXISTING Group2 evaluator."""
import json
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
M = runpy.run_path(str(ROOT / "skills/profile_creator/validators/operational_coverage_v1.py"))
report = M["problem_comparison_report"]
echeck = M["evaluate_check"]


def case():
    p = (ROOT / "skills/profile_creator/operational_cases"
         / "systemic_root_cause_repair_lf/WEB-001.case.json")
    return json.loads(p.read_text(encoding="utf-8"))


def run(tree, ident, attestation="NONE", exact_input=None):
    out = {
        "owner": {"authority_kind": "DERIVED_PROPOSAL" if ident == "old" else "UNKNOWN"},
        "policy_resolution": [] if ident == "old" else [
            {"lookups": [{"level": "N1"}, {"level": "N2"}]}],
        "systemic_root_cause": {"status": "ESTABLISHED" if ident == "old" else "HYPOTHESIS",
                                "statement": ident},
        "first_bad_control": {"statement": "retry >3 versus >=3" if ident == "new" else "untyped"},
        "escape_control": {"statement": "consumer unverified" if ident == "new" else "missing lineage"},
        "current_uncertainties": [], "hard_guard": {"fail_closed_condition": "block unsafe"},
        "next_gate": {"gate": "REVIEW"}, "blocking_codes": [],
        "planned_regressions": [], "acceptance_criteria": [],
    }
    value = {"schema_version": "PROFILE_OPERATIONAL_RUN_V1", "case_id": "WEB-001",
             "profile_slug": "systemic_root_cause_repair_lf",
             "profile_tree_sha256": tree, "run_id": ident,
             "output_sha256": M["canonical_sha256"](out),
             "attestation": attestation, "validator": {"valid": True}, "output": out}
    if exact_input is not None:
        value["input_literal"] = exact_input
    return value


class ProblemComparisonTest(unittest.TestCase):
    def setUp(self):
        self.c = case()
        self.base = run("a"*64, "old")
        self.evolved = run("b"*64, "new")

    def report(self, old=None, new=None, case_override=None):
        cs = {"WEB-001": self.c if case_override is None else case_override}
        return report(cs, [old or self.base, new or self.evolved], "a"*64, "b"*64)

    def test_14_original_controls_intact(self):
        self.assertEqual(len(self.c["checks"]), 14)
        self.assertEqual(len({c["id"] for c in self.c["checks"]}), 14)

    def test_two_questions_and_all_fields_side_by_side(self):
        r = self.report()
        self.assertEqual(r["status"], "READ_ONLY_REPORT_NOT_AUTHORITY")
        self.assertEqual(len(r["rows"]), 2)
        self.assertEqual({x["problem_id"] for x in r["rows"]},
                         {"DISCOVERY_OF_APPLICABLE_RULE_OWNER", "CONTROLLED_RETRY_AND_READMISSION"})
        for x in r["rows"]:
            self.assertIn("original", x)
            self.assertIn("evolved", x)
            self.assertEqual(x["semantic_verdict"], "NO_VERIFICADO_PENDING_INDEPENDENT_JUDGE")
            self.assertEqual(x["evidence_status"], "PREVIEW_INPUT_IDENTITY_UNVERIFIED")
            self.assertTrue(x["original"]["runs"][0]["fields"])
            self.assertTrue(x["evolved"]["runs"][0]["fields"])

    def test_conditional_pass_is_flagged_vacuous(self):
        r = self.report()
        governance = r["rows"][0]
        c = next(x for x in governance["controls"]
                 if x["control_id"] == "OP14_DERIVED_OWNER_DECLARED_RULE_SEARCH")
        self.assertFalse(c["original_vacuous_conditional"])
        self.assertTrue(c["evolved_vacuous_conditional"])
        self.assertEqual(c["original"], "FAIL")
        self.assertEqual(c["evolved"], "PASS")

    def test_matching_input_does_not_claim_semantic_certification(self):
        old = run("a"*64, "old", "RUNTIME_ATTESTED", "SAME LITERAL")
        new = run("b"*64, "new", "RUNTIME_ATTESTED", "SAME LITERAL")
        x = self.report(old, new)["rows"][0]
        self.assertEqual(x["evidence_status"], "PREVIEW_ATTESTATION_CLAIM_UNVERIFIED")
        self.assertFalse(x["attestation_verified_independently"])
        self.assertEqual(x["input_identity_level"], "RECORDED_LITERAL_MATCH_ONLY")
        self.assertTrue(x["same_input_literal_verified"])
        self.assertEqual(x["semantic_verdict"], "NO_VERIFICADO_PENDING_INDEPENDENT_JUDGE")

    def test_different_input_remains_preliminary(self):
        old = run("a"*64, "old", "RUNTIME_ATTESTED", "A")
        new = run("b"*64, "new", "RUNTIME_ATTESTED", "B")
        self.assertEqual(self.report(old, new)["rows"][0]["evidence_status"],
                         "PREVIEW_INPUT_IDENTITY_UNVERIFIED")

    def test_not_universal_when_other_case_has_no_dimensions(self):
        plain = dict(self.c)
        plain.pop("comparison_dimensions", None)
        self.assertEqual(self.report(case_override=plain)["rows"], [])

    def test_missing_run_is_unmeasured(self):
        r = report({"WEB-001": self.c}, [self.base], "a"*64, "b"*64)
        self.assertTrue(all(x["evidence_status"] == "UNMEASURED" for x in r["rows"]))

    def test_existing_group2_evaluate_embeds_report_without_changing_verdict(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            op_root = root / 'operational_cases'
            slug = 'systemic_root_cause_repair_lf'
            source = op_root / slug
            (source / 'runs').mkdir(parents=True)
            (source / 'WEB-001.case.json').write_text(
                json.dumps(self.c, ensure_ascii=False), encoding='utf-8')
            base_dir = root / 'base_profile'
            evolved_dir = root / 'evolved_profile'
            for directory, value in ((base_dir, 'base'), (evolved_dir, 'evolved')):
                directory.mkdir()
                (directory / 'SKILL.md').write_text(value, encoding='utf-8')
            bsha = M['tree_sha256'](base_dir)
            esha = M['tree_sha256'](evolved_dir)
            old = run(bsha, 'old', 'NONE', 'SAME WEB-001')
            new = run(esha, 'new', 'NONE', 'SAME WEB-001')
            for name, record in (('old', old), ('new', new)):
                (source / 'runs' / (name + '.json')).write_text(
                    json.dumps(record, ensure_ascii=False), encoding='utf-8')
            out = M['evaluate'](op_root, slug, base_dir, evolved_dir)
            self.assertEqual(out['status'], 'MEASURED')
            self.assertIn('functional_problem_comparison', out)
            matrix = out['functional_problem_comparison']
            self.assertEqual(len(matrix['rows']), 2)
            self.assertEqual(matrix['rows'][0]['original']['runs'][0]['raw_file_ref'],
                             slug + '/runs/old.json')
            self.assertEqual(matrix['rows'][0]['evolved']['runs'][0]['raw_file_ref'],
                             slug + '/runs/new.json')
            self.assertEqual(matrix['rows'][0]['evidence_status'], 'PREVIEW_UNATTESTED')
            self.assertEqual(matrix['rows'][0]['semantic_verdict'],
                             'NO_VERIFICADO_PENDING_INDEPENDENT_JUDGE')
            a = M['measure']({'WEB-001': self.c}, [old, new], bsha)
            b = M['measure']({'WEB-001': self.c}, [old, new], esha)
            original_result = M['compare'](a, b)
            for key in ('checks_total', 'base_passed', 'candidate_passed',
                        'improved_checks', 'regressed_checks', 'cases_unmeasured'):
                self.assertEqual(out[key], original_result[key])

    def test_duplicate_problem_id_is_not_reported_twice(self):
        malformed = dict(self.c)
        dims = list(self.c['comparison_dimensions'])
        malformed['comparison_dimensions'] = dims + [dict(dims[0])]
        x = self.report(case_override=malformed)
        self.assertEqual(len(x['rows']), 2)
        self.assertIn(
            'COMPARISON_DIMENSION_BINDING_INVALID:WEB-001:DISCOVERY_OF_APPLICABLE_RULE_OWNER',
            x['issues'])

    def test_conditional_applicability_counts_in_multi_run(self):
        old2 = run('a'*64, 'new')
        old2['run_id'] = 'old-vacant'
        new2 = run('b'*64, 'new')
        new2['run_id'] = 'new-vacant'
        x = report({'WEB-001': self.c},
                   [self.base, old2, self.evolved, new2], 'a'*64, 'b'*64)
        row = next(c for c in x['rows'][0]['controls']
                   if c['control_id'] == 'OP14_DERIVED_OWNER_DECLARED_RULE_SEARCH')
        self.assertTrue(row['original_applicability']['conditional_partially_vacuous'])
        self.assertEqual(row['original_applicability']['antecedent_true'], 1)
        self.assertTrue(row['evolved_applicability']['conditional_vacuous'])
        self.assertEqual(row['evolved_applicability']['antecedent_true'], 0)

    def test_owner_and_retry_answers_have_explicit_column_fields(self):
        old = run('a'*64, 'old')
        new = run('b'*64, 'new')
        rows = self.report(old, new)['rows']
        governance, retry = rows
        self.assertEqual(governance['original']['runs'][0]['fields'][0]['pointer'],
                         '/output/owner/status')
        self.assertEqual(governance['evolved']['runs'][0]['fields'][0]['pointer'],
                         '/output/owner/status')
        new_retry = retry['evolved']['runs'][0]['fields']
        target = next(x for x in new_retry
                      if x['pointer'] == '/output/first_bad_control/statement')
        self.assertTrue(target['present'])
        self.assertIn('retry >3 versus >=3', target['preview'])
    def test_untrusted_run_path_claim_is_overridden_by_loader(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            slug = 'systemic_root_cause_repair_lf'
            directory = root / slug / 'runs'
            directory.mkdir(parents=True)
            (root / slug / 'WEB-001.case.json').write_text(
                json.dumps(self.c), encoding='utf-8')
            fake = run('a'*64, 'old')
            fake['_trusted_run_file'] = '../../fake.json'
            (directory / 'actual.json').write_text(
                json.dumps(fake), encoding='utf-8')
            cases, problems = M['load_cases'](root, slug)
            runs, rejects = M['load_runs'](root, slug, cases)
            self.assertFalse(problems)
            self.assertFalse(rejects)
            self.assertEqual(runs[0]['_trusted_run_file'], slug + '/runs/actual.json')

    def test_declared_provider_attestation_never_promoted_to_verified(self):
        base = run('a'*64, 'old', 'RUNTIME_ATTESTED', 'LITERAL')
        evolved = run('b'*64, 'new', 'RUNTIME_ATTESTED', 'LITERAL')
        for arm in self.report(base, evolved)['rows']:
            self.assertEqual(arm['evidence_status'],
                             'PREVIEW_ATTESTATION_CLAIM_UNVERIFIED')
            self.assertFalse(arm['attestation_verified_independently'])

    def test_invalid_control_binding_never_claimed(self):
        malformed = dict(self.c)
        malformed["comparison_dimensions"] = [{
            "problem_id": "UNTRUSTED", "question": "Question",
            "output_pointers": ["/output/owner"], "control_ids": ["MADE_UP_CONTROL"]
        }]
        x = self.report(case_override=malformed)
        self.assertEqual(x["rows"], [])
        self.assertIn("COMPARISON_DIMENSION_BINDING_INVALID:WEB-001:UNTRUSTED", x["issues"])


if __name__ == "__main__":
    unittest.main()
