#!/usr/bin/env python3
"""Source-only tests for progressive A1-A9 checkpoint preparation."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "checkpoint", Path(__file__).with_name("analysis_stage_checkpoint_prepare_v1.py")
)
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)

SHA = "e" * 64
BINDING = {
    "business": "LF", "business_source_namespace": "lf_ops",
    "required_stage_sources": {f"A{i}": f"git://A{i}" for i in range(1, 10)},
    "source_readback": {"stage_git_blobs": {f"A{i}": "a"*40 for i in range(1, 10)}},
}


def run():
    return {"execution_id": "EXEC-ANALYSIS-FIXTURE-001",
            "request_sha256": SHA, "business": "LF",
            "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": "PERFIL-PROGRAMMING-ANALYSIS-LF",
            "status": "IN_PROGRESS",
            "checkpoint_seq": 0,
            "checkpoint_payload": {"pre_existing_payload": {"keep": True}}}


def evidence(stage="A1", r=None):
    r = r or run()
    return {"execution_id": r["execution_id"],
            "request_sha256": r["request_sha256"], "business": r["business"],
            "source_ref": BINDING["required_stage_sources"][stage],
            "source_git_blob": BINDING["source_readback"]["stage_git_blobs"][stage],
            "evidence_ref": f"supabase://authorized-stage-observation/{stage}",
            "raw_output_sha256": SHA}


class AnalysisCheckpointTests(unittest.TestCase):
    def bad(self, r, stage, ev, expected, source=None):
        with self.assertRaisesRegex(C.StageCheckpointError, expected):
            C.prepare(r, source or BINDING, stage, ev)

    def test_01_first_step_keeps_prior_data_and_not_persisted(self):
        r = run()
        before = copy.deepcopy(r)
        result = C.prepare(r, BINDING, "A1", evidence())
        self.assertEqual(r, before)
        self.assertEqual(result["checkpoint_seq"], 1)
        self.assertEqual(result["checkpoint_payload"]["pre_existing_payload"], {"keep": True})
        self.assertEqual(result["checkpoint_payload"][C.KEY]["last_stage"], "A1")
        self.assertFalse(result["persisted"])
        self.assertFalse(result["operational_ready"])

    def test_02_cumulative_nine_steps_same_run(self):
        r = run()
        for i in range(1, 10):
            stage=f"A{i}"
            out=C.prepare(r,BINDING,stage,evidence(stage,r))
            r["checkpoint_seq"]=out["checkpoint_seq"]
            r["checkpoint_payload"]=out["checkpoint_payload"]
        p=r["checkpoint_payload"][C.KEY]
        self.assertEqual([x["stage"] for x in p["stage_receipts"]],list(C.STAGES))
        self.assertEqual(r["checkpoint_seq"],9)
        self.assertFalse(p["operational_ready"])
        self.assertEqual(p["independent_verification"],"NOT_EXECUTED")

    def test_03_first_must_be_A1(self):
        self.bad(run(),"A2",evidence("A2"),"FIRST_STAGE_MUST_BE_A1")

    def test_04_no_duplicate(self):
        r=run();out=C.prepare(r,BINDING,"A1",evidence())
        r["checkpoint_seq"]=out["checkpoint_seq"];r["checkpoint_payload"]=out["checkpoint_payload"]
        self.bad(r,"A1",evidence("A1",r),"STAGE_ORDER_OR_REPLAY_INVALID")

    def test_05_no_stage_skip(self):
        r=run();out=C.prepare(r,BINDING,"A1",evidence())
        r["checkpoint_seq"]=out["checkpoint_seq"];r["checkpoint_payload"]=out["checkpoint_payload"]
        self.bad(r,"A3",evidence("A3",r),"STAGE_ORDER_OR_REPLAY_INVALID")

    def test_06_business_cannot_switch(self):
        r=run();r["business"]="SALY"
        self.bad(r,"A1",evidence(),"BUSINESS_BINDING_INVALID")

    def test_07_evidence_business_drift(self):
        r=run();ev=evidence();ev["business"]="SALY"
        self.bad(r,"A1",ev,"EVIDENCE_IDENTITY_MISMATCH")

    def test_08_stale_source_pin(self):
        ev=evidence();ev["source_git_blob"]="b"*40
        self.bad(run(),"A1",ev,"SOURCE_EVIDENCE_MISMATCH")

    def test_09_missing_raw(self):
        ev=evidence();ev["raw_output_sha256"]=""
        self.bad(run(),"A1",ev,"STAGE_RAW_SHA_INVALID")

    def test_10_finished_run_not_writable(self):
        r=run();r["status"]="COMPLETED"
        self.bad(r,"A1",evidence(),"RUN_NOT_IN_PROGRESS")

    def test_11_checkpoint_sequence_rejects_bad_value(self):
        r=run();r["checkpoint_seq"]=-1
        self.bad(r,"A1",evidence(),"CHECKPOINT_SEQ_INVALID")

    def test_12_prior_progress_identity_must_match(self):
        r=run();out=C.prepare(r,BINDING,"A1",evidence())
        r["checkpoint_seq"]=out["checkpoint_seq"];r["checkpoint_payload"]=out["checkpoint_payload"]
        r["checkpoint_payload"][C.KEY]["request_sha256"]="f"*64
        self.bad(r,"A2",evidence("A2",r),"PROGRESS_IDENTITY_DRIFT")

    def test_13_missing_canonical_source(self):
        b=copy.deepcopy(BINDING);del b["required_stage_sources"]["A1"]
        self.bad(run(),"A1",evidence(),"SOURCE_REF_MISSING",b)

    def test_14_wrong_profile(self):
        r=run();r["profile_code"]="PERFIL-OTHER"
        self.bad(r,"A1",evidence(),"PROFILE_MISMATCH")


if __name__=="__main__":
    unittest.main(verbosity=2)
