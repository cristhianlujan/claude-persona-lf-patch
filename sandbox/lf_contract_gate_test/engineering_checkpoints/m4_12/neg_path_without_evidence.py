#!/usr/bin/env python3
"""M4.12 NEG_PATH_WITHOUT_EVIDENCE: a validator path without mutation/shadow/receipt/entrypoint evidence keeps AUD-045 open.

Judge: AUD-045 is CLOSED only when every ACTIVE validator path has all four evidence kinds, each backed by a DONE evidence unit.
The unmutated snapshot must close; every adversarial copy (missing evidence kind, unlisted active path, evidence unit not done,
inactive path flipped to active without evidence) must leave it OPEN. Input: IG_M4_12_PATH_EVIDENCE_SNAPSHOT_V1 (--input or
ENGINEERING_DECLARED_INPUT_JSON). Read-only.
"""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

TEST_CODE = "ENG_M4_12_NEG_PATH_WITHOUT_EVIDENCE"
KINDS = ("MUTATION", "SHADOW", "RECEIPT_FAIL", "ENTRYPOINT")


def judge(s: dict) -> dict:
    open_reasons = []
    units = s.get("evidence_units") or {}
    for k in KINDS:
        u = units.get(k) or {}
        done = str(u.get("done", ""))
        a, _, b = done.partition("/")
        if not (a and a == b):
            open_reasons.append("EVIDENCE_UNIT_NOT_DONE:" + k)
    active = [p["path"] for p in s.get("paths", []) if p.get("active")]
    if not active:
        open_reasons.append("NO_ACTIVE_PATH_OBSERVED")
    pe = s.get("path_evidence") or {}
    for p in active:
        missing = [k for k in KINDS if k not in (pe.get(p) or [])]
        if missing:
            open_reasons.append("PATH_WITHOUT_EVIDENCE:%s:%s" % (p, "+".join(missing)))
    return {"aud045": "OPEN" if open_reasons else "CLOSED", "reasons": open_reasons, "active_paths": active}


def cases(s):
    def m(name, fn):
        c = copy.deepcopy(s); fn(c); return name, c
    yield m("PATH_LOSES_MUTATION_EVIDENCE", lambda c: c["path_evidence"]["INPUT_VALIDATOR:SQL"].remove("MUTATION"))
    yield m("PATH_LOSES_SHADOW_EVIDENCE", lambda c: c["path_evidence"]["INPUT_VALIDATOR:EDGE"].remove("SHADOW"))
    yield m("PATH_LOSES_RECEIPT_FAIL_EVIDENCE", lambda c: c["path_evidence"]["INPUT_VALIDATOR:EDGE"].remove("RECEIPT_FAIL"))
    yield m("PATH_WITHOUT_ANY_EVIDENCE", lambda c: c["path_evidence"].pop("INPUT_VALIDATOR:SQL"))
    yield m("NEW_ACTIVE_PATH_UNLISTED", lambda c: c["paths"].append({"path": "INPUT_VALIDATOR:NEW", "active": True}))
    yield m("INACTIVE_PATH_BECOMES_ACTIVE", lambda c: c["paths"][2].update(active=True))
    yield m("MUTATION_UNIT_NOT_DONE", lambda c: c["evidence_units"]["MUTATION"].update(done="4/5"))
    yield m("NO_PATHS_OBSERVED", lambda c: c.update(paths=[]))


def run(s: dict) -> dict:
    base = judge(s)
    res = []
    for name, c in cases(s):
        r = judge(c)
        res.append({"case": name, "aud045": r["aud045"], "reasons": r["reasons"][:2]})
    ok = base["aud045"] == "CLOSED" and all(x["aud045"] == "OPEN" for x in res)
    return {"test_code": TEST_CODE, "baseline": base, "negative_cases": res,
            "observed": {"test_passed": ok, "test_exit_code": 0 if ok else 1,
                         "semantic_authority_bound": s.get("novation_event_id") == 20635,
                         "adversarial_case_executed": len(res) == 8}}


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--input"); a = ap.parse_args()
    raw = a.input or os.environ.get("ENGINEERING_DECLARED_INPUT_JSON")
    if not raw:
        print(json.dumps({"observed": {"test_passed": False, "test_exit_code": 2, "semantic_authority_bound": False, "adversarial_case_executed": False}})); return 2
    s = json.loads(raw) if raw.lstrip().startswith("{") else json.loads(Path(raw).read_text())
    out = run(s); print(json.dumps(out, indent=1, sort_keys=True)); return out["observed"]["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
