#!/usr/bin/env python3
"""Adversarial tests for the existing Analysis A14 replay boundary.

This is NOT a model-behaviour test or an approval to integrate A9 -> PG-01.
"""
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def load_module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/(name+".py"))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def main():
    run=load_module("run_analysis_a14_candidate_v1")
    classifier=run.load_depth_classifier()
    cases=json.loads((ROOT/"analysis_a14_fresh_cases_v1.json").read_text())
    seed=cases["cases"][0]
    baseline=run.execute_case(seed,classifier)
    assert baseline["verdict"]=="READY"
    assert baseline["false_ready_count"] is None  # Oracle required, never self-scored.
    assert baseline["source_read_count"]==0 and baseline["duplicate_read_count"]==0
    assert baseline["source_reads_executed_by_replay"] is False
    assert baseline["referenced_source_count"]>0

    corrupt=copy.deepcopy(seed)
    corrupt["handoff"]["receipt_context_sha256"]="mismatched-currentness"
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED" and not result["ready_scope_ids"]
    assert result["handoff_parity_verdict"]=="BLOCK"
    assert result["reinterpretation_required"] is True

    corrupt=copy.deepcopy(seed)
    corrupt["handoff"]["context_sha256"]=None
    corrupt["handoff"]["receipt_context_sha256"]=None
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED"
    assert result["handoff_parity_verdict"]=="BLOCK"

    corrupt=copy.deepcopy(seed)
    corrupt["handoff"]["context_sha256"]="same-but-not-sha256"
    corrupt["handoff"]["receipt_context_sha256"]="same-but-not-sha256"
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED"

    corrupt=copy.deepcopy(seed)
    corrupt["evidence"]["material_fronts"][0].update(
        status="BLOCKED",effect_on_scope="PRESERVE")
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED"
    assert result["scope_front_consistency_verdict"]=="BLOCK"

    corrupt=copy.deepcopy(seed)
    corrupt["evidence"]["material_fronts"].append(
        copy.deepcopy(corrupt["evidence"]["material_fronts"][0]))
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED"
    assert result["scope_front_consistency_verdict"]=="BLOCK"

    corrupt=copy.deepcopy(seed)
    corrupt["evidence"]["material_fronts"][0]["scope_ids"]=["UNKNOWN_SCOPE"]
    result=run.execute_case(corrupt,classifier)
    assert result["verdict"]=="BLOCKED"
    assert result["scope_front_consistency_verdict"]=="BLOCK"

    with tempfile.TemporaryDirectory() as tmp:
        temp=Path(tmp)
        candidate={
            "schema_version":"ANALYSIS_A14_CANDIDATE_RESULT_SET_V1",
            "case_set_id":cases["case_set_id"],
            "evidence_tier":"DETERMINISTIC_CONTRACT_REPLAY",
            "model_inference_executed":False,
            "real_programming_consumer_verified":False,
            "results":[run.execute_case(c,classifier) for c in cases["cases"]]
        }
        def score(package):
            c=temp/"candidate.json"
            c.write_text(json.dumps(package))
            return subprocess.run([
                sys.executable,str(ROOT/"score_analysis_a14_holdout_v1.py"),
                "--cases",str(ROOT/"analysis_a14_fresh_cases_v1.json"),
                "--oracle",str(ROOT/"analysis_a14_fresh_oracle_v1.json"),
                "--candidate",str(c),"--output",str(temp/"score.json")
            ],capture_output=True,text=True)

        passed=score(candidate)
        assert passed.returncode==0,passed.stderr
        report=json.loads((temp/"score.json").read_text())
        assert report["verdict"]=="PASS"
        assert report["operational_integration_admissible"] is False
        assert report["model_inference_verified"] is False
        assert report["real_programming_consumer_verified"] is False

        fake=copy.deepcopy(candidate)
        fake["model_inference_executed"]=True
        failure=score(fake)
        assert failure.returncode!=0
        assert "A14_UNSUPPORTED_RUNTIME_CLAIM" in failure.stderr

        fake=copy.deepcopy(candidate)
        fake["results"][0]["provider_response_id"]="synthetic-provider-id"
        failure=score(fake)
        assert failure.returncode!=0
        assert "A14_REPLAY_MAY_NOT_CLAIM_PROVIDER_EVIDENCE" in failure.stderr

        fake=copy.deepcopy(candidate)
        fake["results"][0]["ready_scope_ids"]=["S1"]
        fake["results"][0]["handoff_parity_verdict"]="BLOCK"
        failure=score(fake)
        assert failure.returncode!=0
        wrong_report=json.loads((temp/"score.json").read_text())
        assert wrong_report["gates"]["critical_false_ready"]>0

    print("PASS_ANALYSIS_EVIDENCE_BOUNDARY replay_positive=1 malformed_handoff=1 "
          "missing_digest=1 malformed_digest=1 front_contradiction=1 duplicate_front=1 wrong_scope=1 "
          "fabricated_runtime_claim=1 provider_claim=1 false_ready=1")

if __name__=="__main__":
    main()
