#!/usr/bin/env python3
"""M4.12 CORRELATION_RERUN under the owner-authorized R11 novation (IG_R11_NOVATION_V1, lf_eventos 20635).

R11's original criterion (0 shared conclusion dependencies with the Curator) cannot be met while the Validator reuses the
Curator classifier. The novated criterion measures behavior instead of structure:
  FACTS_INVARIANTS       every COMPLETE family row carries source refs + curator evidence; every row carries its sha.
  LOGIC_SEVERITY         a P0/P1 applicable family with MISSING coverage is never implementation/qa/production READY.
  CORRELATION_INJECTION  the same defect injected into the snapshot (as a shared Curator/Validator reader would propagate it)
                         must be detected by the controls above; the unmutated snapshot must be clean.
The novation event must state original_criterion_met=false and validator_independent_of_curator=false; claiming either fails.
Input: IG_M4_12_BEHAVIOR_SNAPSHOT_V1 JSON (live read-only query), path via --input or ENGINEERING_DECLARED_INPUT_JSON. No writes.
"""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

TEST_CODE = "ENG_M4_12_CORRELATION_RERUN"


def judge(s: dict) -> list[str]:
    p: list[str] = []
    n = s.get("novation_event") or {}
    if not (n.get("type") == "HANDOFF_DEEP_CONTEXT" and n.get("schema_novation") == "IG_R11_NOVATION_V1" and n.get("authorized_by") == "owner"):
        p.append("NOVATION_EVENT_MISSING_OR_INVALID")
    if n.get("original_criterion_met") is not False:
        p.append("NOVATION_MUST_NOT_CLAIM_ORIGINAL_R11_MET")
    if n.get("validator_independent_of_curator") is not False:
        p.append("NOVATION_MUST_NOT_CLAIM_VALIDATOR_INDEPENDENCE")
    if not n.get("open_findings"):
        p.append("OPEN_FINDINGS_NOT_RECORDED")
    f = s.get("facts") or {}
    if not (s.get("rows", 0) > 0 and s.get("screens", 0) >= 40 and f.get("complete_rows", 0) > 0):
        p.append("FACTS_POPULATION_TOO_SMALL")
    if f.get("complete_without_evidence", 1) != 0:
        p.append("FACTS_COMPLETE_WITHOUT_EVIDENCE")
    if f.get("rows_without_sha", 1) != 0:
        p.append("FACTS_ROW_WITHOUT_SHA")
    seen = set()
    for g in s.get("logic") or []:
        seen.add(g["severity"])
        if g["severity"] in ("P0", "P1") and g["missing_downstream_ready"] != 0:
            p.append("LOGIC_SEVERITY_" + g["severity"] + "_MISSING_BUT_DOWNSTREAM_READY")
    if not {"P0", "P1"} <= seen:
        p.append("LOGIC_SEVERITY_BANDS_ABSENT")
    for r in s.get("sample") or []:
        if r["c"] == "COMPLETE" and (r["nrefs"] == 0 or not r["has_ev"]):
            p.append("ROW_COMPLETE_WITHOUT_EVIDENCE:%s/%s" % (r["p"], r["f"]))
        if r["s"] in ("P0", "P1") and r["ap"] == "APPLICABLE" and r["c"] == "MISSING" and r["downstream_ready"]:
            p.append("ROW_MISSING_BUT_DOWNSTREAM_READY:%s/%s" % (r["p"], r["f"]))
        if not r["has_sha"]:
            p.append("ROW_WITHOUT_SHA:%s/%s" % (r["p"], r["f"]))
    return p


def mutations(s: dict):
    def m(name, fn):
        c = copy.deepcopy(s); fn(c); return name, c
    yield m("NO_NOVATION_EVENT", lambda c: c.pop("novation_event"))
    yield m("CLAIMS_VALIDATOR_INDEPENDENT", lambda c: c["novation_event"].update(validator_independent_of_curator=True))
    yield m("CLAIMS_ORIGINAL_R11_MET", lambda c: c["novation_event"].update(original_criterion_met=True))
    yield m("SHARED_DEFECT_COMPLETE_WITHOUT_EVIDENCE", lambda c: c["facts"].update(complete_without_evidence=1))
    yield m("SHARED_DEFECT_ROW_WITHOUT_SHA", lambda c: c["facts"].update(rows_without_sha=3))
    yield m("SHARED_DEFECT_P1_MISSING_BUT_READY", lambda c: [g.update(missing_downstream_ready=1) for g in c["logic"] if g["severity"] == "P1"])
    yield m("SHARED_DEFECT_P0_MISSING_BUT_READY", lambda c: [g.update(missing_downstream_ready=2) for g in c["logic"] if g["severity"] == "P0"])
    yield m("VACUOUS_COMPLETE_ROW", lambda c: c["sample"][0].update(nrefs=0, has_ev=False))
    yield m("P1_ROW_MISSING_BUT_READY", lambda c: c["sample"][3].update(c="MISSING", downstream_ready=True))
    yield m("EMPTY_POPULATION", lambda c: c.update(rows=0))


def run(s: dict) -> dict:
    base = judge(s)
    results = []
    for name, c in mutations(s):
        pr = judge(c)
        results.append({"mutation": name, "detected": bool(pr), "problems": pr[:3]})
    ok_base = not base
    all_det = all(r["detected"] for r in results)
    return {
        "test_code": TEST_CODE,
        "problems": base,
        "mutations_total": len(results),
        "mutations_detected": sum(r["detected"] for r in results),
        "mutations": results,
        "open_findings": (s.get("novation_event") or {}).get("open_findings"),
        "limits": ["validator_shares_curator_classifier=true", "logic_control_uses_stored_runs_not_evidence_removal_battery"],
        "observed": {
            "test_passed": ok_base and all_det,
            "test_exit_code": 0 if ok_base and all_det else 1,
            "semantic_authority_bound": not any(x.startswith("NOVATION") for x in base) and bool(s.get("novation_event")),
            "adversarial_case_executed": len(results) == 10,
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
