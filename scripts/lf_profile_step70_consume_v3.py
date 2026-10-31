#!/usr/bin/env python3
"""Issue #3401: consume an independently produced Product Director V3 verdict and record ONLY step 70.

Does not invoke the producer, fabricate a semantic verdict, touch step 80 or re-enter Router.
Usage: python scripts/lf_profile_step70_consume_v3.py --execution-id EXEC-... --verdict review.json
Environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""
import argparse
import json
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

CHECKS = (
    "context_resolution_valid", "evidence_supported", "decision_resolves_objective",
    "authority_resolution_valid", "constraints_preserved", "claims_authorized",
    "materiality_handled_correctly", "tradeoff_defensible",
    "acceptance_detects_wrong_implementation", "handoff_implementation_ready",
    "router_direct_consistency", "counterfactual_trajectory",
)
PASS = "PASS_INDEPENDENT_SEMANTIC"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def api(method, path, data=None):
    root = os.environ["SUPABASE_URL"].rstrip("/")
    token = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {"apikey": token, "Authorization": "Bearer " + token, "Content-Type": "application/json"}
    if method == "GET":
        headers["Accept"] = "application/json"
    request = Request(root + path, data=None if data is None else json.dumps(data).encode(), headers=headers, method=method)
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as exc:
        raise RuntimeError(f"{method} {path}: HTTP {exc.code} {exc.read().decode()[:1500]}") from exc


def check_verdict(v):
    require(v.get("verdict") == PASS, "Step 70 PASS registration requires a genuine independent PASS; non-PASS verdicts must be returned as structured errors to the final reporter")
    checks = v.get("decision_checks")
    require(isinstance(checks, dict) and set(checks) == set(CHECKS), "Exactly 12 V3 checks required")
    for name, check in checks.items():
        require(isinstance(check, dict) and check.get("result") in (True, "true"), f"{name} not PASS")
        require(check.get("reason") and isinstance(check.get("source_refs"), list), f"{name}: missing rationale/refs")
    require(v.get("producer_independence_proven") is True, "Independence unproven")
    require(v.get("model_call_count") == 1, "Requires one real independent judge model call")
    require(v.get("unsupported_claims") == [], "Unsupported claims must be empty")
    require(v.get("blocking_codes") == [], "Blocking codes must be empty")
    require(isinstance(v.get("source_refs"), list) and v["source_refs"], "Inspected sources required")
    require(isinstance(v.get("resolved_context_refs"), list) and v["resolved_context_refs"], "Context required")
    require(v.get("independent_semantic_receipt_ref"), "Independent receipt ref required")
    require(v.get("router_direct_consistency") in ("NOT_TESTED", "PASS"), "Router/direct unexplained divergence")
    require(v.get("counterfactual_result"), "Counterfactual evaluation required")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--execution-id", required=True)
    parser.add_argument("--verdict", required=True, help="Independent V3 result JSON; never the producer's self-verdict")
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs only, no RPC call")
    args = parser.parse_args()
    with open(args.verdict, encoding="utf-8") as handle:
        review = json.load(handle)
    check_verdict(review)
    eid = args.execution_id
    rows = api("GET", "/rest/v1/lf_operation_execution_steps?execution_id=eq." + eid + "&select=step_id,status,evidence_payload")
    by_step = {row["step_id"]: row for row in rows}
    require(all(by_step.get(k, {}).get("status") == "STEP_PASS_WITH_EVIDENCE" for k in (
        "init_execution", "router", "profile_resolve", "profile_source_read", "input_validate",
        "context_admission", "research_baseline_freeze", "execute_profile", "output_validate",
    )), "9 predecessor steps must be clean")
    require("semantic_judge" not in by_step and "report_output" not in by_step,
            "Step 70/80 already present: do not replay")
    candidate = by_step["execute_profile"]["evidence_payload"]["candidate_digest"]
    scope = by_step["input_validate"]["evidence_payload"]["scope_authority_packet_sha256"]
    require(review.get("candidate_sha256") == candidate.removeprefix("sha256:"), "Candidate SHA mismatch")
    require(review.get("scope_packet_sha256") == scope.removeprefix("sha256:"), "Scope SHA mismatch")
    require(review.get("execution_id") == eid, "Execution ID mismatch")
    receipt = {
        "status": "PASS", "verdict": PASS, "validator_status": "PASS",
        "producer_independence_proven": True, "model_call_count": 1,
        "candidate_sha256": review["candidate_sha256"],
        "scope_packet_sha256": review["scope_packet_sha256"],
        "result": {
            "verdict": PASS, "candidate_sha256": review["candidate_sha256"],
            "scope_packet_sha256": review["scope_packet_sha256"],
            "unsupported_claims": [], "blocking_codes": [],
        },
        "judge_v3_evidence": review,
    }
    payload = {
        "semantic_judge_result": receipt, "unsupported_claims": [],
        "independent_semantic_receipt_ref": review["independent_semantic_receipt_ref"],
    }
    if args.dry_run:
        print(json.dumps({"status": "DRY_RUN_VALID", "step": 70, "execution_id": eid, "validated_payload": payload, "rpc": "lf_record_profile_execution_step_v1"}))
        return
    response = api("POST", "/rest/v1/rpc/lf_record_profile_execution_step_v1", {
        "p_execution_id": eid, "p_step_id": "semantic_judge",
        "p_evidence_ref": review["independent_semantic_receipt_ref"],
        "p_evidence_payload": payload, "p_actor_execution_id": eid,
    })
    print(json.dumps({"rpc_response": response}))
    require(response.get("outcome") == "STEP_RECORDED" and response.get("status") == "STEP_PASS_WITH_EVIDENCE",
            "Recorder did not confirm PASS")
    confirmed = api("GET", "/rest/v1/lf_operation_execution_steps?execution_id=eq." + eid + "&step_id=eq.semantic_judge&select=step_id,status,evidence_payload")
    require(len(confirmed) == 1 and confirmed[0]["status"] == "STEP_PASS_WITH_EVIDENCE",
            "Step 70 readback failed")
    print(json.dumps({"step": 70, "status": "STEP_PASS_WITH_EVIDENCE", "readback": "CONFIRMED"}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, RuntimeError, OSError) as exc:
        print(json.dumps({"status": "BLOCKED", "step": 70, "error": str(exc)}), file=sys.stderr)
        sys.exit(1)
