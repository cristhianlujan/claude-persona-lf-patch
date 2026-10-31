"""Read-only matrix tests: actual source structures are different across profiles."""
import json
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




class GovernedRunnerSidecarTest(unittest.TestCase):
    """Compare a local report to the already published Group 2 proof."""

    def payload(self):
        import runpy
        runner = runpy.run_path(str(ROOT / "scripts/lf_profile_update_run.py"),
                                run_name="runner_test")
        base, candidate = "a" * 64, "b" * 64
        cases = {"CASE": {"profile_slug": "product_director_lf", "case_id": "CASE",
                          "checks": [
            {"id": "C1", "pointer": "/output/status", "op": "eq", "value": "OK"},
        ]}}
        runs = [
            {"run_id": "base-run", "case_id": "CASE", "profile_tree_sha256": base,
             "attestation": "NONE", "output": {"status": "BAD"}, "validator": {"valid": True}},
            {"run_id": "candidate-run", "case_id": "CASE", "profile_tree_sha256": candidate,
             "attestation": "NONE", "output": {"status": "OK"}, "validator": {"valid": True}},
        ]
        official = {"base_tree_sha256": base, "candidate_tree_sha256": candidate,
                    "checks_total": 1, "base_passed": 0, "candidate_passed": 1,
                    "improved_checks": ["CASE:C1"], "regressed_checks": [],
                    "cases_unmeasured": []}
        proof = {"operational": official, "verdict": "EVOLUTION_DEMONSTRATED"}
        return runner, cases, runs, base, candidate, proof

    def test_projection_matches_exact_group2_without_conferring_authority(self):
        from unittest.mock import patch
        runner, cases, runs, base, candidate, proof = self.payload()
        func = runner["project_operational_matrix"]
        with patch.dict(func.__globals__, {
            "gather_operational": lambda *_: (cases, runs, base, candidate, [])}):
            report = func("product_director_lf", ROOT / "profiles/product_director_lf", proof)
        self.assertEqual(report["status"], "GROUP2_PROJECTION_MATCHED_REPORT_ONLY")
        self.assertEqual(report["summary"]["mejorados"], 1)
        self.assertEqual(report["summary"]["destinos_pendientes"], 1)
        self.assertEqual(report["destination_authority"], "UNVERIFIED")
        self.assertEqual(report["approval_effect"], "NONE")
        self.assertEqual(report["rows"][0]["original_run_ids"], ["base-run"])

    def test_mismatched_official_proof_is_not_verified(self):
        from unittest.mock import patch
        runner, cases, runs, base, candidate, proof = self.payload()
        proof["operational"]["candidate_passed"] = 0
        func = runner["project_operational_matrix"]
        with patch.dict(func.__globals__, {
            "gather_operational": lambda *_: (cases, runs, base, candidate, [])}):
            report = func("product_director_lf", ROOT / "profiles/product_director_lf", proof)
        self.assertEqual(report["status"], "NO_VERIFICADO_PROOF_OR_SOURCE")
        self.assertEqual(report["approval_effect"], "NONE")

    def test_sidecar_is_independent_file_and_replay_overwrites_atomically(self):
        import json
        import tempfile
        import runpy
        runner = runpy.run_path(str(ROOT / "scripts/lf_profile_update_run.py"), run_name="test")
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "run.json"
            state.write_text("{}", encoding="utf-8")
            report = {"schema": "LF_PROFILE_CONTROL_MATRIX_V1", "status": "READ_ONLY_REPORT_NOT_AUTHORITY"}
            path = runner["save_matrix_sidecar"](state, report)
            self.assertEqual(json.loads(Path(path).read_text()), report)
            report["status"] = "NO_VERIFICADO_PROOF_OR_SOURCE"
            self.assertEqual(path, runner["save_matrix_sidecar"](state, report))
            self.assertEqual(json.loads(Path(path).read_text()), report)
            self.assertEqual(state.read_text(), "{}")
            self.assertFalse(Path(path + ".pending").exists())




