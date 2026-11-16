"""V2 regressions: evidence accounting, contract meaning, PASS and SQL safety.

Synthetic mutations prove validator behavior only. The committed real pilot
retains historical runtime provenance and FLOW_NOT_ACCREDITED.
"""
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from jsonschema import Draft202012Validator

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
sys.path.insert(0, str(PACK / "scripts"))
sys.path.insert(0, str(PACK / "validators"))
from audit_v2 import (contract_grade, flow_verdict, lot_coverage, materialization_assessment,
                      negative_coverage, plan_summary, sample_metrics, vague_candidates)
from render_audit_v2 import render
from scan_pass_emitters import scan
from validate_audit_v2 import validate, local_ref


class V2Reporting(unittest.TestCase):
    def setUp(self):
        self.report = json.loads((PACK / "reports/perfil_ig_perfil_v2.json").read_text())
        self.profiles = json.loads((PACK / "references/contract_profiles_v2.json").read_text())

    def errors(self): return validate(self.report, ROOT)
    def has(self, token): self.assertTrue(any(token in e for e in self.errors()), self.errors())
    def reaccount(self):
        result = flow_verdict(self.report)
        self.report["completion"].update(flow_verdict=result["verdict"], flow_reasons=result["reasons"])

    def test_real_packet_valid_but_flow_not_accredited(self):
        self.assertEqual(self.errors(), [])
        self.assertEqual(self.report["completion"]["flow_verdict"], "FLOW_NOT_ACCREDITED")
        self.assertEqual(len(self.report["steps"]), 11)
        self.assertEqual(sum(q["measurement_status"] == "MEASURED" for q in self.report["sql_queries"]), 8)

    def test_missing_step_cannot_disappear(self):
        self.report["steps"].pop(2); self.has("ELEVEN_STEP_LEDGER_REQUIRED")

    def test_100_percent_lot_never_implies_new_e2e(self):
        for task in self.report["audit_tasks"]:
            task.update(status="VERIFIED", evidence_refs=["E-BINDINGS"])
        self.report["completion"]["lot_coverage_percent"] = 100.0
        self.assertEqual(lot_coverage(self.report["audit_tasks"])["percent"], 100)
        self.assertEqual(flow_verdict(self.report)["verdict"], "FLOW_NOT_ACCREDITED")

    def test_overclaimed_flow_is_rejected(self):
        self.report["completion"]["flow_verdict"] = "FLOW_ACCREDITED"; self.has("FLOW_VERDICT_OVERCLAIM")

    def test_accounting_can_accredit_a_complete_synthetic_new_run(self):
        # Accounting only: this mutation is not evidence of a real new execution.
        self.report["audit_context"].update(new_e2e_executed=True,ig_execution_required=False)
        for step in self.report["steps"]:
            step.update(runtime_origin="NEW_AUDIT_RUN",behavior_status="EXECUTED_AND_VERIFIED",resolved_receipts=["synthetic-only"])
        for hop in self.report["hops"]:
            if not hop["id"].startswith("H-IG-"):
                hop.update(run_binding="RECORDED_PARENT_MATCH",hash_binding="RECORDED_MATCH")
        self.assertEqual(flow_verdict(self.report)["verdict"],"FLOW_ACCREDITED")

    def test_historical_run_is_not_new_e2e(self):
        self.report["audit_context"]["new_e2e_executed"] = True
        self.reaccount(); self.has("HISTORICAL_RUN_IS_NOT_NEW_E2E")

    def test_new_run_cannot_relabel_old_or_static_receipt(self):
        s = self.report["steps"][0]
        s.update(runtime_origin="NEW_AUDIT_RUN", behavior_status="EXECUTED_AND_VERIFIED", resolved_receipts=["E-SOURCE"])
        self.reaccount(); self.has("NEW_RUN_RECEIPT_PROVENANCE_INVALID")

    def test_static_evidence_cannot_be_current_measurement(self):
        self.report["evidence_catalog"][0]["kind"] = "MEASURED_THIS_AUDIT"
        self.has("STATIC_OR_PRIOR_MISLABELED_CURRENT")

    def test_capture_hash_and_pointer_resolve(self):
        self.report["evidence_catalog"][0]["capture_sha256"] = "0" * 64; self.has("CAPTURE_HASH_DRIFT")
        with self.assertRaises(ValueError): local_ref(ROOT, "../escape")
        with self.assertRaises(KeyError): local_ref(ROOT, self.report["evidence_catalog"][3]["capture_ref"].split("#")[0] + "#/absent")

    def test_missing_hop_is_rejected(self):
        self.report["hops"].pop(2); self.has("HOP_MATRIX_INCOMPLETE")

    def test_candidate_hash_not_invented_before_step50(self):
        early = self.report["hops"][0]
        self.assertEqual(early["hash_binding"], "NOT_APPLICABLE")
        self.assertIn("aún no existe", early["hash_semantics"])
        self.assertEqual(self.errors(), [])

    def test_pointer_presence_not_false_pass_rate(self):
        metrics = self.report["run_sample"]["metrics"]
        self.assertEqual(metrics["pass_missing_evidence_ref"], 0)
        self.assertEqual(metrics["persisted_pass_steps"], 175)
        self.assertIsNone(metrics["confirmed_false_pass_rate"])

    def test_empty_sample_denominators_are_null(self):
        m = sample_metrics([])
        self.assertIsNone(m["pass_missing_evidence_ref_percent"])
        self.assertIsNone(m["ig_reported_without_invocation_percent"])
        self.assertIsNone(m["confirmed_false_pass_rate"])

    def test_optional_ig_without_invocation_not_automatically_false_pass(self):
        m = sample_metrics([{"pass_steps":1,"pass_missing_evidence_ref":0,"pass_empty_payload":0,"ig_reported":True,"ig_invocations":0}])
        self.assertEqual(m["ig_reported_without_invocation_percent"], 100)
        self.assertIsNone(m["confirmed_false_pass_rate"])

    def test_measured_sql_without_readonly_rollback_is_rejected(self):
        self.report["sql_queries"][0]["rollback_included"] = False; self.has("QUERY_MEASUREMENT_UNSUPPORTED")

    def test_unmeasured_writer_cannot_have_fake_latency(self):
        self.report["sql_queries"][-1]["execution_ms"] = 0.1; self.has("UNMEASURED_QUERY_HAS_METRICS")

    def test_query_numbers_must_match_captured_plan(self):
        self.report["sql_queries"][0]["execution_ms"] += 1
        self.has("QUERY_METRICS_OR_SQL_CAPTURE_DRIFT")

    def test_cohort_statistics_cannot_be_rewritten_as_zero_false_passes(self):
        self.report["run_sample"]["metrics"]["confirmed_false_pass_rate"] = 0
        self.has("COHORT_METRICS_DRIFT")

    def test_materialization_not_recommended_without_frequency_and_safety(self):
        q = self.report["sql_queries"][0]; q["materialization_decision"] = "OPTIONAL_CANDIDATE"
        self.has("MATERIALIZATION_WITHOUT_MEASURED_BENEFIT_AND_SAFETY")
        self.assertEqual(materialization_assessment({"cost_measured":True})["decision"], "NOT_EVALUATED")

    def test_materialization_rejected_for_immediate_freshness(self):
        self.assertEqual(materialization_assessment({"immediate_freshness":True})["decision"], "REJECT_MATERIALIZATION")

    def test_optional_materialization_requires_measured_positive_benefit(self):
        m = {k:True for k in ("frequency_measured","cost_measured","equivalence_verified","refresh_verified","security_equivalent","invalidation_verified")}
        m.update(freshness_budget_ms=500,worst_refresh_lag_ms=100,calls_per_interval=10,mean_query_ms=20,refresh_cost_ms=30)
        self.assertEqual(materialization_assessment(m), {"decision":"OPTIONAL_CANDIDATE","reason":"MEASURED_FREQUENCY_TIMES_COST_MINUS_REFRESH","benefit_ms":170})
        m["worst_refresh_lag_ms"] = 501
        self.assertEqual(materialization_assessment(m)["decision"], "REJECT_MATERIALIZATION")
        m.update(worst_refresh_lag_ms=100, refresh_cost_ms=201)
        self.assertEqual(materialization_assessment(m)["decision"], "KEEP_CURRENT")

    def test_materialize_plan_node_not_materialized_view(self):
        capture = json.loads((PACK / "reports/v2_inputs/source_capture.json").read_text())
        q = next(q for q in capture["query_measurements"] if q["id"] == "Q_RECENT_COHORT")
        s = plan_summary(q["plan"])
        self.assertTrue(any(n["Node Type"] == "Materialize" for n in s["nodes"]))
        self.assertFalse(s["materialize_plan_node_is_materialized_view"])

    def test_critical_missing_and_weak_never_averaged_away(self):
        c = copy.deepcopy(next(c for c in self.report["contracts"] if c["id"] == "C10"))
        c["fields"]["output"].update(status="MISSING",literal=None,proposed_rewrite="Return the exact typed output and error.")
        self.assertEqual(contract_grade(c, self.profiles["profiles"])["grade"], "LOW")
        c["fields"]["output"]["status"] = "WEAK"
        c["fields"]["input"]["status"] = "NOT_EVALUATED"
        self.assertEqual(contract_grade(c, self.profiles["profiles"])["grade"], "LOW")

    def test_wordy_vague_contract_does_not_outscore_concise_specific(self):
        c = copy.deepcopy(next(c for c in self.report["contracts"] if c["id"] == "C10"))
        c["fields"]["output"].update(literal="Gestionar adecuadamente el resultado. " * 100,
            status="WEAK",reason="No fija objeto, condición, error ni receptor.",proposed_rewrite="return {code: 'SCOPE_REQUIRED'} if scope is null")
        self.assertEqual(contract_grade(c, self.profiles["profiles"])["grade"], "LOW")
        c["fields"]["output"].update(literal="scope=null → SCOPE_REQUIRED",status="ACCEPTABLE",
            reason="Especifica condición y resultado verificable.",semantic_checks=["Condición→error explícitos y compatibles con el consumidor."])
        self.assertEqual(contract_grade(c, self.profiles["profiles"])["grade"], "ACCEPTABLE")

    def test_unknown_contract_field_stays_gray(self):
        c = copy.deepcopy(next(c for c in self.report["contracts"] if c["id"] == "C10"))
        c["fields"]["input"].update(status="NOT_EVALUATED", literal=None,reason="Consumidor sin leer.")
        self.assertEqual(contract_grade(c, self.profiles["profiles"])["grade"], "NOT_EVALUATED")

    def test_type_specific_formats_and_semantic_acceptance_required(self):
        c = copy.deepcopy(self.report["contracts"][0]); c["format"] = "SQL"
        self.assertIn("CONTRACT_FORMAT_INCOMPATIBLE_WITH_TYPE", contract_grade(c, self.profiles["profiles"])["errors"])
        c = copy.deepcopy(self.report["contracts"][0]); c["fields"]["input"]["semantic_checks"] = []
        self.assertTrue(any("SEMANTIC_ACCEPTANCE_UNSUPPORTED" in e for e in contract_grade(c, self.profiles["profiles"])["errors"]))

    def test_weak_field_requires_actionable_rewrite(self):
        self.report["contracts"][0]["fields"]["types"]["proposed_rewrite"] = None
        self.has("ACTIONABLE_REWRITE_MISSING")

    def test_contract_literal_and_grade_cannot_be_invented(self):
        self.report["contracts"][0]["fields"]["input"]["literal"] = "invented contract"
        self.has("CONTRACT_LITERAL_UNRESOLVED")
        self.report["contracts"][0]["grade"] = "ACCEPTABLE"; self.has("CONTRACT_GRADE_OVERCLAIM")

    def test_vague_phrase_is_a_hint_even_in_negation(self):
        self.assertEqual(vague_candidates('Nunca responder solamente "revisar el backend".')[0]["status"], "HYPOTHESIS_REQUIRES_CONTEXT")

    def test_pass_scanner_finds_exception_success_without_executing_source(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/"case.py"
            p.write_text('raise RuntimeError("DO_NOT_EXECUTE")\ndef run():\n    try: work()\n    except ValueError:\n        return {"eval_status":"PASS"}\n')
            result = scan(p)
            self.assertTrue(any(s["marker"] == "PASS" for s in result["sites"]))
            self.assertTrue(all(s["classification"] == "EMITTER_CANDIDATE" for s in result["sites"]))
            self.assertTrue(any("EXCEPT_EMITS_SUCCESS" in s["risk_candidates"] for s in result["sites"]))

    def test_sql_comparison_and_default_true_need_context(self):
        defaults = [s for s in self.report["pass_emitters"] if s["marker"] == "DEFAULT_TRUE"]
        self.assertEqual(len(defaults), 2)
        self.assertTrue(all(s["classification"] == "RISK_PATTERN_ONLY" for s in defaults))
        self.assertTrue(any(s["classification"] == "NOT_EMITTER" and s["marker"] == "STEP_PASS_WITH_EVIDENCE" for s in self.report["pass_emitters"]))

    def test_accepted_broken_input_is_not_verified_negative(self):
        summary = negative_coverage(self.report["pass_emitters"])
        self.assertEqual(summary["negatives_verified"], 1)
        self.assertGreater(len(summary["unverified_ids"]), 0)
        self.assertTrue(any(s["negative_test"]["status"] == "EXECUTED_ACCEPTED_BROKEN_INPUT" for s in self.report["pass_emitters"]))

    def test_fake_negative_execution_and_source_drift_rejected(self):
        s = next(s for s in self.report["pass_emitters"] if s["classification"] == "EMITTER")
        s["negative_test"].update(status="EXECUTED_REJECTED_BROKEN_INPUT",command=None,evidence_refs=[])
        self.has("PASS_NEGATIVE_EXECUTION_NOT_PROVEN")
        s["source_sha256"] = "0"*64; self.has("PASS_SOURCE_READBACK_DRIFT")

    def test_finding_integrity_and_no_fake_fix(self):
        self.report["findings"][0]["status"] = "FIX_VERIFIED"; self.has("FIX_BEFORE_AFTER_REQUIRED")
        self.report["findings"][0]["found_code"] = "invented code"; self.has("LITERAL_SOURCE_MISMATCH")
        self.report["findings"][0]["negative_test"]["executed"] = False; self.has("CONFIRMATION_EVIDENCE_INSUFFICIENT")

    def test_six_phases_and_ekb_evidence_are_preserved(self):
        self.assertEqual(self.report["phases"], [1,2,3,4,5,6])
        self.assertEqual(len(self.report["checklist"]), 16)
        self.report["phases"].pop(); self.has("SCHEMA:phases")

    def test_ekb_applicability_and_evidence_cannot_be_faked(self):
        self.report["checklist"][0].update(applies=True,result="NOT_APPLICABLE")
        self.has("CHECKLIST_APPLICABILITY_CONTRADICTION")

    def test_fresh_context_fixture_reproduces_undocumented_losses(self):
        # Re-run the separately authored reviewed harness; keep committed captures intact.
        path = PACK / "reports/forward_v2/reproduce.py"
        spec = importlib.util.spec_from_file_location("audit_v2_forward_reproduction", path)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            module.OUT = Path(directory)
            self.assertEqual(module.main(), 0)
            result = json.loads((Path(directory)/"reproduction.json").read_text())
        cases = {c["id"]: c["observed"] for c in result["cases"]}
        self.assertEqual(result["summary"]["assertions_passed"], 32)
        self.assertEqual(cases["RAW_RUN_VALID"]["exception"], "TypeError")
        self.assertEqual(cases["RAW_AFTER_BINDING_ONLY"]["message"], "'currency'")
        self.assertEqual(cases["RAW_AFTER_CURRENCY_ONLY"]["message"], "'source_revision'")
        self.assertEqual(cases["CORRECT_RUN_PEN"]["value"]["decision"], "READY")
        self.assertEqual(cases["CORRECT_UNSUPPORTED"]["message"], "CURRENCY_UNSUPPORTED")
        self.assertEqual(cases["CORRECT_NULL_REVISION_BOUNDARY"]["kind"], "RETURN")

    def test_promotion_true_requires_real_current_policy_evidence(self):
        self.report["audit_context"]["promotion_authorized"] = True
        self.has("PROMOTION_AUTHORITY_CURRENT_READBACK_REQUIRED")

    def test_typed_intake_rejects_null_commit_empty_consumer_and_unscoped_write(self):
        schema = json.loads((PACK / "schemas/audit_input_v2.schema.json").read_text())
        data = json.loads((PACK / "examples/audit_input_v2.json").read_text())
        v = Draft202012Validator(schema); self.assertEqual(list(v.iter_errors(data)), [])
        for field, value in (("base_commit",None),("consumer_targets",[]),("write_scope",["PRODUCTION"])):
            broken = copy.deepcopy(data); broken[field] = value
            self.assertTrue(list(v.iter_errors(broken)), field)

    def test_judge_contextual_pass_does_not_require_invented_independence(self):
        schema = json.loads((PACK / "schemas/judge_result_v2.schema.json").read_text())
        value = {"schema_version":"LF_CONTEXT_SPEC_JUDGE_RESULT_V2","evaluation_scope":"CURRENT_CONTEXT_SPEC_EVAL",
            "evaluation_valid":True,"evaluation_errors":[],"independence_status":"NOT_PROVEN","independence_evidence_refs":[],
            "promotion_authorized":True,"authorized_effect":"REQUEST_PROMOTION","authority":{
                "policy_ref":"fixture://contextual-allowed","policy_revision":"a"*40,"policy_sha256":"b"*64,
                "actor":"fixture-actor","target":"fixture-target","current_readback_ref":"fixture://policy"},
            "next_action":"REQUEST_PROMOTION","source_refs":["fixture://spec"]}
        v = Draft202012Validator(schema)
        self.assertEqual(list(v.iter_errors(value)), [])
        value["authority"] = None; self.assertTrue(list(v.iter_errors(value)))
        value.update(evaluation_valid=False,evaluation_errors=["CONTENT_INVALID"])
        self.assertTrue(list(v.iter_errors(value)))
        value.update(authority=None,promotion_authorized=False,authorized_effect="NONE",independence_status="PROVEN")
        self.assertTrue(list(v.iter_errors(value)))

    def test_renderer_colors_labels_escape_and_separate_verdict(self):
        self.report["contracts"][0]["fields"]["input"]["literal"] = '<img src=x onerror=alert(1)>'
        md, html = render(self.report, self.profiles)
        self.assertIn("FLUJO NO ACREDITADO", md)
        for color in ("#dcfce7","#fef9c3","#fee2e2","#e5e7eb"): self.assertIn(color, html)
        self.assertIn("&lt;img src=x onerror=alert(1)&gt;", html)
        self.assertNotIn("<img src=x", html)
        self.assertIn('id="grade"', html)


if __name__ == "__main__": unittest.main()
