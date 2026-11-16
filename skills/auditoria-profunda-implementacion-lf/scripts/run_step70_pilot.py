#!/usr/bin/env python3
"""Reproduce local LF helper behavior; no network, SQL invocation or real RUN.

Synthetic receipt values are imported from LF's EXISTING unit tests. They are
never persisted as governance receipts. The target implementation is unmodified.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _observe():
    # Import-time env prerequisite only. Network calls are not exercised.
    os.environ.setdefault("LF_PROFILE_EDGE_URL", "https://local-test-only.invalid")
    sys.path.insert(0, str(ROOT / "scripts"))
    receipts = load(ROOT / "scripts/lf_step70_separate_call_receipt_v1.py", "lf_step70_separate_call_receipt_v1")
    evaluator = load(ROOT / "scripts/lf_step70_same_llm_eval_v1.py", "lf_step70_same_llm_eval_v1")
    native = load(ROOT / "scripts/lf_profile_native_resume.py", "lf_deep_audit_native_pilot")
    fixtures = load(ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/test_step70_same_llm_separate_call_v1.py", "lf_deep_audit_existing_test_fixture")
    clean = load(ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/test_step70_clean_eval_runner_v1.py", "lf_deep_audit_existing_clean_fixture")
    good = fixtures.fixture()
    explicit_good = receipts.assess_separate_call_receipt(good, execution_id=fixtures.RUN)
    wrong_run = copy.deepcopy(good)
    wrong_run["separate_model_call_receipt"]["execution_id"] = "EXEC-PROFILE-GATE2-FIXTURE_OTHER_RUN"
    caller_shape = receipts.assess_separate_call_receipt(wrong_run)
    try:
        receipts.assess_separate_call_receipt(wrong_run, execution_id=fixtures.RUN)
    except ValueError as exc:
        bound_rejection = str(exc)
    else:
        bound_rejection = None
    # Divergent outer review and failing nested EVAL are a consistency probe.
    top = clean.case()
    top.update(review_mode="INDEPENDENT_SEMANTIC", verdict="PASS_INDEPENDENT_SEMANTIC",
               separate_model_call_receipt=copy.deepcopy(good["separate_model_call_receipt"]))
    top["separate_model_call_receipt"]["decision_body"]["unsupported_claims"] = ["FIXTURE_UNSUPPORTED_CLAIM"]
    normalized, assessment = receipts.normalize_when_unverified(top)
    try:
        native.validate_independent_semantic_review(normalized)
    except ValueError as exc:
        downstream = {"accepted": False, "error": str(exc)}
    else:
        downstream = {"accepted": True, "error": None}
    valid_top = copy.deepcopy(top)
    valid_top["separate_model_call_receipt"]["decision_body"]["unsupported_claims"] = []
    _, valid_assessment = receipts.normalize_when_unverified(valid_top)
    r = good["separate_model_call_receipt"]
    raw = {"schema_id": r["schema_id"], "execution_id": r["execution_id"],
           "candidate_sha256": r["candidate_sha256"], "scope_packet_sha256": r["scope_packet_sha256"],
           "verdict": r["decision_body"]["verdict"], "decision_body": r["decision_body"],
           "source_refs": ["x"]}
    eval_short = evaluator.evaluate(raw, r["execution_id"], r["candidate_sha256"], r["scope_packet_sha256"])
    from jsonschema import Draft202012Validator
    schema = json.loads((ROOT / "profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json").read_text())
    rejected_by_schema = [e.message for e in Draft202012Validator(schema).iter_errors(raw)]
    raw_valid = {**raw, "source_refs": good["source_refs"]}
    valid_schema_errors = [e.message for e in Draft202012Validator(schema).iter_errors(raw_valid)]
    return {"execution_scope": "LOCAL_REAL_LF_HELPER_WITH_EXISTING_SYNTHETIC_INPUTS",
            "real_governance_run_created": False, "network_calls": 0,
            "database_writes": 0, "lf_functional_files_modified": [],
            "run_binding": {"valid_explicit_evaluator_status": explicit_good.get("evaluator_status"),
                "actual_caller_shape_status": caller_shape["status"],
                "wrong_run_evaluator_status": caller_shape.get("evaluator_status"),
                "explicit_binding_rejects": bound_rejection},
            "eval_masking": {"failing_nested_eval_error": assessment.get("receipt_contract_error"),
                "normalized_verdict": normalized["verdict"],
                "original_receipt_retained": "separate_model_call_receipt" in normalized,
                "content_continuation_allowed": assessment["content_continuation_allowed"],
                "downstream_validator": downstream,
                "valid_receipt_baseline_status": valid_assessment["status"]},
            "schema_eval": {"invalid_input": {"source_refs": ["x"]},
                "evaluator_status": eval_short["eval_status"], "schema_errors": rejected_by_schema,
                "valid_schema_errors": valid_schema_errors,
                "valid_evaluator_status": evaluator.evaluate(raw_valid, r["execution_id"], r["candidate_sha256"], r["scope_packet_sha256"])["eval_status"]}}


def observe():
    # The reviewed LF helper uses urllib. Any attempted transport fails locally;
    # record intercepted call counts rather than claiming a real external trace.
    with patch("urllib.request.urlopen", side_effect=AssertionError("PILOT_NETWORK_FORBIDDEN")) as http:
        with patch("socket.create_connection", side_effect=AssertionError("PILOT_NETWORK_FORBIDDEN")) as sockets:
            result = _observe()
            result["network_interception"] = {"urllib_urlopen_calls": http.call_count,
                                               "socket_create_connection_calls": sockets.call_count}
            if http.call_count or sockets.call_count:
                raise AssertionError("PILOT_ATTEMPTED_NETWORK")
            return result


def main():
    import argparse
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    result = observe()
    data = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(data, encoding="utf8")
    else:
        print(data, end="")


if __name__ == "__main__":
    main()
