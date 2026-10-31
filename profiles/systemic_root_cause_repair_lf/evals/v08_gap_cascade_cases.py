#!/usr/bin/env python3
"""V0.8 gap-resolution cascade cases (generic).

A design-blocking gap is acceptable only when the cascade was run over every evidence class,
and a derived proposal is a distinct accepted form that is never existing authority."""
import copy
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
v05 = runpy.run_path(str(ROOT / "evals" / "v05_producer_depth_cases.py"), run_name="v08_import")
runtime_validate = v05["runtime_validate"]
to_nonready, attempt, add_manifest_evidence = v05["to_nonready"], v05["attempt"], v05["add_manifest_evidence"]
c, e = v05["c"], v05["e"]
RESULTS = []


def codes(r):
    return {x["code"] for x in r["errors"]}


def check(label, cond, detail=""):
    RESULTS.append((label, bool(cond), detail))


e5 = add_manifest_evidence(e, "EV-ATTEMPT-1")
good = to_nonready(c, [attempt()])
check("GAP_ALL_CLASSES_COVERED_WITHOUT_SEARCH_RECORD_REJECTED", "GAP_CASCADE_EXHAUSTED_NEEDS_SEARCH_RECORD" in codes(runtime_validate.validate(good, e5)))

g = copy.deepcopy(good); g["current_uncertainties"][0].pop("cascade")
check("GAP_CASCADE_RECORD_REQUIRED", "GAP_CASCADE_RECORD_REQUIRED" in codes(runtime_validate.validate(g, e5)))

g = copy.deepcopy(good); g["current_uncertainties"][0]["cascade"]["classes_without_source"] = []
check("GAP_CASCADE_MUST_COVER_ALL_CLASSES", "GAP_CASCADE_NOT_EXHAUSTED" in codes(runtime_validate.validate(g, e5)))

g = copy.deepcopy(good); g["current_uncertainties"][0]["cascade"] = {"classes_tried": [], "classes_without_source": ["DIRECT", "DECLARED", "ANALOGY", "RELATED", "HISTORY"]}
check("GAP_CASCADE_NEEDS_AT_LEAST_ONE_CLASS_TRIED", "GAP_CASCADE_NOTHING_TRIED" in codes(runtime_validate.validate(g, e5)))

g = copy.deepcopy(good); g["current_uncertainties"][0]["cascade"]["classes_without_source"].append("DIRECT")
check("GAP_CASCADE_CLASS_CANNOT_BE_BOTH", "GAP_CASCADE_NOT_EXHAUSTED" in codes(runtime_validate.validate(g, e5)))

ALL5 = ["DIRECT", "DECLARED", "ANALOGY", "RELATED", "HISTORY"]
g = copy.deepcopy(good); g["current_uncertainties"][0]["cascade"] = {"classes_tried": ALL5, "classes_without_source": []}
check("GAP_CASCADE_ALL_SEARCHED_NEEDS_SEARCH_RECORD", "GAP_CASCADE_EXHAUSTED_NEEDS_SEARCH_RECORD" in codes(runtime_validate.validate(g, e5)))

e6 = add_manifest_evidence(e, "EV-S1")
ref = c["implementation_package"]["deliverables"][0]["artifact_ref"]
inv = copy.deepcopy(c); inv["campo_nuevo_cualquiera"] = {"status": "UNRESOLVED", "missing_evidence": ["dato"]}
check("GAP_CLOSED_ANSWER_WITH_UNRESOLVED_DATUM_REJECTED", "GAP_UNRESOLVED_CANNOT_CLOSE" in codes(runtime_validate.validate(inv, e6)))

rec = [{"class": k, "source": "fuente-" + k, "evidence_id": "EV-S1", "result": "sin dato"} for k in ALL5]
ok = copy.deepcopy(inv); ok["campo_nuevo_cualquiera"].update({"search_record": rec, "repair_step_ref": ref})
r = runtime_validate.validate(ok, e6)
check("GAP_ABSENCE_WITH_SEARCH_RECORD_AND_REPAIR_STEP_ACCEPTED", r["valid"], r["errors"][:2])

nos = copy.deepcopy(ok); nos["campo_nuevo_cualquiera"]["search_record"] = [dict(x, result="NO_SOURCE_ACCESSIBLE") if x["class"] in ("ANALOGY", "HISTORY") else x for x in rec]
r = runtime_validate.validate(nos, e6)
check("GAP_NO_SOURCE_ACCESSIBLE_IS_A_SEARCH_RESULT_ACCEPTED", r["valid"], r["errors"][:2])

bad = copy.deepcopy(ok); bad["campo_nuevo_cualquiera"]["search_record"] = rec[:3]
check("GAP_SEARCH_RECORD_MUST_COVER_ALL_CLASSES", "GAP_SEARCH_RECORD_NOT_EXHAUSTIVE" in codes(runtime_validate.validate(bad, e6)))

bad = copy.deepcopy(ok); bad["campo_nuevo_cualquiera"]["repair_step_ref"] = "no-existe"
check("GAP_SEARCH_RECORD_NEEDS_REPAIR_STEP", "GAP_SEARCH_RECORD_REPAIR_STEP_REQUIRED" in codes(runtime_validate.validate(bad, e6)))

d = copy.deepcopy(c); d["otro_campo_nuevo"] = {"authority_kind": "DERIVED_PROPOSAL"}
check("GAP_DERIVED_PROPOSAL_NEEDS_RECORD_ANYWHERE", "GAP_DERIVED_PROPOSAL_RECORD_REQUIRED" in codes(runtime_validate.validate(d, e6)))

d["otro_campo_nuevo"]["derivation"] = {"criterion": "c", "confidence": 0.6, "alternatives": ["a"], "attempts": [{"evidence_id": "EV-S1"}], "ratification_ref": ref}
r = runtime_validate.validate(d, e6)
check("GAP_DERIVED_PROPOSAL_WITH_RECORD_ACCEPTED_ANYWHERE", r["valid"], r["errors"][:2])

failed = [x for x in RESULTS if not x[1]]
for label, ok, detail in RESULTS:
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else f"  {detail}"))
if failed:
    sys.exit(1)
print(f"GAP_CASCADE_CASES={len(RESULTS)}/{len(RESULTS)}")
