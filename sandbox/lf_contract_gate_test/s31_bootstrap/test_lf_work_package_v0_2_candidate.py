#!/usr/bin/env python3
import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

p = Path(__file__).with_name("validate_lf_work_package_v0_2_candidate.py")
s = importlib.util.spec_from_file_location("lf_wp_v02", p)
m = importlib.util.module_from_spec(s)
sys.modules[s.name] = m
s.loader.exec_module(m)

SHA_A = "a" * 40
SHA_B = "b" * 40


def digest(record):
    raw = json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def fixture():
    evidence = {
        "receipt://validation": {
            "evidence_type": "EXECUTED_VALIDATION_RECEIPT",
            "resolver_id": "EXECUTION_EVIDENCE_RESOLVER",
            "status": "PASS",
            "executed_sha": SHA_B,
            "command_or_runner": "python test.py",
            "exit_status": 0,
        },
        "receipt://ekb-freshness": {
            "evidence_type": "EKB_FRESHNESS_RECEIPT",
            "resolver_id": "EKB_EVIDENCE_RESOLVER",
            "status": "PASS",
            "run_id": "EKB-RUN-TEST",
            "resolved_at": "2026-09-12T19:00:00-05:00",
            "applicable_codes": ["GOV-010", "PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001"],
            "control_mapping": {
                "GOV-010": "PREFLIGHT",
                "PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001": "CLOSE_GUARD",
            },
        },
        "receipt://currentness": {
            "evidence_type": "CURRENTNESS_RECEIPT",
            "resolver_id": "CURRENTNESS_EVIDENCE_RESOLVER",
            "status": "PASS",
            "base_sha": SHA_A,
            "branch_head_sha": SHA_B,
            "executed_sha": SHA_B,
            "execution_ref_kind": "BRANCH_HEAD",
            "exact_head_claim": True,
        },
        "receipt://ekb-final": {
            "evidence_type": "EKB_FINAL_READBACK_RECEIPT",
            "resolver_id": "EKB_FINAL_READBACK_RESOLVER",
            "status": "PASS",
            "executed_sha": SHA_B,
            "applicable_codes": ["GOV-010", "PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001"],
        },
    }
    wp = {
        "schema_id":"LF_WORK_PACKAGE_V0_2_CANDIDATE",
        "work_package_id":"WP-S31-B-TEST",
        "strategy_id":"S31",
        "lane_id":"S31-B",
        "operation":"WORK_PACKAGE_EVOLUTION",
        "objective":"Validate the transversal LF Work Package candidate with deterministic anti-close and currentness guards.",
        "execution_identity":{"base_sha":SHA_A,"branch_head_sha":SHA_B,"executed_sha":SHA_B,"execution_ref_kind":"BRANCH_HEAD","exact_head_claim":True},
        "source_snapshot_bindings":[{"source_ref":"github://source","material":True,"binding_kind":"GIT_COMMIT","revision":SHA_A,"digest":None,"authority_receipt_ref":None}],
        "causal_ownership":{"key":"S31-B:WP","active_writer":"S31-B","dependencies":[],"safe_parallel_scope":["S31-C"]},
        "authority":{"sources":["S30","EKB"],"contracts":["S31_S30_EXECUTION_CONTROL_REUSE_BINDING_V0_1"],"ekb_execution_binding":{"run_id":"EKB-RUN-TEST","resolved_at":"2026-09-12T19:00:00-05:00","applicable_codes":["GOV-010","PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001"],"control_mapping":{"GOV-010":"PREFLIGHT","PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001":"CLOSE_GUARD"},"fresh_for_execution":True}},
        "scope":{"read":["main/**"],"write":["sandbox/lf_contract_gate_test/s31_bootstrap/**"],"forbidden":["main","S30_INTERNALS","S26_INTERNALS","PRODUCTION"]},
        "execution":{"worker":"GPT","port":"GITHUB","adapter":"S31_SANDBOX","allowed_tools":["GITHUB_READ","GITHUB_WRITE_S31"],"retry_policy":{"max_attempts":2,"same_failure_retries_forbidden":True},"executed_validation":{"required":True,"command_or_runner":"python test.py","executed_sha":SHA_B,"exit_status":0,"receipt_ref":"receipt://validation"}},
        "resolved_evidence": {
            "executed_validation_receipt":{"ref":"receipt://validation","digest":digest(evidence["receipt://validation"]),"resolver_id":"EXECUTION_EVIDENCE_RESOLVER"},
            "ekb_freshness_receipt":{"ref":"receipt://ekb-freshness","digest":digest(evidence["receipt://ekb-freshness"]),"resolver_id":"EKB_EVIDENCE_RESOLVER"},
            "currentness_receipt":{"ref":"receipt://currentness","digest":digest(evidence["receipt://currentness"]),"resolver_id":"CURRENTNESS_EVIDENCE_RESOLVER"},
            "ekb_final_readback_receipt":{"ref":"receipt://ekb-final","digest":digest(evidence["receipt://ekb-final"]),"resolver_id":"EKB_FINAL_READBACK_RESOLVER"}
        },
        "preflight":{"required_checks":["EKB","CURRENTNESS","OWNERSHIP"],"material_work_gate":"FAIL_CLOSED","result":"PASS_TO_MATERIAL_WORK"},
        "obligations":{"acceptance":["SAFE_WORK_CONTINUES"],"failure":["PREMATURE_CLOSE"],"blocking":["STALE_AUTHORITY"]},
        "evidence":{"required_receipts":["CURRENTNESS","VALIDATION"],"claim_ceiling":"CANDIDATE_ONLY","provenance_required":True},
        "judge":{"independent_required":True,"self_certification_forbidden":True,"binding":"INDEPENDENT_REVIEW"},
        "repair_policy":{"bounded":True,"requires_new_evidence_after_failure":True,"silent_repair_forbidden":True},
        "frontier":{"current_stage":"VALIDATION","next_gate":"CLOSE","blockers":[],"safe_parallel_work":[],"remaining_safe_scope_count":0,"next_safe_batch":"NONE","targeted_scope_dispositions":{"S31-B":"TERMINAL_CANDIDATE"},"global_remaining_work_scan":"PASS"},
        "close_guard":{"can_close":True,"safe_work_remaining_count":0,"next_safe_batch":"NONE","global_remaining_work_scan":"PASS","ekb_final_readback_verified":True,"currentness_verified":True,"terminal_disposition_complete":True},
        "handoff_contract":{"typed_result":{},"current_frontier":{},"next_owner":"INDEPENDENT_REVIEW","next_gate":"SEMANTIC_REVIEW"}
    }
    return wp, evidence