class OfficialLedgerPayloadTest(unittest.TestCase):
    """Projection is visible in existing step evidence, never a replacement gate."""

    def setUp(self):
        import runpy
        self.runner = runpy.run_path(str(ROOT / "scripts/lf_profile_update_run.py"),
                                     run_name="matrix_test")
        self.report = {
            "schema": "LF_PROFILE_CONTROL_MATRIX_V1",
            "status": "GROUP2_PROJECTION_MATCHED_REPORT_ONLY",
            "profile_slug": "systemic_root_cause_repair_lf",
            "destination_authority": "UNVERIFIED",
            "summary": {"total": 1, "mejorados": 1, "preservados": 0,
                        "regresados": 0, "no_verificados": 0, "destinos_pendientes": 1,
                        "destinos_solo_textuales": 0},
            "binding": {"base_tree_sha256": "a"*64, "candidate_tree_sha256": "b"*64},
            "rows": [{"case_id": "WEB-001", "control_id": "OP01",
                      "original_result": "FAIL", "evolved_result": "PASS",
                      "comparison": "MEJORA", "original_run_ids": ["BASE_RUN"],
                      "evolved_run_ids": ["CAND_RUN"],
                      "original_attestation": ["NONE"],
                      "evolved_attestation": ["NONE"],
                      "destination_status": "DESTINO_PENDIENTE",
                      "blocking_code": "DESTINATION_BINDING_MISSING"}],
        }

    def test_existing_step_payloads_carry_same_bound_receipt(self):
        from importlib.util import module_from_spec
        receipt = self.runner["build_matrix_receipt"](self.report, "456")
        post = self.runner["build_post_steps"](
            "EXEC-ACTUALIZACION-PERFIL-LF-OIDC-12345678-aaaa",
            "systemic_root_cause_repair_lf", "a"*40, "b"*40, "456",
            {"base_passed": 0, "candidate_passed": 1, "checks_total": 1},
            receipt)
        close = self.runner["build_close_steps"](
            "systemic_root_cause_repair_lf", "c"*40, "b"*40, "456",
            "d"*40, "e"*40, "PACK", "NO_HABILITADO", receipt)
        self.assertEqual(post[-1]["evidence_payload"]["before_after_matrix"]["control_matrix"], receipt)
        self.assertEqual(close[-1]["evidence_payload"]["control_matrix_report"], receipt)
        self.assertEqual(receipt["projection"], "FULL_ROWS")
        self.assertEqual(receipt["approval_effect"], "NONE")
        self.assertEqual(receipt["destination_authority"], "UNVERIFIED")
        self.assertEqual(receipt["proof_ref"], "actions:profile-evolution-proof:456")
        self.assertIn("destination_source_path", receipt["rows"][0])
        self.assertIn("destination_source_sha256", receipt["rows"][0])
        self.assertIn("destination_source_line", receipt["rows"][0])
        self.assertIn("change_type", receipt["rows"][0])
        for steps in (post, close):
            request = self.runner["steps_batch"](
                "EXEC-ACTUALIZACION-PERFIL-LF-OIDC-12345678-aaaa", steps)
            self.assertEqual(
                self.runner["validate_body"](request, "o/r")["action"],
                "profile_update_record_batch")

    def test_old_step_callers_work_without_matrix(self):
        steps = self.runner["build_post_steps"](
            "EXEC-ACTUALIZACION-PERFIL-LF-OIDC-12345678-aaaa", "p_x",
            "a"*40, "b"*40, "456", {})
        self.assertNotIn("control_matrix", steps[-1]["evidence_payload"]["before_after_matrix"])
        close = self.runner["build_close_steps"](
            "p_x", "c"*40, "b"*40, "456", "d"*40, "e"*40, "PACK", "NO_HABILITADO")
        self.assertNotIn("control_matrix_report", close[-1]["evidence_payload"])

    def test_report_is_bounded_with_explicit_omissions(self):
        report = dict(self.report)
        report["rows"] = [
            {**self.report["rows"][0], "control_id": f"LONG-CONTROL-{n}",
             "destination_profile_step_name": "x"*200} for n in range(60)]
        receipt = self.runner["build_matrix_receipt"](report, "456", max_chars=1600)
        self.assertGreater(receipt["row_count_omitted"], 0)
        self.assertEqual(receipt["projection"], "PARTIAL_ROWS_NOT_COMPLETE")
        self.assertEqual(receipt["row_count_omitted"]+len(receipt["rows"]), 60)
        self.assertEqual(receipt["approval_effect"], "NONE")
        # The published budget applies AFTER final counters and digest.
        serialized = json.dumps(receipt, ensure_ascii=False, separators=(",", ":"))
        self.assertLessEqual(len(serialized.encode("utf-8")), 1600)

    def test_utf8_receipt_budget_includes_digest_and_metadata(self):
        report = dict(self.report)
        report["rows"] = [{**self.report["rows"][0], "control_id": f"OP-{n}",
                           "destination_profile_step_name": "Investigación Ñandú 🔎" * 10}
                          for n in range(30)]
        limit = 1450
        receipt = self.runner["build_matrix_receipt"](report, "456", max_chars=limit)
        encoded = json.dumps(receipt, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.assertLessEqual(len(encoded), limit)
        self.assertEqual(receipt["projection"], "PARTIAL_ROWS_NOT_COMPLETE")
        self.assertEqual(len(receipt["rows"])+receipt["row_count_omitted"], 30)
        self.assertEqual(receipt["approval_effect"], "NONE")
        import hashlib
        digest_input = {k:v for k,v in receipt.items() if k!="receipt_sha256"}
        digest_bytes = json.dumps(digest_input, sort_keys=True, ensure_ascii=False,
                                  separators=(",", ":")).encode("utf-8")
        self.assertEqual(receipt["receipt_sha256"], hashlib.sha256(digest_bytes).hexdigest())

    def test_unbounded_header_fails_closed(self):
        report = dict(self.report)
        report["rows"] = []
        report["binding"] = {**report["binding"], "unexpected": "ñ"*2000}
        with self.assertRaisesRegex(self.runner["Stop"],
                                    "PROFILE_MATRIX_RECEIPT_BASE_EXCEEDS_LIMIT"):
            self.runner["build_matrix_receipt"](report, "456", max_chars=900)

    def test_invalid_report_and_proof_ref_rejected(self):
        for bad, proof in (({}, "456"), (self.report, "bogus")):
            with self.assertRaises(self.runner["Stop"]):
                self.runner["build_matrix_receipt"](bad, proof)




class TrustedCaseDestinationIntegrationTest(unittest.TestCase):
    """Control destination is derived from trusted case metadata, never a fixed number."""

    def fixture(self, slug, section, ordinal, title):
        return {
            "case_id": "SYNTHETIC",
            "profile_slug": slug,
            "checks": [{"id": "CTRL1"}],
            "destination_bindings": {
                "CTRL1": {"profile_slug": slug, "section_title": section,
                          "ordered_item": ordinal, "item_title": title,
                          "change_type": "MODIFICAR"}
            },
        }

    def test_product_own_0_is_resolved_through_case_bindings(self):
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        root = ROOT / "profiles" / slug
        bindings, issues = matrix.source_bound_bindings_from_cases({"SYNTHETIC": case}, slug, root)
        self.assertEqual(issues, [])
        destination = matrix.resolve_destination(root, bindings["SYNTHETIC:CTRL1"])
        self.assertEqual(destination["destination_status"], "SOURCE_ANCHORED_NOT_CANONICAL")
        self.assertEqual(destination["destination_profile_step_id"],
                         case["destination_bindings"]["CTRL1"]["section_title"] + "::0")

    def test_repair_own_4_is_resolved_without_product_number(self):
        slug = "systemic_root_cause_repair_lf"
        case = self.fixture(slug, "Runtime method capsule", 4,
            "Use the smallest search strategy that can falsify the hypothesis.")
        root = ROOT / "profiles" / slug
        bindings, issues = matrix.source_bound_bindings_from_cases({"SYNTHETIC": case}, slug, root)
        self.assertEqual(issues, [])
        destination = matrix.resolve_destination(root, bindings["SYNTHETIC:CTRL1"])
        self.assertEqual(destination["destination_profile_step_id"], "Runtime method capsule::4")

    def test_cross_profile_and_unknown_control_are_reported(self):
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        case["destination_bindings"]["CTRL1"]["profile_slug"] = "systemic_root_cause_repair_lf"
        case["destination_bindings"]["UNDECLARED"] = case["destination_bindings"]["CTRL1"]
        bindings, issues = matrix.source_bound_bindings_from_cases(
            {"SYNTHETIC": case}, slug, ROOT / "profiles" / slug)
        self.assertEqual(bindings, {})
        self.assertTrue(any("DESTINATION_PROFILE_MISMATCH" in value for value in issues))
        self.assertTrue(any("DESTINATION_CONTROL_NOT_DECLARED" in value for value in issues))

    def test_runner_consumes_trusted_case_mapping_end_to_end(self):
        import runpy
        from unittest.mock import patch
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        case["checks"][0].update({"pointer": "/output/status", "op": "eq", "value": "OK"})
        original_tree, candidate_tree = "a" * 64, "b" * 64
        runs = [
            {"run_id": "ORIGINAL", "case_id": "SYNTHETIC",
             "profile_tree_sha256": original_tree, "attestation": "NONE",
             "output": {"status": "BAD"}, "validator": {"valid": True}},
            {"run_id": "EVOLVED", "case_id": "SYNTHETIC",
             "profile_tree_sha256": candidate_tree, "attestation": "NONE",
             "output": {"status": "OK"}, "validator": {"valid": True}},
        ]
        official = {"operational": {
            "base_tree_sha256": original_tree, "candidate_tree_sha256": candidate_tree,
            "checks_total": 1, "base_passed": 0, "candidate_passed": 1,
            "improved_checks": ["SYNTHETIC:CTRL1"], "regressed_checks": [],
            "cases_unmeasured": []}, "verdict": "EVOLUTION_DEMONSTRATED"}
        runner = runpy.run_path(str(ROOT / "scripts/lf_profile_update_run.py"),
                                run_name="matrix_integrated_test")
        func = runner["project_operational_matrix"]
        with patch.dict(func.__globals__, {"gather_operational":
                lambda *_: ({"SYNTHETIC": case}, runs, original_tree, candidate_tree, [])}):
            report = func(slug, ROOT / "profiles" / slug, official)
        self.assertEqual(report["status"], "GROUP2_PROJECTION_MATCHED_REPORT_ONLY")
        self.assertEqual(report["summary"]["destinos_solo_textuales"], 1)
        self.assertEqual(report["summary"]["destinos_pendientes"], 0)
        self.assertEqual(report["rows"][0]["destination_profile_step_id"],
                         case["destination_bindings"]["CTRL1"]["section_title"] + "::0")
        self.assertEqual(report["destination_authority"], "UNVERIFIED")

    def test_invalid_governed_mapping_marks_projection_unverified(self):
        import runpy
        from unittest.mock import patch
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        case["destination_bindings"]["CTRL1"]["profile_slug"] = "wrong_profile"
        case["checks"][0].update({"pointer": "/output/status", "op": "eq", "value": "OK"})
        tree0, tree1 = "a" * 64, "b" * 64
        runs = [
            {"run_id": "A", "case_id": "SYNTHETIC", "profile_tree_sha256": tree0,
             "attestation": "NONE", "output": {"status": "BAD"}, "validator": {"valid": True}},
            {"run_id": "B", "case_id": "SYNTHETIC", "profile_tree_sha256": tree1,
             "attestation": "NONE", "output": {"status": "OK"}, "validator": {"valid": True}},
        ]
        official = {"operational": {
            "base_tree_sha256": tree0, "candidate_tree_sha256": tree1,
            "checks_total": 1, "base_passed": 0, "candidate_passed": 1,
            "improved_checks": ["SYNTHETIC:CTRL1"], "regressed_checks": [],
            "cases_unmeasured": []}, "verdict": "EVOLUTION_DEMONSTRATED"}
        runner = runpy.run_path(str(ROOT / "scripts/lf_profile_update_run.py"),
                                run_name="matrix_integrated_invalid_test")
        func = runner["project_operational_matrix"]
        with patch.dict(func.__globals__, {"gather_operational":
                lambda *_: ({"SYNTHETIC": case}, runs, tree0, tree1, [])}):
            report = func(slug, ROOT / "profiles" / slug, official)
        self.assertEqual(report["status"], "NO_VERIFICADO_PROOF_OR_SOURCE")
        self.assertTrue(report["destination_binding_issues"])
        self.assertEqual(report["approval_effect"], "NONE")

    def test_declared_nonexistent_anchor_is_rejected_as_evidence(self):
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        case["destination_bindings"]["CTRL1"]["item_title"] = "INVENTED_STEP"
        bindings, issues = matrix.source_bound_bindings_from_cases(
            {"SYNTHETIC": case}, slug, ROOT / "profiles" / slug)
        self.assertEqual(bindings, {})
        self.assertEqual(len(issues), 1)
        self.assertIn("DESTINATION_ANCHOR_AMBIGUOUS_OR_NOT_FOUND", issues[0])

    def test_declared_invalid_change_type_does_not_bind(self):
        slug = "systemic_root_cause_repair_lf"
        case = self.fixture(slug, "Runtime method capsule", 4,
            "Use the smallest search strategy that can falsify the hypothesis.")
        case["destination_bindings"]["CTRL1"]["change_type"] = "FORCE_DELETE"
        bindings, issues = matrix.source_bound_bindings_from_cases(
            {"SYNTHETIC": case}, slug, ROOT / "profiles" / slug)
        self.assertEqual(bindings, {})
        self.assertTrue(any("DESTINATION_CHANGE_TYPE_INVALID" in issue for issue in issues))

    def test_stale_sha_rejected_and_missing_bindings_remain_pending(self):
        slug = "product_director_lf"
        case = self.fixture(slug,
            "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
            0, "AUTHORITY RESOLUTION FIRST.")
        case["destination_bindings"]["CTRL1"]["source_sha256"] = "a" * 64
        bindings, issues = matrix.source_bound_bindings_from_cases(
            {"SYNTHETIC": case}, slug, ROOT / "profiles" / slug)
        self.assertEqual(bindings, {})
        self.assertTrue(any("DESTINATION_SOURCE_SHA_MISMATCH" in value for value in issues))
        case.pop("destination_bindings")
        bindings, issues = matrix.source_bound_bindings_from_cases(
            {"SYNTHETIC": case}, slug, ROOT / "profiles" / slug)
        self.assertEqual(bindings, {})
        self.assertEqual(issues, [])


class RealRecordedWeb001ReadbackTest(unittest.TestCase):
    """Recorded data, not a live run; attestation NONE cannot become provider proof."""

    def test_report_rows_from_existing_web001_case_and_two_stored_runs(self):
        import operational_coverage_v1 as coverage
        path = ROOT / "skills/profile_creator/operational_cases/systemic_root_cause_repair_lf"
        cases, errors = coverage.load_cases(path.parent, "systemic_root_cause_repair_lf")
        self.assertEqual(errors, [])
        self.assertIn("WEB-001", cases)
        runs, errors = coverage.load_runs(path.parent, "systemic_root_cause_repair_lf", cases)
        self.assertEqual(errors, [])
        base = next(r for r in runs if r["run_id"] == "RUN-WEB001-BASE-20261029")
        evolved = next(r for r in runs if r["run_id"] == "RUN-WEB001-CANDIDATE-20261029")
        m0 = coverage.measure({"WEB-001": cases["WEB-001"]}, runs, base["profile_tree_sha256"])
        m1 = coverage.measure({"WEB-001": cases["WEB-001"]}, runs, evolved["profile_tree_sha256"])
        outcome = matrix.build_control_matrix({"WEB-001": cases["WEB-001"]},
                   m0, m1, {}, ROOT/"profiles/systemic_root_cause_repair_lf")
        self.assertEqual(outcome["summary"]["total"], 14)
        self.assertEqual(outcome["summary"]["destinos_pendientes"], 14)
        self.assertTrue(all("NONE" in row["original_attestation"]
                            for row in outcome["rows"]))
        self.assertTrue(all(row["destination_status"] == "DESTINO_PENDIENTE"
                            for row in outcome["rows"]))
        official = coverage.compare(m0, m1)
        self.assertEqual(outcome["summary"]["mejorados"], len(official["improved_checks"]))
        self.assertEqual(outcome["summary"]["regresados"], len(official["regressed_checks"]))
        import json
        print("WEB001_TRUSTED_GROUP2_READBACK " + json.dumps({
            "case": "WEB-001",
            "base_tree": base["profile_tree_sha256"],
            "evolved_tree": evolved["profile_tree_sha256"],
            "base_run": base["run_id"],
            "evolved_run": evolved["run_id"],
            "attestation": [base["attestation"], evolved["attestation"]],
            "base_output_sha256": base["output_sha256"],
            "evolved_output_sha256": evolved["output_sha256"],
            "conditions_same": base.get("conditions") == evolved.get("conditions"),
            "checks": [
                {"id": row["control_id"], "original": row["original_result"],
                 "evolved": row["evolved_result"],
                 "comparison": row["comparison"]}
                for row in outcome["rows"]
            ],
        }, separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    unittest.main()
