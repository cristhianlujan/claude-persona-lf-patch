#!/usr/bin/env python3
"""M9.3 adversarial sandbox guard + independent three-table rollback readback.

Only real SQL evidence qualifies the material checkpoint. Self-test fixtures
validate this verifier but can never be used as live admission receipts.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

PROJECT = "mhwmirqcgxxukpctffuv"
CODE = "ENG_M9_3_ZERO_AUTH_WRITES_NEGATIVE"
HASH_FIELDS = ("runs_sha", "assessments_sha", "proposals_sha")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def inspect(e):
    issues = []
    def need(ok, code):
        if not ok:
            issues.append(code)
    need(e.get("project_id") == PROJECT, "WRONG_PROJECT")
    need(e.get("runtime_mode") == "SANDBOX_SQL_ROLLBACK", "NOT_ROLLBACK_SANDBOX")
    need(e.get("sql_executed") is True, "NO_MATERIAL_SQL_PROOF")
    need(e.get("rollback_completed") is True, "NO_ROLLBACK_PROOF")
    need(e.get("data_source") == "programacion.v_input_governance_representative_cohort_v1",
         "UNGOVERNED_SELECTION")
    need(isinstance(e.get("execution_ref"), str)
         and e.get("execution_ref", "").startswith("supabase://"),
         "NO_DATABASE_PROVENANCE")
    trial, external = e.get("trial") or {}, e.get("external") or {}
    negative = trial.get("negative") or {}
    need(negative.get("blocked") is True
         and negative.get("error_code") == "P0001"
         and negative.get("error_message") == "TERMINAL_INPUT_READINESS_RUN_IMMUTABLE",
         "TERMINAL_WRITE_GUARD_NOT_PROVEN")
    sid = trial.get("selected_screen_id")
    need(type(sid) is int and sid > 0 and external.get("screen_id") == sid,
         "SCREEN_SCOPE_OR_IDENTITY_DRIFT")
    before, after = trial.get("before") or {}, trial.get("after") or {}
    need(trial.get("unchanged") is True, "IN_TRANSACTION_CHANGED")
    for key in HASH_FIELDS:
        a, b, c = before.get(key), after.get(key), external.get(key)
        need(isinstance(a,str) and bool(HEX64.fullmatch(a or ""))
             and a == b == c, "ROLLBACK_READBACK_MISMATCH:" + key)
    need(e.get("candidate_created_run_ids") == []
         and e.get("candidate_created_assessment_ids") == []
         and e.get("candidate_created_gap_proposal_ids") == [],
         "CANDIDATE_WRITE_CLAIM")
    return issues


def self_test():
    hash1 = "a" * 64
    sample = {"project_id":PROJECT, "runtime_mode":"SANDBOX_SQL_ROLLBACK",
              "sql_executed":True,"rollback_completed":True,
              "data_source":"programacion.v_input_governance_representative_cohort_v1",
              "execution_ref":"supabase://programacion.input_readiness_runs/terminal_guard",
              "trial":{"selected_screen_id":51,"negative":{"blocked":True,"error_code":"P0001",
                       "error_message":"TERMINAL_INPUT_READINESS_RUN_IMMUTABLE"},
                       "unchanged":True,"before":{f:hash1 for f in HASH_FIELDS},
                       "after":{f:hash1 for f in HASH_FIELDS}},
              "external":{"screen_id":51,**{f:hash1 for f in HASH_FIELDS}},
              "candidate_created_run_ids":[],"candidate_created_assessment_ids":[],
              "candidate_created_gap_proposal_ids":[]}
    assert not inspect(sample)
    mutations = [
      ("guard",{"trial":{**sample["trial"],"negative":{"blocked":False}}}),
      ("database",{"project_id":"OTHER"}),
      ("screen",{"external":{**sample["external"],"screen_id":52}}),
      ("assessment",{"external":{**sample["external"],"assessments_sha":"b"*64}}),
      ("proposal",{"trial":{**sample["trial"],"after":{**sample["trial"]["after"],"proposals_sha":"b"*64}}}),
      ("rollback",{"rollback_completed":False}),
      ("invented",{"sql_executed":False}),
      ("created_id",{"candidate_created_run_ids":[1]}),
    ]
    for name, patch in mutations:
        assert inspect({**sample,**patch}), "NEGATIVE_FALSE_PASS:" + name
    print(json.dumps({"test_code":CODE,"self_test":"PASS","negative_count":len(mutations),
                      "material_sql_executed":False}))
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--self-test",action="store_true")
    p.add_argument("--evidence-json")
    args=p.parse_args()
    if args.self_test:
        return self_test()
    if not args.evidence_json:
        p.error("--evidence-json required for live verification")
    try:
        e=json.loads(Path(args.evidence_json).read_text(encoding="utf-8"))
        issues=inspect(e) if isinstance(e,dict) else ["INVALID_EVIDENCE"]
        sha=hashlib.sha256(json.dumps(e,sort_keys=True,separators=(",",":")).encode()).hexdigest()
    except (OSError,ValueError,TypeError):
        issues=["EVIDENCE_UNREADABLE"]
        sha=None
    passed=not issues
    print(json.dumps({"test_code":CODE,"status":"PASS" if passed else "BLOCKED",
                      "test_passed":passed,"test_exit_code":0 if passed else 1,
                      "semantic_authority_bound":passed,"adversarial_case_executed":passed,
                      "evidence_sha256":sha,"issues":issues},sort_keys=True))
    return 0 if passed else 1


if __name__=="__main__":
    sys.exit(main())
