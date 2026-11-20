#!/usr/bin/env python3
"""Fresh pure helper probes. Never submit synthetic receipts to LF runtime."""
import copy
import datetime as dt
import json
from pathlib import Path
from unittest.mock import patch
from run_step70_pilot import ROOT, load, observe


def execute():
    with patch("urllib.request.urlopen", side_effect=AssertionError("NETWORK_FORBIDDEN")):
        baseline = observe()
        receipt = load(ROOT / "scripts/lf_step70_separate_call_receipt_v1.py", "audit_v2_receipt")
        evaluator = load(ROOT / "scripts/lf_step70_same_llm_eval_v1.py", "audit_v2_eval")
        native = load(ROOT / "scripts/lf_profile_native_resume.py", "audit_v2_native")
        fixtures = load(ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/test_step70_same_llm_separate_call_v1.py", "audit_v2_receipt_fixture")
        clean = load(ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/test_step70_clean_eval_runner_v1.py", "audit_v2_clean_fixture")
        review = clean.case()
        review.update(review_mode="INDEPENDENT_SEMANTIC", verdict="PASS_INDEPENDENT_SEMANTIC",
                      separate_model_call_receipt=copy.deepcopy(fixtures.fixture()["separate_model_call_receipt"]))
        review["separate_model_call_receipt"]["decision_body"]["unsupported_claims"] = ["LOCAL_NEGATIVE_ONLY"]
        normalized, result = receipt.normalize_when_unverified(review)
        native.validate_independent_semantic_review(normalized)
        downstream = native.build_semantic_receipt(normalized)
        raw = fixtures.fixture(); r = raw["separate_model_call_receipt"]
        raw = {"schema_id": r["schema_id"], "execution_id": r["execution_id"],
               "candidate_sha256": r["candidate_sha256"], "scope_packet_sha256": r["scope_packet_sha256"],
               "verdict": r["decision_body"]["verdict"], "decision_body": r["decision_body"],
               "source_refs": ["fixture://valid-reference"]}
        rejected = evaluator.evaluate(raw, r["execution_id"], "0" * 64, r["scope_packet_sha256"])
        return {"executed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "scope": "LOCAL_HELPERS_WITH_SYNTHETIC_INPUTS_ONLY", "new_governance_run": False,
                "network_calls_allowed": False, "step70": baseline,
                "normalizer_and_receipt": {"material_error": result.get("receipt_contract_error"),
                    "normalized_verdict": normalized["verdict"], "receipt_status": downstream["status"],
                    "validator_status": downstream["validator_status"],
                    "independence_proven": downstream["producer_independence_proven"],
                    "broken_input_accepted": downstream["status"] == "PASS"},
                "eval_negative_hash": rejected}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(execute(), ensure_ascii=False, indent=2) + "\n")
