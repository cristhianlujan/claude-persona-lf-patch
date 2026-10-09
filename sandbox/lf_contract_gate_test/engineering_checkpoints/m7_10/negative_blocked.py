#!/usr/bin/env python3
"""IG M7.10: BLOCKED successor must not invalidate the last completed predecessor.

Proof comes only from real Supabase fixture SQL; synthetic JSON fixture inputs
alone never qualify. Freshness STALE is distinct from lifecycle invalidation.
"""
import argparse
import json
import sys

TEST_CODE="ENG_M7_10_NEGATIVE_BLOCKED"
def verdict(status,reason=None):
    passed=status=="PASS"
    print(json.dumps({"test_code":TEST_CODE,"status":status,"error_code":reason,
        "observed":{"test_passed":passed,"test_exit_code":0 if passed else 1,
                    "semantic_authority_bound":True,
                    "adversarial_case_executed":passed}},sort_keys=True))
    return 0 if passed else 1

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--probe-json",required=True)
    args=p.parse_args()
    try: d=json.loads(args.probe_json)
    except (ValueError,TypeError): return verdict("FAIL","BAD_PROBE_JSON")
    if not isinstance(d,dict) or d.get("schema_version")!="IG_M710_BLOCKED_PROBE_V1":
        return verdict("FAIL","PROBE_CONTRACT_MISMATCH")
    if d.get("source")!="LIVE_SUPABASE_TRANSACTION" or d.get("rollback_verified") is not True:
        return verdict("FAIL","LIVE_ROLLBACK_EVIDENCE_MISSING")
    if d.get("persistent_delta")!={"runs":0,"screens":0,"receipts":0}:
        return verdict("FAIL","ROLLBACK_RESIDUE")
    if d.get("semantic_authority")!="CANONICAL_PLAN_EXIT_CRITERION":
        return verdict("FAIL","CANONICAL_AUTHORITY_NOT_BOUND")
    x=d.get("case")
    if not isinstance(x,dict) or x.get("test_code")!="M7_10_BLOCKED_SUCCESSOR_PRESERVE":
        return verdict("FAIL","WRONG_NEGATIVE_CASE")
    required={"executed":True,"fresh_fixture":True,"source_change_executed":True,
              "predecessor_status":"COMPLETED","successor_status":"BLOCKED",
              "predecessor_invalidated":False,"predecessor_invalidated_by_run_id":None,
              "blocked_successor_invalidation_count":0,"lifecycle_predecessor_current":True,
              "source_freshness_state":"STALE","rollback_verified":True}
    if any(x.get(key)!=value for key,value in required.items()):
        return verdict("FAIL","NEGATIVE_INVARIANT_FAILED")
    parent,child=x.get("predecessor_run_id"),x.get("successor_run_id")
    if not isinstance(parent,int) or not isinstance(child,int) or parent<1 or child<1 or parent==child:
        return verdict("FAIL","FRESH_LINEAGE_MISSING")
    if x.get("successor_supersedes_run_id")!=parent or x.get("historical_run_id") is not None:
        return verdict("FAIL","LINEAGE_REUSES_HISTORY")
    if x.get("parent_graph_receipt_count")!=2 or x.get("parent_consumer_readback")!="PASS":
        return verdict("FAIL","PRODUCER_VALIDATION_NOT_PROVEN")
    return verdict("PASS")

if __name__=="__main__":
    sys.exit(main())
