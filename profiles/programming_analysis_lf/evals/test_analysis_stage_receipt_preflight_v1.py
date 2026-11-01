#!/usr/bin/env python3
"""Synthetic tests: a full shape is only a provisional trace, NOT runtime proof."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "stage_gate", Path(__file__).with_name("analysis_stage_receipt_preflight_v1.py")
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
H = "e" * 64
E = "EXEC-TEST-ANALYSIS-NONPROD"
B = {
    "business": "LF",
    "business_source_namespace": "lf_ops",
    "business_scope_binding_status": "CANDIDATE_NOT_RELEASED",
    "required_stage_sources": {f"A{i}": f"git://stage/{i}" for i in range(1, 10)},
    "source_readback": {"stage_git_blobs": {f"A{i}": "a" * 40 for i in range(1, 10)}},
}


def packet():
    return {
        "execution": {"execution_id": E, "operation_code": "EJECUCION_PERFIL_LF", "profile_code": "PERFIL-PROGRAMMING-ANALYSIS-LF", "request_sha256": H, "status": "COMPLETED", "business": "LF"},
        "router_handoff": {"router": "ACT-0001", "business": "LF", "request_sha256": H, "authorization_fingerprint_sha256": H, "authorization_receipt_ref": "router-authorization://" + H},
        "operation_step_readback": [{"execution_id": E, "step_id": x, "status": "STEP_PASS_WITH_EVIDENCE", "evidence_ref": ("router-authorization://" + H if x == "router" else "supabase://step/" + x) for x in gate.OP_STEPS],
        "stage_readback": [{"stage": f"A{i}", "business": "LF", "execution_id": E, "request_sha256": H, "source_ref": f"git://stage/{i}", "source_git_blob": "a" * 40, "evidence_origin": "OPERATIONAL_RECORDER", "stage_receipt_ref": f"supabase://stage/{i}", "raw_output_sha256": H} for i in range(1, 10)],
        "model_readback": {"business": "LF", "execution_id": E, "raw_ref": "supabase://raw", "raw_sha256": H},
        "independent_semantic_judge_ref": "supabase://judge",
        "currentness_authority_receipt_ref": "supabase://currentness",
        "downstream_readback_ref": "supabase://PG01",
    }


class AnalysisStageRunPreflightTests(unittest.TestCase):
    def rejects(self, p, code):
        r = gate.validate_readback(p, B)
        self.assertEqual(r["status"], "FAIL", r)
        self.assertIn(code, r["errors"])
        self.assertFalse(r["operational_ready"])

    def test_01_full_shape_is_only_candidate(self):
        r = gate.validate_readback(packet(), B)
        self.assertEqual(r["status"], "STRUCTURAL_CANDIDATE_ONLY")
        self.assertFalse(r["operational_ready"])
        self.assertFalse(r["runtime_provenance_verified"])

    def test_02_missing_router(self):
        p=packet(); del p["router_handoff"]; self.rejects(p,"ROUTER_HANDOFF_RECEIPT_MISSING")

    def test_03_router_input_drift(self):
        p=packet(); p["router_handoff"]["request_sha256"]="f"*64; self.rejects(p,"ROUTER_RECEIPT_BINDING_MISMATCH")

    def test_04_missing_stage(self):
        p=packet(); p["stage_readback"].pop(); self.rejects(p,"A1_A9_STAGE_READBACK_MISSING_OR_OUT_OF_ORDER")

    def test_05_self_report_is_not_receipt(self):
        p=packet(); p["stage_readback"][3]["evidence_origin"]="MODEL_SELF_REPORT"; self.rejects(p,"A4_NO_PERSISTED_STAGE_RECEIPT")

    def test_06_stale_pin(self):
        p=packet(); p["stage_readback"][0]["source_git_blob"]="b"*40; self.rejects(p,"A1_SOURCE_PIN_MISMATCH")

    def test_07_stage_different_run(self):
        p=packet(); p["stage_readback"][5]["execution_id"]="OTHER"; self.rejects(p,"A6_RUN_BINDING_MISMATCH")

    def test_08_no_raw(self):
        p=packet(); del p["model_readback"]; self.rejects(p,"MODEL_RAW_READBACK_MISSING")

    def test_09_no_judge(self):
        p=packet(); del p["independent_semantic_judge_ref"]; self.rejects(p,"INDEPENDENT_JUDGE_RECEIPT_MISSING")

    def test_10_no_downstream_readback(self):
        p=packet(); del p["downstream_readback_ref"]; self.rejects(p,"DOWNSTREAM_READBACK_MISSING")

    def test_11_missing_canonical_step(self):
        p=packet(); p["operation_step_readback"].pop(4); self.rejects(p,"OPERATION_11_STEP_READBACK_MISSING")

    def test_12_wrong_operation(self):
        p=packet(); p["execution"]["operation_code"]="OTHER"; self.rejects(p,"OPERATION_MISMATCH")

    def test_13_no_currentness(self):
        p=packet(); del p["currentness_authority_receipt_ref"]; self.rejects(p,"CURRENTNESS_AUTHORITY_RECEIPT_MISSING")

    def test_14_run_not_closed(self):
        p=packet(); p["execution"]["status"]="IN_PROGRESS"; self.rejects(p,"OPERATION_NOT_TERMINAL")

    def test_15_router_step_not_bound_to_receipt(self):
        p=packet(); p["operation_step_readback"][1]["evidence_ref"]="unbound"; self.rejects(p,"ROUTER_STEP_RECEIPT_NOT_BOUND")


    def test_16_run_business_missing(self):
        p=packet(); del p["execution"]["business"]
        self.rejects(p,"BUSINESS_CONTEXT_MISSING_OR_INVALID")

    def test_17_router_business_mismatch(self):
        p=packet(); p["router_handoff"]["business"]="SALY"
        self.rejects(p,"ROUTER_BUSINESS_CONTEXT_MISMATCH")

    def test_18_saly_cannot_use_lf_sources(self):
        p=packet(); p["execution"]["business"]="SALY"; p["router_handoff"]["business"]="SALY"
        self.rejects(p,"BUSINESS_AUTHORITY_SCOPE_MISMATCH")

    def test_19_lf_stage_cannot_be_attached_to_saly_context(self):
        p=packet(); p["stage_readback"][3]["business"]="SALY"
        self.rejects(p,"A4_BUSINESS_CONTEXT_MISMATCH")

    def test_20_model_readback_must_match_business(self):
        p=packet(); p["model_readback"]["business"]="SALY"
        self.rejects(p,"MODEL_RAW_READBACK_MISSING")

    def test_21_wrong_lf_namespace(self):
        p=packet(); b=dict(B); b["business_source_namespace"]="saly"
        r=gate.validate_readback(p,b)
        self.assertEqual(r["status"],"FAIL"); self.assertIn("LF_SOURCE_NAMESPACE_MISMATCH",r["errors"])

    def test_22_copied_lf_candidate_cannot_authorize_saly(self):
        p=packet(); p["execution"]["business"]="SALY"; p["router_handoff"]["business"]="SALY"
        for stage in p["stage_readback"]: stage["business"]="SALY"
        p["model_readback"]["business"]="SALY"
        b=dict(B); b["business"]="SALY"; b["business_source_namespace"]="saly"
        r=gate.validate_readback(p,b)
        self.assertEqual(r["status"],"FAIL")
        self.assertIn("NON_LF_BUSINESS_SOURCE_NOT_QUALIFIED",r["errors"])

    def test_23_business_binding_missing(self):
        p=packet(); b=dict(B); del b["business"]
        r=gate.validate_readback(p,b)
        self.assertEqual(r["status"],"FAIL")
        self.assertIn("BUSINESS_SOURCE_BINDING_MISSING",r["errors"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