def run(wp, evidence):
    return m.evaluate_work_package(wp, lambda ref: evidence.get(ref))


cases = 0
wp, evd = fixture(); r = run(wp, evd)
assert r["status"] == m.PASS and r["code"] == "PASS_CLOSE_GUARD", r; cases += 1

wp, evd = fixture()
wp["frontier"].update({"blockers":[{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":["S31-C"],"invalidation_condition":"REVIEW_RECEIPT"}],"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"})
wp["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = run(wp, evd); assert r["status"] == m.CONTINUE and r["code"] == "CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE", r; cases += 1

wp, evd = fixture(); wp["source_snapshot_bindings"][0]["revision"] = None
assert run(wp, evd)["code"] == "BLOCK_SCHEMA_VALIDATION"; cases += 1

wp, evd = fixture(); wp["execution"]["executed_validation"].update({"command_or_runner":None,"executed_sha":None,"exit_status":None,"receipt_ref":None})
assert run(wp, evd)["code"] == "BLOCK_SCHEMA_VALIDATION"; cases += 1

wp, evd = fixture(); wp["execution_identity"]["execution_ref_kind"] = "PR_MERGE_REF"
assert run(wp, evd)["code"] == "BLOCK_EXACT_HEAD_REF_KIND_INVALID"; cases += 1

wp, evd = fixture(); wp["execution_identity"]["executed_sha"] = SHA_A
assert run(wp, evd)["code"] == "BLOCK_EXACT_HEAD_SHA_MISMATCH"; cases += 1

wp, evd = fixture(); wp["authority"]["ekb_execution_binding"]["fresh_for_execution"] = False
assert run(wp, evd)["code"] == "BLOCK_EKB_BINDING_NOT_FRESH"; cases += 1

wp, evd = fixture(); del wp["authority"]["ekb_execution_binding"]["control_mapping"]["GOV-010"]
assert run(wp, evd)["code"] == "BLOCK_EKB_CONTROL_MAPPING_MISSING"; cases += 1

wp, evd = fixture(); wp["execution"]["retry_policy"]["same_failure_retries_forbidden"] = False
assert run(wp, evd)["code"] == "BLOCK_SAME_FAILURE_RETRY_ALLOWED"; cases += 1

wp, evd = fixture(); wp["close_guard"]["next_safe_batch"] = "S31-D"; wp["frontier"]["next_safe_batch"] = "S31-D"
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_NEXT_SAFE_BATCH_WITH_ZERO_COUNT", r; cases += 1

wp, evd = fixture(); wp["close_guard"]["global_remaining_work_scan"] = "NOT_RUN"; wp["frontier"]["global_remaining_work_scan"] = "NOT_RUN"
r = run(wp, evd); assert r["status"] == m.BLOCKED and "GLOBAL_REMAINING_WORK_SCAN_NOT_PASS" in r["reasons"], r; cases += 1

wp, evd = fixture(); del wp["objective"]
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SCHEMA_VALIDATION", r; cases += 1

wp, evd = fixture(); wp["execution"]["executed_validation"]["executed_sha"] = "not-a-sha"
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SCHEMA_VALIDATION", r; cases += 1

wp, evd = fixture(); wp["frontier"]["safe_parallel_work"] = ["S31-C"]
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SAFE_WORK_COUNT_MISMATCH", r; cases += 1

wp, evd = fixture(); wp["frontier"].update({"safe_parallel_work":["S31-C","S31-D"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); wp["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SAFE_WORK_COUNT_MISMATCH", r; cases += 1

wp, evd = fixture(); wp["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-D"}); wp["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-D","terminal_disposition_complete":False})
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_NEXT_SAFE_BATCH_NOT_LISTED", r; cases += 1

wp, evd = fixture(); wp["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); wp["close_guard"].update({"can_close":False,"safe_work_remaining_count":0,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_FRONTIER_CLOSE_COUNT_MISMATCH", r; cases += 1

wp, evd = fixture(); wp["frontier"]["blockers"] = [{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":[],"invalidation_condition":"REVIEW_RECEIPT"}]
r = run(wp, evd); assert r["status"] == m.BLOCKED and r["code"] == "BLOCKED_CAUSAL_NO_SAFE_WORK", r; cases += 1

# Independent review regression: executed validation SHA must equal governed execution identity.
wp, evd = fixture(); wp["execution"]["executed_validation"]["executed_sha"] = SHA_A
r = run(wp, evd); assert r["code"] == "BLOCK_VALIDATION_EXECUTED_SHA_IDENTITY_MISMATCH", r; cases += 1

# A cryptographically valid receipt for the wrong SHA still fails content binding.
wp, evd = fixture(); evd["receipt://validation"]["executed_sha"] = SHA_A; wp["resolved_evidence"]["executed_validation_receipt"]["digest"] = digest(evd["receipt://validation"])
r = run(wp, evd); assert r["code"] == "BLOCK_VALIDATION_RECEIPT_CONTENT_MISMATCH", r; cases += 1

# Receipt content cannot be changed without invalidating its declared digest.
wp, evd = fixture(); wp["resolved_evidence"]["executed_validation_receipt"]["digest"] = "f" * 64
r = run(wp, evd); assert r["code"] == "BLOCK_EVIDENCE_DIGEST_MISMATCH", r; cases += 1

# Self-declared booleans cannot pass without an actual evidence resolver.
wp, evd = fixture(); r = m.evaluate_work_package(wp, None)
assert r["code"] == "BLOCK_EVIDENCE_RESOLVER_MISSING", r; cases += 1

# EKB freshness receipt must match the exact governed run, time, codes and control mapping.
wp, evd = fixture(); evd["receipt://ekb-freshness"]["run_id"] = "EKB-OTHER"; wp["resolved_evidence"]["ekb_freshness_receipt"]["digest"] = digest(evd["receipt://ekb-freshness"])
r = run(wp, evd); assert r["code"] == "BLOCK_EKB_RECEIPT_MISMATCH", r; cases += 1

# Currentness receipt must match the governed exact branch head and execution identity.
wp, evd = fixture(); evd["receipt://currentness"]["branch_head_sha"] = SHA_A; wp["resolved_evidence"]["currentness_receipt"]["digest"] = digest(evd["receipt://currentness"])
r = run(wp, evd); assert r["code"] == "BLOCK_CURRENTNESS_RECEIPT_IDENTITY_MISMATCH", r; cases += 1

# The execution worker cannot resolve/certify its own currentness evidence.
wp, evd = fixture(); evd["receipt://currentness"]["resolver_id"] = "GPT"; wp["resolved_evidence"]["currentness_receipt"]["resolver_id"] = "GPT"; wp["resolved_evidence"]["currentness_receipt"]["digest"] = digest(evd["receipt://currentness"])
r = run(wp, evd); assert r["code"] == "BLOCK_EVIDENCE_SELF_RESOLVER", r; cases += 1

# Final EKB readback boolean is not enough: resolved final evidence must bind to the executed SHA.
wp, evd = fixture(); evd["receipt://ekb-final"]["executed_sha"] = SHA_A; wp["resolved_evidence"]["ekb_final_readback_receipt"]["digest"] = digest(evd["receipt://ekb-final"])
r = run(wp, evd); assert r["code"] == "BLOCK_EKB_FINAL_READBACK_RECEIPT_MISMATCH", r; cases += 1

print(f"PASS_LF_WORK_PACKAGE_V0_2_CANDIDATE_SELFTEST={cases}/{cases}")
