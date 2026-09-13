#!/usr/bin/env python3
import copy
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
p = ROOT / "validate_lf_work_package_v0_2_candidate.py"
s = importlib.util.spec_from_file_location("lf_wp_v02", p)
m = importlib.util.module_from_spec(s)
sys.modules[s.name] = m
s.loader.exec_module(m)

RESOLVER = m.TrustedRefResolver(ROOT)
HEAD = RESOLVER.head
BASE = "3b39657fbf14f29c7839ecb26d715ed5c6fad59e"
TRUST = m.TRUSTED_RESOLVER_ID
EVIDENCE = "sandbox/lf_contract_gate_test/s31_bootstrap/trusted_evidence"


def ref(name):
    return f"github://{RESOLVER.repo}@{HEAD}/{EVIDENCE}/{name}"


def binding(name):
    r = ref(name)
    observed = RESOLVER.resolve(r)
    return {"ref": r, "digest": observed["sha256"], "resolver_id": TRUST}


def fixture():
    val = binding("b_validation_receipt.json")
    wp = {
        "schema_id":"LF_WORK_PACKAGE_V0_2_CANDIDATE",
        "work_package_id":"WP-S31-B-TEST",
        "strategy_id":"S31","lane_id":"S31-B","operation":"WORK_PACKAGE_EVOLUTION",
        "objective":"Validate trusted provider-bound evidence and anti-close guards for LF Work Package.",
        "execution_identity":{"base_sha":BASE,"branch_head_sha":HEAD,"executed_sha":HEAD,"execution_ref_kind":"BRANCH_HEAD","exact_head_claim":True},
        "source_snapshot_bindings":[{"source_ref":"github://source","material":True,"binding_kind":"GIT_COMMIT","revision":BASE,"digest":None,"authority_receipt_ref":None}],
        "causal_ownership":{"key":"S31-B:WP","active_writer":"S31-B","dependencies":[],"safe_parallel_scope":["S31-C"]},
        "authority":{"sources":["S30","EKB"],"contracts":["S31_S30_EXECUTION_CONTROL_REUSE_BINDING_V0_1"],"ekb_execution_binding":{"run_id":"EKB-RUN-TEST","resolved_at":"2026-09-12T19:00:00-05:00","applicable_codes":["GOV-010","PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001"],"control_mapping":{"GOV-010":"PREFLIGHT","PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001":"CLOSE_GUARD"},"fresh_for_execution":True}},
        "scope":{"read":["main/**"],"write":["sandbox/lf_contract_gate_test/s31_bootstrap/**"],"forbidden":["main","S30_INTERNALS","S26_INTERNALS","PRODUCTION"]},
        "execution":{"worker":"GPT","port":"GITHUB","adapter":"S31_SANDBOX","allowed_tools":["GITHUB_READ","GITHUB_WRITE_S31"],"retry_policy":{"max_attempts":2,"same_failure_retries_forbidden":True},"executed_validation":{"required":True,"command_or_runner":"python test.py","executed_sha":HEAD,"exit_status":0,"receipt_ref":val["ref"]}},
        "resolved_evidence": {
            "executed_validation_receipt":val,
            "ekb_freshness_receipt":binding("b_ekb_freshness_receipt.json"),
            "currentness_receipt":binding("b_currentness_receipt.json"),
            "ekb_final_readback_receipt":binding("b_ekb_final_receipt.json")
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
    return wp


def run(wp, resolver=RESOLVER):
    return m.evaluate_work_package(wp, resolver)

cases=0
wp=fixture(); r=run(wp); assert r["status"]==m.PASS and r["code"]=="PASS_CLOSE_GUARD",r; cases+=1
wp=fixture(); wp["frontier"].update({"blockers":[{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":["S31-C"],"invalidation_condition":"REVIEW_RECEIPT"}],"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); wp["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False}); r=run(wp); assert r["status"]==m.CONTINUE; cases+=1

# Legacy anti-close/currentness negatives.
for mutate, expected in [
 (lambda w:w["source_snapshot_bindings"][0].__setitem__("revision",None),"BLOCK_SCHEMA_VALIDATION"),
 (lambda w:w["execution_identity"].__setitem__("execution_ref_kind","PR_MERGE_REF"),"BLOCK_EXACT_HEAD_REF_KIND_INVALID"),
 (lambda w:w["execution_identity"].__setitem__("executed_sha",BASE),"BLOCK_EXACT_HEAD_SHA_MISMATCH"),
 (lambda w:w["authority"]["ekb_execution_binding"].__setitem__("fresh_for_execution",False),"BLOCK_EKB_BINDING_NOT_FRESH"),
 (lambda w:w["execution"]["retry_policy"].__setitem__("same_failure_retries_forbidden",False),"BLOCK_SAME_FAILURE_RETRY_ALLOWED"),
]:
 w=fixture(); mutate(w); r=run(w); assert r["code"]==expected,(expected,r); cases+=1
w=fixture(); del w["objective"]; assert run(w)["code"]=="BLOCK_SCHEMA_VALIDATION"; cases+=1
w=fixture(); w["execution"]["executed_validation"]["executed_sha"]="not-a-sha"; assert run(w)["code"]=="BLOCK_SCHEMA_VALIDATION"; cases+=1
w=fixture(); w["frontier"]["safe_parallel_work"]=["S31-C"]; assert run(w)["code"]=="BLOCK_SAFE_WORK_COUNT_MISMATCH"; cases+=1
w=fixture(); w["frontier"].update({"safe_parallel_work":["S31-C","S31-D"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); w["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-C","terminal_disposition_complete":False}); assert run(w)["code"]=="BLOCK_SAFE_WORK_COUNT_MISMATCH"; cases+=1
w=fixture(); w["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-D"}); w["close_guard"].update({"can_close":False,"safe_work_remaining_count":1,"next_safe_batch":"S31-D","terminal_disposition_complete":False}); assert run(w)["code"]=="BLOCK_NEXT_SAFE_BATCH_NOT_LISTED"; cases+=1
w=fixture(); w["frontier"].update({"safe_parallel_work":["S31-C"],"remaining_safe_scope_count":1,"next_safe_batch":"S31-C"}); w["close_guard"].update({"can_close":False,"safe_work_remaining_count":0,"next_safe_batch":"S31-C","terminal_disposition_complete":False}); assert run(w)["code"]=="BLOCK_FRONTIER_CLOSE_COUNT_MISMATCH"; cases+=1
w=fixture(); w["frontier"]["blockers"]=[{"code":"WAIT_REVIEW","affected_scope":"S31-A","causal_gate":"INDEPENDENT_REVIEW","owner":"INDEPENDENT_REVIEW","independent_safe_work":[],"invalidation_condition":"REVIEW_RECEIPT"}]; assert run(w)["code"]=="BLOCKED_CAUSAL_NO_SAFE_WORK"; cases+=1
w=fixture(); w["close_guard"]["global_remaining_work_scan"]="NOT_RUN"; w["frontier"]["global_remaining_work_scan"]="NOT_RUN"; assert run(w)["code"]=="BLOCK_CLOSE_GUARD"; cases+=1

# IR-001 identity binding preserved.
w=fixture(); w["execution"]["executed_validation"]["executed_sha"]=BASE; assert run(w)["code"]=="BLOCK_VALIDATION_EXECUTED_SHA_IDENTITY_MISMATCH"; cases+=1
w=fixture(); w["resolved_evidence"]["executed_validation_receipt"]["digest"]="f"*64; assert run(w)["code"]=="BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH"; cases+=1
w=fixture(); w["authority"]["ekb_execution_binding"]["run_id"]="EKB-OTHER"; assert run(w)["code"]=="BLOCK_EKB_RECEIPT_MISMATCH"; cases+=1
w=fixture(); w["execution_identity"]["base_sha"]="a"*40; assert run(w)["code"]=="BLOCK_CURRENTNESS_RECEIPT_IDENTITY_MISMATCH"; cases+=1
w=fixture(); w["resolved_evidence"]["ekb_final_readback_receipt"]["ref"]=ref("b_validation_receipt.json"); w["resolved_evidence"]["ekb_final_readback_receipt"]["digest"]=RESOLVER.resolve(ref("b_validation_receipt.json"))["sha256"]; assert run(w)["code"]=="BLOCK_EVIDENCE_TYPE_MISMATCH"; cases+=1

# IR-002: arbitrary callbacks/maps and resolver-id aliases can never enter governed PASS.
w=fixture(); r=run(w, lambda _ref: {"evidence_type":"CURRENTNESS_RECEIPT","status":"PASS"}); assert r["code"]=="BLOCK_UNTRUSTED_RESOLVER_TYPE",r; cases+=1
class FakeResolver:
 def resolve(self,ref): return {"raw":b'{}',"sha256":"0"*64,"current":True}
w=fixture(); r=run(w, FakeResolver()); assert r["code"]=="BLOCK_UNTRUSTED_RESOLVER_TYPE",r; cases+=1
w=fixture(); w["resolved_evidence"]["currentness_receipt"]["resolver_id"]="GPT_ALIAS"; assert run(w)["code"]=="BLOCK_SCHEMA_VALIDATION"; cases+=1
w=fixture(); w["resolved_evidence"]["currentness_receipt"]["ref"]=f"github://{RESOLVER.repo}@{'a'*40}/{EVIDENCE}/b_currentness_receipt.json"; assert run(w)["code"]=="BLOCK_TRUSTED_REF_RESOLUTION_FAILED"; cases+=1

assert cases>=24,cases
print(f"PASS_LF_WORK_PACKAGE_V0_2_CANDIDATE_SELFTEST={cases}/{cases}")
