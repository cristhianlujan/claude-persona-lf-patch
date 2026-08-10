#!/usr/bin/env python3
"""Regression for inferred visual element wider than its confirmed semantic parent."""
from __future__ import annotations
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(ROOT))
from p0_visual_fidelity_v3 import enrich_candidate, validate_visual_fidelity
from p0_visual_parent_remediation_v3 import repair_inferred_parent_containment

CFG = {"geometry": {"parent_containment_tolerance_px": 0}}


def element(eid, etype, box, parent=None, classification="CONFIRMED", role="material"):
    return {
        "element_id": eid,
        "source_image_ref": "SYNTH-PARENT-REGRESSION",
        "parent_id": parent,
        "region": dict(zip(("x", "y", "width", "height"), box)),
        "element_type": etype,
        "visible_text": None,
        "semantic_role": role,
        "visual_state": "STATIC_VISIBLE",
        "classification": classification,
        "confidence": 0.99 if classification == "CONFIRMED" else 0.84,
        "evidence_refs": [f"synthetic://{eid}"],
        "source_observation_refs": [],
        "uncertainty_codes": [],
        "machine_resolution_status": "RESOLVED",
    }


def main() -> int:
    legacy = {
        "schema_version": "p0-consolidated-visual-reading/v1",
        "source_image_ref": "SYNTH-PARENT-REGRESSION",
        "source_sha256": "a" * 64,
        "elements": [
            element("SCR", "SCREEN", (0, 0, 100, 100), role="screen"),
            element("P", "REGION", (0, 0, 40, 100), "SCR", role="confirmed_text_region"),
            element("I", "ILLUSTRATION", (0, 10, 60, 20), "P", "INFERRED", "supporting_illustration"),
        ],
    }
    candidate = enrich_candidate(legacy, None, CFG)
    before = validate_visual_fidelity(candidate, None, CFG)
    if "PARENT_CHILD_GEOMETRY_CONFLICT:I" not in before.get("errors", []):
        print(json.dumps({"result": "FAIL", "stage": "precondition", "errors": before.get("errors", [])}))
        return 2
    repaired = repair_inferred_parent_containment(candidate, CFG)
    after = validate_visual_fidelity(candidate, None, CFG)
    inferred = next(e for e in candidate["elements"] if e["element_id"] == "I")
    trace = inferred.get("machine_remediation_trace", [])
    ok = (
        repaired == ["I"]
        and inferred.get("parent_id") == "SCR"
        and after.get("result") == "PASS_VISUAL_FIDELITY"
        and not after.get("errors")
        and any(t.get("strategy") == "INFERRED_PARENT_REASSIGNMENT" for t in trace)
    )
    print(json.dumps({
        "result": "PASS" if ok else "FAIL",
        "pre_errors": before.get("errors", []),
        "repaired": repaired,
        "final_parent": inferred.get("parent_id"),
        "trace": trace,
        "post_result": after.get("result"),
        "post_errors": after.get("errors", []),
    }, sort_keys=True))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
