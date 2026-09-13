#!/usr/bin/env python3
import importlib.util
import sys
from pathlib import Path

p = Path(__file__).with_name("validate_lf_work_package_v0_2_candidate.py")
s = importlib.util.spec_from_file_location("lf_wp_v02", p)
m = importlib.util.module_from_spec(s)
sys.modules[s.name] = m
s.loader.exec_module(m)

SHA_A = "a" * 40
SHA_B = "b" * 40


def base():
    return {
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
        "execution":{"worker":"GPT","port":"GITHUB","adapter":"S31_SANDBOX","allowed_tools":["GITHUB_READ","GITHUB_WRITE_S31"],"retry_policy":{"max_attempts":2,"same_failure_retries_forbidden":True},"executed_validation":{"required":True,"command_or_runner":"python test.py","executed_sha":SHA_B,"exit_status":0,"receipt_ref":"receipt://test"}},
        "preflight":{"required_checks":["EKB","CURRENTNESS","OWNERSHIP"],"material_work_gate":"FAIL_CLOSED","result":"PASS_TO_MATERIAL_WORK"},
        "obligations":{"acceptance":["SAFE_WORK_CONTINUES"],"failure":["PREMATURE_CLOSE"],"blocking":["STALE_AUTHORITY"]},
        "evidence":{"required_receipts":["CURRENTNESS","VALIDATION"],"claim_ceiling":"CANDIDATE_ONLY","provenance_required":True},
        "judge":{"independent_required":True,"self_certification_forbidden":True,"binding":"INDEPENDENT_REVIEW"},
        "repair_policy":{"bounded":True,"requires_new_evidence_after_failure":True,"silent_repair_forbidden":True},
        "frontier":{"current_stage":"VALIDATION","next_gate":"CLOSE","blockers":[],"safe_parallel_work":[],"remaining_safe_scope_count":0,"next_safe_batch":"NONE","targeted_scope_dispositions":{"S31-B":"TERMINAL_CANDIDATE"},"global_remaining_work_scan":"PASS"},
        "close_guard":{"can_close":True,"safe_work_remaining_count":0,"next_safe_batch":"NONE","global_remaining_work_scan":"PASS","ekb_final_readback_verified":True,"currentness_verified":True,"terminal_disposition_complete":True},
        "handoff_contract":{"typed_result":{},"current_frontier":{},"next_owner":"INDEPENDENT_REVIEW","next_gate":"SEMANTIC_REVIEW"}
    }


r = m.evaluate_work_package(base())
assert r["status"] == m.PASS and r["code"] == "PASS_CLOSE_GUARD", r

x = base()
x["frontier"].update({"blockers":[{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":["S31-C"],"invalidation_condition":"REVIEW_RECEIPT"}],"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"})
x["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = m.evaluate_work_package(x)
assert r["status"] == m.CONTINUE and r["code"] == "CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE", r

x = base(); x["source_snapshot_bindings"][0]["revision"] = None
assert m.evaluate_work_package(x)["code"] == "BLOCK_SCHEMA_VALIDATION"

x = base(); x["execution"]["executed_validation"].update({"command_or_runner":None,"executed_sha":None,"exit_status":None,"receipt_ref":None})
assert m.evaluate_work_package(x)["code"] == "BLOCK_SCHEMA_VALIDATION"

x = base(); x["execution_identity"]["execution_ref_kind"] = "PR_MERGE_REF"
assert m.evaluate_work_package(x)["code"] == "BLOCK_EXACT_HEAD_REF_KIND_INVALID"

x = base(); x["execution_identity"]["executed_sha"] = SHA_A
assert m.evaluate_work_package(x)["code"] == "BLOCK_EXACT_HEAD_SHA_MISMATCH"

x = base(); x["authority"]["ekb_execution_binding"]["fresh_for_execution"] = False
assert m.evaluate_work_package(x)["code"] == "BLOCK_EKB_BINDING_NOT_FRESH"

x = base(); del x["authority"]["ekb_execution_binding"]["control_mapping"]["GOV-010"]
assert m.evaluate_work_package(x)["code"] == "BLOCK_EKB_CONTROL_MAPPING_MISSING"

x = base(); x["execution"]["retry_policy"]["same_failure_retries_forbidden"] = False
assert m.evaluate_work_package(x)["code"] == "BLOCK_SAME_FAILURE_RETRY_ALLOWED"

x = base(); x["close_guard"]["next_safe_batch"] = "S31-D"; x["frontier"]["next_safe_batch"] = "S31-D"
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_NEXT_SAFE_BATCH_WITH_ZERO_COUNT", r

x = base(); x["close_guard"]["global_remaining_work_scan"] = "NOT_RUN"; x["frontier"]["global_remaining_work_scan"] = "NOT_RUN"
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and "GLOBAL_REMAINING_WORK_SCAN_NOT_PASS" in r["reasons"], r

x = base(); del x["objective"]
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SCHEMA_VALIDATION", r

x = base(); x["execution"]["executed_validation"]["executed_sha"] = "not-a-sha"
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SCHEMA_VALIDATION", r

x = base(); x["frontier"]["safe_parallel_work"] = ["S31-C"]
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SAFE_WORK_COUNT_MISMATCH", r

x = base(); x["frontier"].update({"safe_parallel_work":["S31-C","S31-D"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); x["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_SAFE_WORK_COUNT_MISMATCH", r

x = base(); x["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-D"}); x["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-D","terminal_disposition_complete":False})
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_NEXT_SAFE_BATCH_NOT_LISTED", r

x = base(); x["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); x["close_guard"].update({"can_close":False,"safe_work_remaining_count":0,"next_safe_batch":"S31-C","terminal_disposition_complete":False})
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCK_FRONTIER_CLOSE_COUNT_MISMATCH", r

x = base(); x["frontier"]["blockers"] = [{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":[],"invalidation_condition":"REVIEW_RECEIPT"}]
r = m.evaluate_work_package(x)
assert r["status"] == m.BLOCKED and r["code"] == "BLOCKED_CAUSAL_NO_SAFE_WORK", r

print("PASS_LF_WORK_PACKAGE_V0_2_CANDIDATE_SELFTEST=18/18")
