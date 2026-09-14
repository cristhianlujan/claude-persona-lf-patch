#!/usr/bin/env python3
import argparse, json, re, sys
from pathlib import Path

PASS_VERDICTS = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
RETURN_VERDICTS = {"RETURN_TO_WORKER_FOR_SELF_REPAIR", "RETURN_TO_ORCHESTRATOR", "BLOCK_PIPELINE"}
HEX40 = re.compile(r"^[0-9a-f]{40}$")


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def block(reason, bundle=None, output=None):
    doc = {
        "contract_version": "S38_S36_ASSURANCE_ROUTER_V1",
        "route_from": "S38",
        "route_to": "S38",
        "route_state": "BLOCK_ROUTER_INPUT",
        "blocking_reason": reason,
        "mutation_policy": "READ_ONLY_EXPORT_ONLY",
        "authority": {"merge":"NONE","golden":"NONE","runtime":"NONE","scheduler":"NONE","production":"NONE","promotion":"NONE"}
    }
    if isinstance(bundle, dict):
        doc["review_case_id"] = bundle.get("review_case_id")
        doc["candidate_sha"] = (bundle.get("candidate_snapshot") or {}).get("s38_candidate_head")
    if output:
        Path(output).write_text(json.dumps(doc, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print(json.dumps(doc, sort_keys=True))
    return 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--bundle-ref", required=True)
    ap.add_argument("--expected-signer-digest", required=True)
    ap.add_argument("--routing-contract", required=True)
    ap.add_argument("--receipt")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    routing = load(args.routing_contract)
    if set(routing.get("core_transversal_strategies", {})) != {"S30","S31","S36","S38"}:
        return block("BLOCK_CORE_STRATEGY_TAXONOMY_INVALID", output=args.output)
    if routing.get("new_strategy_default") != "DO_NOT_CREATE":
        return block("BLOCK_ANTI_ATOMIZATION_POLICY_WEAKENED", output=args.output)

    bundle = load(args.bundle)
    case = bundle.get("review_case_id")
    if not isinstance(case, str) or not case.startswith("S38-DG-IR-"):
        return block("BLOCK_S38_REVIEW_CASE_INVALID", bundle, args.output)
    if bundle.get("execution_mode") != "INDEPENDENT_CHAT_CONTEXT":
        return block("BLOCK_REVIEW_MODE_NOT_INDEPENDENT", bundle, args.output)
    if bundle.get("producer_semantic_verdict", "__missing__") is not None:
        return block("BLOCK_PRODUCER_SEMANTIC_VERDICT_NOT_NULL", bundle, args.output)
    snap = bundle.get("candidate_snapshot") or {}
    candidate = snap.get("s38_candidate_head")
    if not isinstance(candidate, str) or not HEX40.fullmatch(candidate):
        return block("BLOCK_CANDIDATE_SHA_INVALID", bundle, args.output)
    trust = bundle.get("external_trust") or {}
    declared_signer = trust.get("expected_signer_digest_out_of_band")
    if args.expected_signer_digest != declared_signer or not HEX40.fullmatch(args.expected_signer_digest):
        return block("BLOCK_OUT_OF_BAND_SIGNER_DIGEST_MISMATCH", bundle, args.output)
    auth = bundle.get("authority") or bundle.get("signed_subject_authority") or {}
    if not auth or any(v != "NONE" for v in auth.values()):
        return block("BLOCK_S38_PACKAGE_AUTHORITY_ESCALATION", bundle, args.output)

    current_pins = bundle.get("current_candidate_pins") or []
    historical_pins = bundle.get("historical_frozen_artifacts") or []
    quality_pins = bundle.get("frozen_quality_pack") or []
    if not current_pins:
        return block("BLOCK_CURRENT_TCB_PIN_SET_EMPTY", bundle, args.output)
    if not quality_pins:
        return block("BLOCK_QUALITY_PACK_PIN_SET_EMPTY", bundle, args.output)

    verdict = None
    restrictions = []
    if args.receipt:
        receipt = load(args.receipt)
        if receipt.get("review_case_id") != case:
            return block("BLOCK_RECEIPT_REVIEW_CASE_MISMATCH", bundle, args.output)
        if receipt.get("execution_mode") != "INDEPENDENT_CHAT_CONTEXT" or receipt.get("semantic_status") != "EXECUTED_INDEPENDENT_CONTEXT":
            return block("BLOCK_RECEIPT_NOT_EXECUTED_INDEPENDENTLY", bundle, args.output)
        if receipt.get("reviewer_is_producer") is not False or receipt.get("producer_context_available") is not False:
            return block("BLOCK_RECEIPT_INDEPENDENCE_INVALID", bundle, args.output)
        src = receipt.get("source_bundle") or {}
        review = receipt.get("quality_review") or {}
        if src.get("artifact_ref") != args.bundle_ref or review.get("reviewed_artifact") != args.bundle_ref:
            return block("BLOCK_RECEIPT_BUNDLE_BINDING_MISMATCH", bundle, args.output)
        if receipt.get("review_completed") is not True or receipt.get("execution_blockers") not in ([], None):
            return block("BLOCK_RECEIPT_REVIEW_INCOMPLETE", bundle, args.output)
        verdict = review.get("verdict")
        restrictions = review.get("blocking_codes") or []
        if verdict in PASS_VERDICTS:
            route_state = "READY_FOR_S36_ASSURANCE_ENROLLMENT" if verdict == "PASS_TO_COMPOSER" else "READY_FOR_S36_ASSURANCE_ENROLLMENT_WITH_RESTRICTIONS"
            route_to = "S36"
        elif verdict in RETURN_VERDICTS:
            route_state = "RETURN_TO_S38_REPAIR"
            route_to = "S38"
        else:
            return block("BLOCK_RECEIPT_VERDICT_UNSUPPORTED", bundle, args.output)
    else:
        route_state = "WAIT_INDEPENDENT_REVIEW"
        route_to = "S38"

    invariants = [
        {"code":"S38_INDEPENDENT_REVIEW_REQUIRED","status":"CANDIDATE_FOR_S36","evidence":{"review_case_id":case,"bundle_ref":args.bundle_ref}},
        {"code":"S38_EXTERNAL_SIGNER_IDENTITY_BOUND","status":"CANDIDATE_FOR_S36","evidence":{"expected_signer_digest":args.expected_signer_digest,"signer_workflow_ref":trust.get("signer_workflow_ref")}},
        {"code":"S38_CURRENT_TCB_PIN_COMPLETENESS","status":"CANDIDATE_FOR_S36","evidence":{"declared_pin_count":len(current_pins)}},
        {"code":"S38_HISTORICAL_IDENTITY_PIN_COMPLETENESS","status":"CANDIDATE_FOR_S36","evidence":{"declared_pin_count":len(historical_pins)}},
        {"code":"S38_FROZEN_QUALITY_PACK_BINDING","status":"CANDIDATE_FOR_S36","evidence":{"declared_pin_count":len(quality_pins)}},
        {"code":"S38_NO_AUTHORITY_ESCALATION","status":"CANDIDATE_FOR_S36","evidence":{"authority":auth}},
        {"code":"S38_OFFLINE_REPRODUCIBILITY_AFTER_TRUST_BOOTSTRAP","status":"CANDIDATE_FOR_S36","evidence":{"runtime_network_required_after_verified_subject_bootstrap":trust.get("runtime_network_required_after_verified_subject_bootstrap")}},
        {"code":"S38_PRODUCER_SEMANTIC_VERDICT_MUST_REMAIN_NULL","status":"CANDIDATE_FOR_S36","evidence":{"producer_semantic_verdict":bundle.get("producer_semantic_verdict")}}
    ]
    doc = {
        "contract_version":"S38_S36_ASSURANCE_ROUTER_V1",
        "route_from":"S38",
        "route_to":route_to,
        "route_state":route_state,
        "review_case_id":case,
        "candidate_sha":candidate,
        "bundle_ref":args.bundle_ref,
        "expected_signer_digest":args.expected_signer_digest,
        "independent_verdict":verdict,
        "independent_blocking_codes":restrictions,
        "assurance_invariants":invariants,
        "s36_policy":"ENROLL_IN_ONE_CANONICAL_LF_TEST_MATRIX_ONLY",
        "new_strategy_policy":"DO_NOT_CREATE_BY_DEFAULT_ROUTE_AS_WORK_PACKAGE",
        "mutation_policy":"READ_ONLY_EXPORT_ONLY",
        "authority":{"merge":"NONE","golden":"NONE","runtime":"NONE","scheduler":"NONE","production":"NONE","promotion":"NONE","supabase_mutation":"NONE"}
    }
    Path(args.output).write_text(json.dumps(doc, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print(json.dumps({"route_state":route_state,"route_to":route_to,"review_case_id":case,"invariant_count":len(invariants)}, sort_keys=True))
    return 0

if __name__ == "__main__":
    sys.exit(main())
