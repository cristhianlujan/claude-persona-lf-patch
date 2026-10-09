#!/usr/bin/env python3
"""M8.5 negative acceptance: a resolver that is not needed is never executed.

Authority: a canonical Supabase snapshot of one Curator materialization (47 families) taken with a
counting wrapper on the family semantic resolver, comparing the live JIT trigger against the same
trigger forced to the previous "invoke always" behaviour. The acquisition transaction is rolled back.
Mutations affect Python copies ONLY. No database writes.

Judge: for every family the resolver call count must drop by exactly one when the family is
NOT_REQUIRED or CONDITIONAL with COMPLETE deterministic coverage, and must be unchanged (with
byte-identical semantic_plan) otherwise. REQUIRED is never skipped. A missing resolver must fail closed.
"""
from __future__ import annotations
import argparse
import copy
import json
import sys
from pathlib import Path

TEST_CODE = "ENG_M8_5_NEGATIVE_SKIPPED"
SKIP_REASON = {"NOT_REQUIRED": "JIT_NOT_REQUIRED", "CONDITIONAL": "JIT_CONDITIONAL_COVERAGE_COMPLETE"}


def must_skip(f: dict) -> bool:
    if f.get("eligibility") == "NOT_REQUIRED":
        return True
    return f.get("eligibility") == "CONDITIONAL" and f.get("coverage_status") == "COMPLETE"


def jit_gate(authority: dict) -> bool:
    """Independent judge of the JIT activation contract over the snapshot."""
    if authority.get("source") != "SUPABASE_LIVE_CANONICAL_ROLLED_BACK":
        return False
    mr = authority.get("missing_resolver") or {}
    if mr.get("silent") is not False or not mr.get("sqlstate") or not mr.get("error"):
        return False
    fams = authority.get("families")
    if not isinstance(fams, list) or len(fams) != 47:
        return False
    if len({f.get("family_code") for f in fams}) != 47:
        return False
    classes = set()
    for f in fams:
        el, cov, app = f.get("eligibility"), f.get("coverage_status"), f.get("applicability")
        old, new = f.get("calls_old_forced"), f.get("calls_new_jit")
        if not isinstance(old, int) or not isinstance(new, int) or old < 1:
            return False
        if app == "NOT_APPLICABLE" and el != "NOT_REQUIRED":
            return False
        if el == "REQUIRED" and f.get("jit_reason") is not None:
            return False
        if must_skip(f):
            if f.get("jit_reason") != SKIP_REASON[el] or new != old - 1:
                return False
            if f.get("execution_state") not in ("NOT_REQUIRED", "DONE"):
                return False
            classes.add("SKIPPED_" + el)
        else:
            if f.get("jit_reason") is not None or new != old:
                return False
            if f.get("invoked_semantic_plan_identical") is not True:
                return False
            classes.add("INVOKED_" + el)
    needed = {"SKIPPED_NOT_REQUIRED", "SKIPPED_CONDITIONAL", "INVOKED_REQUIRED", "INVOKED_CONDITIONAL"}
    if not needed <= classes:
        return False
    skipped = sum(1 for f in fams if must_skip(f))
    return sum(f["calls_old_forced"] for f in fams) - sum(f["calls_new_jit"] for f in fams) == skipped > 0


def pick(fams, pred):
    for i, f in enumerate(fams):
        if pred(f):
            return i
    raise AssertionError("SNAPSHOT_LACKS_CASE_CLASS")


def negative_campaign(authority: dict) -> dict:
    if not jit_gate(authority):
        raise AssertionError("POSITIVE_LIVE_SNAPSHOT_NOT_ACCEPTED")
    cases: dict[str, dict] = {}
    fams = authority["families"]
    i_skip = pick(fams, lambda f: f["eligibility"] == "NOT_REQUIRED")
    i_cond_skip = pick(fams, lambda f: f["eligibility"] == "CONDITIONAL" and f["coverage_status"] == "COMPLETE")
    i_req = pick(fams, lambda f: f["eligibility"] == "REQUIRED")
    i_cond_inv = pick(fams, lambda f: f["eligibility"] == "CONDITIONAL" and f["coverage_status"] != "COMPLETE")

    def case(name, mutate):
        c = copy.deepcopy(authority)
        mutate(c)
        cases[name] = c

    case("not_required_resolver_still_called", lambda c: c["families"][i_skip].__setitem__("calls_new_jit", c["families"][i_skip]["calls_old_forced"]))
    case("conditional_complete_resolver_still_called", lambda c: c["families"][i_cond_skip].__setitem__("calls_new_jit", c["families"][i_cond_skip]["calls_old_forced"]))
    case("required_family_skipped", lambda c: c["families"][i_req].update(jit_reason="JIT_NOT_REQUIRED", calls_new_jit=c["families"][i_req]["calls_old_forced"] - 1))
    case("conditional_gap_family_skipped", lambda c: c["families"][i_cond_inv].update(jit_reason="JIT_CONDITIONAL_COVERAGE_COMPLETE", calls_new_jit=c["families"][i_cond_inv]["calls_old_forced"] - 1))
    case("invoked_family_extra_call", lambda c: c["families"][i_req].__setitem__("calls_new_jit", c["families"][i_req]["calls_old_forced"] + 1))
    case("invoked_family_evidence_changed", lambda c: c["families"][i_req].__setitem__("invoked_semantic_plan_identical", False))
    case("wrong_skip_reason", lambda c: c["families"][i_skip].__setitem__("jit_reason", "JIT_CONDITIONAL_COVERAGE_COMPLETE"))
    case("missing_resolver_silent", lambda c: c["missing_resolver"].__setitem__("silent", True))
    case("missing_resolver_no_error", lambda c: c["missing_resolver"].update(error="", sqlstate=""))
    case("family_dropped_46", lambda c: c["families"].pop())
    case("family_duplicated", lambda c: c["families"].__setitem__(-1, copy.deepcopy(c["families"][0])))
    case("not_applicable_marked_required", lambda c: c["families"][i_skip].__setitem__("eligibility", "REQUIRED"))
    case("forged_source", lambda c: c.__setitem__("source", "FIXTURE"))

    controls = {"baseline_live_snapshot": True}
    for name, cand in cases.items():
        if jit_gate(cand):
            raise AssertionError(f"NEGATIVE_NOT_DETECTED:{name}")
        controls[name] = True
    fams = authority["families"]
    skipped = [f["family_code"] for f in fams if must_skip(f)]
    return {
        "status": "PASS", "test_code": TEST_CODE, "test_passed": True, "test_exit_code": 0,
        "semantic_authority_bound": True,
        "semantic_authority_scope": "CANONICAL_PLAN_EXIT_CRITERION:0 resolvers ejecutados sin necesidad",
        "adversarial_case_executed": True,
        "pantalla_id": authority.get("pantalla_id"), "run_new": authority.get("run_new"), "run_old_forced": authority.get("run_old_forced"),
        "families": len(fams), "skipped_families": len(skipped),
        "resolver_calls_old": sum(f["calls_old_forced"] for f in fams),
        "resolver_calls_new": sum(f["calls_new_jit"] for f in fams),
        "negative_cases_detected": len(cases), "tests_passed": len(controls), "tests_total": len(controls),
        "controls": controls,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority-json", type=Path, required=True)
    args = parser.parse_args()
    authority = json.loads(args.authority_json.read_text(encoding="utf-8"))
    print(json.dumps(negative_campaign(authority), sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, ValueError, TypeError, IndexError) as error:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE, "test_passed": False, "test_exit_code": 1, "error": str(error)}))
        sys.exit(1)
