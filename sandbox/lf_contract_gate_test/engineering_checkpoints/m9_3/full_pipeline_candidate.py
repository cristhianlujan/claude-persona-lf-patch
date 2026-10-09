#!/usr/bin/env python3
"""M9.3 FULL_PIPELINE_CANDIDATE.

Fail-closed verifier for a LIVE read-only comparison of the full vNext
Core -> Semantics -> Curator -> Validator pipeline versus 5.13, across
the governed M9.4 cohorts through T-EQUIV.

The input MUST be evidence captured from actual external runtime execution,
not a fabricated local fixture. This script validates the received evidence;
it does not launch the pipeline or certify that a live run occurred by itself.
It cannot PASS without the comparison traces and authoritative DB readback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

TEST_CODE = "ENG_M9_3_FULL_PIPELINE_CANDIDATE"
PROJECT = "mhwmirqcgxxukpctffuv"
ASSETS = {
    "EDGE_FN_INPUT_GOVERNANCE_AGENT_V1",
    "EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1",
    "EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1",
}
COHORTS = {"AUTH", "FORMS", "NAVIGATION", "DESIGN", "ONBOARDING", "RECOVERY", "API"}
STAGES = ("CORE", "SEMANTICS", "CURATOR", "VALIDATOR")
HEX64 = re.compile(r"^[a-f0-9]{64}$")
HEX40 = re.compile(r"^[a-f0-9]{40}$")


def sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def valid_ref(s: object) -> bool:
    return isinstance(s, str) and bool(re.match(r"^(supabase|github|sentinelx)://[^ ]{12,}$", s))


def admissible_t_equiv(eq: dict) -> bool:
    """A D4 hold proves observation, never semantic equivalence or promotion."""
    diff = eq.get("difference_count")
    d0 = (eq.get("status") == "PASS" and eq.get("result") == "PASS_EQUIVALENT"
          and diff == 0 and eq.get("semantic_hold") is not True)
    d4 = (eq.get("status") == "CLASSIFIED_HOLD"
          and eq.get("result") == "BLOCKED_DIVERGENCE"
          and eq.get("comparison_level") == "D4"
          and type(diff) is int and diff > 0
          and eq.get("semantic_hold") is True
          and eq.get("promotion_authorized") is False)
    return d0 or d4


def self_test() -> int:
    positive = {"status":"PASS","result":"PASS_EQUIVALENT","difference_count":0}
    hold = {"status":"CLASSIFIED_HOLD","result":"BLOCKED_DIVERGENCE",
            "comparison_level":"D4","difference_count":3,
            "semantic_hold":True,"promotion_authorized":False}
    assert admissible_t_equiv(positive)
    assert admissible_t_equiv(hold)
    for x in ({**hold,"promotion_authorized":True},
              {**hold,"comparison_level":"D2"},
              {**hold,"semantic_hold":False},
              {**hold,"result":"BLOCKED_UNCLASSIFIED_DIVERGENCE"},
              {**hold,"difference_count":0},
              {**positive,"difference_count":1},
              {**positive,"status":"CLASSIFIED_HOLD"}):
        assert not admissible_t_equiv(x), "FALSE_POSITIVE_SEMANTIC_ADMISSION"
    print(json.dumps({"test_code":TEST_CODE,"self_test":"PASS",
                      "negative_case_count":7,
                      "live_pipeline_executed":False}))
    return 0


def validate(e: dict) -> list[str]:
    issues: list[str] = []

    def need(test: bool, message: str) -> None:
        if not test:
            issues.append(message)

    need(e.get("schema_version") == "IG_M9_3_FULL_PIPELINE_EVIDENCE_V1", "INVALID_SCHEMA")
    need(e.get("origin") == "SUPABASE_LIVE_RUNTIME_EVIDENCE", "NO_LIVE_ORIGIN")
    need(e.get("project_id") == PROJECT, "WRONG_DATABASE")
    need(valid_ref(e.get("capture_ref")), "MISSING_CAPTURE_PROVENANCE")
    need(isinstance(e.get("captured_at"), str) and "T" in e.get("captured_at", ""), "MISSING_CAPTURE_TIME")

    bundle = e.get("bundle") or {}
    need(bundle.get("unit_code") == "M9.0" and bundle.get("status") == "DONE", "M90_NOT_CLOSED")
    need(isinstance(bundle.get("sha256"), str) and bool(HEX64.fullmatch(bundle.get("sha256", ""))), "BUNDLE_SHA_ABSENT")
    need(valid_ref(bundle.get("readback_ref")), "BUNDLE_SOURCE_UNVERIFIED")

    edge = e.get("edge_assets") or []
    need(isinstance(edge, list) and {a.get("codigo_activo") for a in edge if isinstance(a, dict)} == ASSETS
         and len(edge) == len(ASSETS), "EDGE_ASSET_SET_INVALID")
    for a in edge:
        if isinstance(a, dict):
            need(a.get("runtime_estado") == "CANDIDATE_READ_ONLY", "NOT_READ_ONLY:" + str(a.get("codigo_activo")))
        else:
            issues.append("INVALID_EDGE_ROW")

    rows = e.get("cohorts") or []
    if not isinstance(rows, list):
        rows = []
    observed = {x.get("cohort_code") for x in rows if isinstance(x, dict)}
    need(observed == COHORTS and len(rows) == len(COHORTS), "M94_SEVEN_COHORTS_NOT_COVERED")
    for item in rows:
        if not isinstance(item, dict):
            issues.append("INVALID_COHORT_ROW")
            continue
        c = str(item.get("cohort_code"))
        need(isinstance(item.get("screen_id"), int) and item.get("screen_id", 0) > 0
             and item.get("active") is True and item.get("joinable") is True
             and valid_ref(item.get("membership_ref")), "COHORT_AUTHORITY_MISSING:" + c)
        stages = item.get("vnext_pipeline") or []
        need(isinstance(stages, list) and [s.get("stage") for s in stages if isinstance(s, dict)] == list(STAGES),
             "PIPELINE_INCOMPLETE:" + c)
        for stage in stages:
            if not isinstance(stage, dict):
                issues.append("INVALID_STAGE:" + c)
                continue
            need(stage.get("status") == "PASS" and valid_ref(stage.get("execution_ref")),
                 "STAGE_NO_LIVE_PROOF:" + c + "/" + str(stage.get("stage")))
        eq = item.get("t_equiv") or {}
        need(eq.get("capability_code") == "CONTROL_EQUIVALENCE_JUDGE"
             and eq.get("baseline") == "5.13" and eq.get("candidate") == "VNEXT"
             and admissible_t_equiv(eq)
             and valid_ref(eq.get("execution_ref")), "EQUIVALENCE_UNPROVEN:" + c)

    writes = e.get("authoritative_readback") or {}
    need(writes.get("candidate_created_run_ids") == []
         and writes.get("candidate_created_assessment_ids") == [],
         "CANDIDATE_AUTHORITATIVE_WRITE")
    for key in ("input_readiness_runs", "input_family_assessments"):
        snapshot = writes.get(key) or {}
        before, after = snapshot.get("before_sha256"), snapshot.get("after_sha256")
        need(isinstance(before, str) and bool(HEX64.fullmatch(before))
             and before == after and valid_ref(snapshot.get("readback_ref")),
             "AUTHORITATIVE_READBACK_UNPROVEN:" + key)

    need(e.get("shadow_decisional") is False, "SHADOW_DECISIONAL")
    need(e.get("production_authorized") is False, "PRODUCTION_AUTHORIZATION_CLAIM")
    need(e.get("promotion_authorized") is False, "PROMOTION_AUTHORIZATION_CLAIM")
    return issues


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--evidence-json", help="Actual live runtime and DB readback JSON")
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    if a.self_test:
        return self_test()
    if not a.evidence_json:
        p.error('--evidence-json is required outside self-test')
    try:
        evidence = json.loads(Path(a.evidence_json).read_text(encoding="utf-8"))
        if not isinstance(evidence, dict):
            raise ValueError("object required")
        issues = validate(evidence)
        fingerprint = sha(evidence)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        issues = ["EVIDENCE_NOT_READABLE:" + type(exc).__name__]
        fingerprint = None
    passed = not issues
    print(json.dumps({
        "test_code": TEST_CODE,
        "status": "PASS" if passed else "BLOCKED",
        "test_passed": passed,
        "test_exit_code": 0 if passed else 1,
        "semantic_authority_bound": passed,
        "evidence_sha256": fingerprint,
        "observed": {"failures": issues, "comparison_required": "7 M9.4 cohorts via T-EQUIV",
                     "authoritative_writes_allowed": 0},
    }, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
