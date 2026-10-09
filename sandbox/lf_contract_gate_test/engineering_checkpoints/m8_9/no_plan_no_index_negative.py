#!/usr/bin/env python3
"""M8.9 NO_PLAN_NO_INDEX_NEGATIVE: an IG index without a registered EXPLAIN plan (before AND after) is rejected (D-V2.1, no interim index).
Judge over IG_M8_9_INDEX_SNAPSHOT_V1 (live pg_indexes read-only snapshot + registered plans). Baseline must be clean; every defect rejected. No writes."""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

TEST_CODE = "ENG_M8_9_NO_PLAN_NO_INDEX_NEGATIVE"


def judge(s: dict) -> list[str]:
    p: list[str] = []
    asis = set(s.get("asis_indexes") or [])
    live = list(s.get("live_indexes") or [])
    plans = s.get("plans") or []
    if not asis:
        p.append("ASIS_INVENTORY_EMPTY")
    planned = {}
    for pl in plans:
        ix = pl.get("index")
        ok = all(pl.get(k) for k in ("query", "explain_before", "explain_after")) and pl.get("analyze_in_sandbox") is True
        if not ok:
            p.append("PLAN_INCOMPLETE:" + str(ix))
        else:
            planned[ix] = pl
    for ix in live:
        if ix not in asis and ix not in planned:
            p.append("INDEX_WITHOUT_PLAN:" + ix)
    for ix in planned:
        if ix not in live:
            p.append("PLAN_FOR_NON_EXISTENT_INDEX:" + ix)
    return p


GOOD_PLAN = {"index": "idx_new", "query": "select 1", "explain_before": {"Plan": "Seq Scan"}, "explain_after": {"Plan": "Index Scan"}, "analyze_in_sandbox": True}


def mutations(s: dict):
    def m(name, fn):
        c = copy.deepcopy(s); fn(c); return name, c
    yield m("NEW_INDEX_NO_PLAN", lambda c: c["live_indexes"].append("idx_new"))
    yield m("PLAN_MISSING_BEFORE", lambda c: (c["live_indexes"].append("idx_new"), c["plans"].append({**GOOD_PLAN, "explain_before": None})))
    yield m("PLAN_MISSING_AFTER", lambda c: (c["live_indexes"].append("idx_new"), c["plans"].append({**GOOD_PLAN, "explain_after": None})))
    yield m("PLAN_NOT_ANALYZED_IN_SANDBOX", lambda c: (c["live_indexes"].append("idx_new"), c["plans"].append({**GOOD_PLAN, "analyze_in_sandbox": False})))
    yield m("PLAN_FOR_OTHER_INDEX", lambda c: (c["live_indexes"].append("idx_new"), c["plans"].append({**GOOD_PLAN, "index": "idx_other"})))
    yield m("EMPTY_ASIS", lambda c: c.update(asis_indexes=[]))


def run(s: dict) -> dict:
    base = judge(s)
    res = []
    for name, c in mutations(s):
        pr = judge(c)
        res.append({"mutation": name, "detected": bool(pr), "problems": pr[:2]})
    # positive control: a fully planned index must be accepted
    c = copy.deepcopy(s); c["live_indexes"].append("idx_new"); c["plans"].append(GOOD_PLAN)
    positive_ok = not judge(c)
    ok = not base and all(r["detected"] for r in res) and positive_ok
    return {
        "test_code": TEST_CODE, "problems": base, "positive_control_accepted": positive_ok,
        "mutations_total": len(res), "mutations_detected": sum(r["detected"] for r in res), "mutations": res,
        "observed": {
            "test_passed": ok, "test_exit_code": 0 if ok else 1,
            "semantic_authority_bound": bool(s.get("schema") == "IG_M8_9_INDEX_SNAPSHOT_V1" and s.get("asis_indexes")),
            "adversarial_case_executed": len(res) == 6,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--input")
    a = ap.parse_args()
    raw = a.input or os.environ.get("ENGINEERING_DECLARED_INPUT_JSON")
    if not raw:
        print(json.dumps({"observed": {"test_passed": False, "test_exit_code": 2, "semantic_authority_bound": False, "adversarial_case_executed": False}, "problems": ["NO_INPUT"]})); return 2
    s = json.loads(Path(raw).read_text()) if not raw.lstrip().startswith("{") else json.loads(raw)
    out = run(s); print(json.dumps(out, indent=1, sort_keys=True)); return out["observed"]["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
