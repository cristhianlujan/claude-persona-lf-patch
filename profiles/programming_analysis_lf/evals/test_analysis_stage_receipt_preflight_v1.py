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
    "required_stage_sources": {f"A{i}": f"git://stage/{i}" for i in range(1, 10)},
    "source_readback": {"stage_git_blobs": {f"A{i}": "a" * 40 for i in range(1, 10)}},
}


def packet():
    return {
        "execution": {"execution_id": E, "operation_code": "EJECUCION_PERFIL_LF", "profile_code": "PERFIL-PROGRAMMING-ANALYSIS-LF", "request_sha256": H, "status": "COMPLETED"},
        "router_handoff": {"router": "ACT-0001", "request_sha256": H, "authorization_fingerprint_sha256": H, "authorization_receipt_ref": "router-authorization://" + H},
        "operation_step_readback": [{"execution_id": E, "step_id": x, "status": "STEP_PASS_WITH_EVIDENCE", "evidence_ref": ("router-authorization://" + H if x == "router" else "supabase://step/" + x) for x in gate.OP_STEPS],
        "stage_readback": [{"stage": f"A{i}", "execution_id": E, "request_sha256": H, "source_ref": f"git://stage/{i}", "source_git_blob": "a" * 40, "evidence_origin": "OPERATIONAL_RECORDER", "stage_receipt_ref": f"supabase://stage/{i}", "raw_output_sha256": H} for i in range(1, 10)],
        "model_readback": {"execution_id": E, "raw_ref": "supabase://raw", "raw_sha256": H},
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
