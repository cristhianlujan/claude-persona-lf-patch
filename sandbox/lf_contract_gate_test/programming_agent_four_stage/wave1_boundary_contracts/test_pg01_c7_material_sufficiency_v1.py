#!/usr/bin/env python3
"""PG-01_C7 synthetic material sufficiency positive and adversarial returns."""
import copy
import runpy
from pathlib import Path

from pg01_c3_scope_front_clean_v1 import CONTRACT, ROOT
from pg01_c7_material_sufficiency_v1 import MATERIAL_CLASSES, assess_pg01_c7

fixture = runpy.run_path(
    str(Path(__file__).with_name("test_analysis_pg01_snapshot_payload_v1.py"))
)["fixture"]
snapshot = fixture()
paths = [ROOT + f.removesuffix("[]")
         for f in CONTRACT["programming_context_snapshot"]["required_fields"]]
receipt = {"verdict": "ACCEPT", "validated_material_paths": paths}

def row(category, status="PRESENT"):
    base = {
        "scope_id": "S1", "category": category, "status": status,
        "canonical_ref": "analysis://A6/" + category,
        "source_ref": "analysis://A9/" + category,
        "currentness_ref": "currentness://A9/" + category,
        "evidence_ref": "evidence://A9/" + category,
    }
    if status == "PRESENT":
        base.update(resolved_value="synthetic_value_" + category,
                    currentness="CURRENT")
    else:
        base["reason"] = "not applicable in this synthetic scope, per source evidence"
    return base

rows = [row(category) for category in MATERIAL_CLASSES]
good = assess_pg01_c7(snapshot=snapshot, receipt=receipt,
                       requested_scope_ids=["S1"], obligations=rows)
assert good["status"] == "CANDIDATE_SUFFICIENT_NOT_ADMITTED", good
assert good["strategy_allowed"] is False and good["authority"] == "NONE"

# Five omissions must return MISSING to Analysis, not silently be guessed.
for category in MATERIAL_CLASSES:
    broken = copy.deepcopy(rows)
    target = next(x for x in broken if x["category"] == category)
    target.pop("resolved_value")
    result = assess_pg01_c7(snapshot=snapshot, receipt=receipt,
                             requested_scope_ids=["S1"], obligations=broken)
    assert result["status"] == "MISSING" and result["route"] == "ANALYSIS"
    assert category in result["missing_classes"] and not result["strategy_allowed"], (category, result)
    print("PG01_C7_MISSING_CATEGORY_PASS=" + category)

# A sourced and reasoned NOT_APPLICABLE item is valid, but still non-authorizing.
na = [row(category, "NOT_APPLICABLE") if category == "applicable_consents"
      else row(category) for category in MATERIAL_CLASSES]
assert assess_pg01_c7(snapshot=snapshot, receipt=receipt,
    requested_scope_ids=["S1"], obligations=na)["status"] == "CANDIDATE_SUFFICIENT_NOT_ADMITTED"

negative = []
def check(label, newrows, newreceipt=receipt, newscopes=None, newsnapshot=snapshot):
    result = assess_pg01_c7(snapshot=newsnapshot, receipt=newreceipt,
                             requested_scope_ids=["S1"] if newscopes is None else newscopes,
                             obligations=newrows)
    assert result["status"] == "MISSING" and result["route"] == "ANALYSIS", (label, result)
    assert result["authority"] == "NONE" and not result["strategy_allowed"]
    negative.append(label)

check("matrix_omission", rows[:-1])
check("matrix_duplicate", rows[:-1] + [copy.deepcopy(rows[0])])
check("unknown_category", rows[:-1] + [dict(rows[0], category="fabricated")])
check("blocked_receipt", rows, dict(receipt, verdict="BLOCK"))
check("blocked_scope", rows, newscopes=["S2"])
check("null_provenance", [dict(x, source_ref=None) if x["category"]=="message_texts"
                           else x for x in rows])
check("stale_source", [dict(x, currentness="STALE") if x["category"]=="error_codes"
                        else x for x in rows])
check("no_na_reason", [dict(x, reason="") if x["category"]=="applicable_consents"
                         else x for x in na])
check("na_with_value", [dict(x, resolved_value="invented") if x["category"]=="applicable_consents"
                         else x for x in na])
check("unknown_state", [dict(x, status="UNKNOWN") if x["category"]=="navigation_events"
                         else x for x in rows])

print("PASS_PG01_C7_MATERIAL_SUFFICIENCY positive=1 sourced_na=1 "
      "five_material_missing=5 adversarial=" + str(len(negative)) +
      " return_to_analysis=true authority=NONE pg01_runtime_verified=false")
