#!/usr/bin/env python3
"""M1.9 M1_NEG_OPEN_UNIT: the M1 handoff cannot be declared while any M1 unit is open.
Judge over IG_M1_9_CLOSURE_SNAPSHOT_V1 (live read-only snapshot of the 16 M1 units + PAULO-136 dependencies).
Baseline (all closed, wired, evidenced) must be clean; every injected open-unit defect must be rejected. No writes."""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

TEST_CODE = "ENG_M1_9_NEG_OPEN_UNIT"
EXPECTED_UNITS = 16


def judge(s: dict) -> list[str]:
    p: list[str] = []
    units = s.get("units") or []
    if len(units) != EXPECTED_UNITS:
        p.append("M1_UNIT_COUNT_%d_NOT_%d" % (len(units), EXPECTED_UNITS))
    for u in units:
        c = u.get("unit")
        if u.get("status") != "DONE":
            p.append("UNIT_NOT_DONE:" + str(c))
        if u.get("cps_req_open", 1) != 0:
            p.append("REQUIRED_CHECKPOINT_OPEN:" + str(c))
        if u.get("cps_done_without_evidence", 1) != 0:
            p.append("DONE_CHECKPOINT_WITHOUT_EVIDENCE:" + str(c))
        if u.get("open_blockers", 1) != 0:
            p.append("OPEN_BLOCKER:" + str(c))
        if not u.get("event_count"):
            p.append("NO_LF_EVENTO:" + str(c))
    wired = set(s.get("m19_deps") or [])
    for u in units:
        if u.get("work_item") not in wired:
            p.append("DEPENDENCY_NOT_WIRED:" + str(u.get("unit")))
    return p


def mutations(s: dict):
    def m(name, fn):
        c = copy.deepcopy(s); fn(c); return name, c
    yield m("UNIT_BACKLOG", lambda c: c["units"][3].update(status="BACKLOG"))
    yield m("UNIT_IN_PROGRESS", lambda c: c["units"][14].update(status="IN_PROGRESS"))
    yield m("REQUIRED_CHECKPOINT_OPEN", lambda c: c["units"][0].update(cps_req_open=1))
    yield m("DONE_WITHOUT_EVIDENCE", lambda c: c["units"][7].update(cps_done_without_evidence=1))
    yield m("OPEN_BLOCKER", lambda c: c["units"][10].update(open_blockers=1))
    yield m("NO_EVENT", lambda c: c["units"][11].update(event_count=0))
    yield m("DEPENDENCY_DROPPED", lambda c: c["m19_deps"].remove(194))
    yield m("UNIT_MISSING_FROM_SCOPE", lambda c: c["units"].pop())
    yield m("EMPTY_SCOPE", lambda c: c.update(units=[], m19_deps=[]))


def run(s: dict) -> dict:
    base = judge(s)
    res = []
    for name, c in mutations(s):
        pr = judge(c)
        res.append({"mutation": name, "detected": bool(pr), "problems": pr[:2]})
    ok = not base and all(r["detected"] for r in res)
    return {
        "test_code": TEST_CODE, "problems": base,
        "mutations_total": len(res), "mutations_detected": sum(r["detected"] for r in res), "mutations": res,
        "limits": s.get("limits"),
        "observed": {
            "test_passed": ok, "test_exit_code": 0 if ok else 1,
            "semantic_authority_bound": bool(s.get("schema") == "IG_M1_9_CLOSURE_SNAPSHOT_V1" and s.get("m19_deps")),
            "adversarial_case_executed": len(res) == 9,
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
