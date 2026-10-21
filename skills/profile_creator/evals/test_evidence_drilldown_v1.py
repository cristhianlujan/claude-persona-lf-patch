#!/usr/bin/env python3
"""Deterministic positive/negative drills; isolated, no DB or runtime calls."""
import importlib.util
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "validators" / "evidence_drilldown_v1.py"
spec = importlib.util.spec_from_file_location("drilldown", SRC)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def probe(i):
    return {"probe_id": i, "source_ref": f"source://{i}", "discriminator": "Test competing claims", "read_only": True}


def obs(i, outcome):
    return {"probe_id": i, "outcome": outcome, "evidence_ref": f"receipt://{i}", "temporal_scope": "CURRENT"}


def payload(steps, phase="DIAGNOSIS"):
    return {"phase": phase, "material_limits": [
        {"limit_id": "L1", "material": True, "probe_queue": [probe("Q1"), probe("Q2"), probe("Q3")], "observations": steps}
    ]}


initial = mod.evaluate(payload([]))
assert initial["new_probes"][0]["depth"] == 1
assert initial["next_gate"] == "TARGETED_READ_ONLY_PROBE"
second = mod.evaluate(payload([obs("Q1", "NEW_MATERIAL_UNKNOWN")]))
assert [x["probe_id"] for x in second["new_probes"]] == ["Q2"]
resolved = mod.evaluate(payload([obs("Q1", "RESOLVED")]))
assert not resolved["new_probes"] and resolved["limits"][0]["status"] == "STOP_RESOLVED"
no_gain = mod.evaluate(payload([obs("Q1", "NO_NEW_EVIDENCE")]))
assert not no_gain["new_probes"] and "MATERIAL_UNKNOWN_REMAINS:L1" in no_gain["blocking_codes"]
ceiling = mod.evaluate(payload([obs("Q1", "NEW_MATERIAL_UNKNOWN"), obs("Q2", "NEW_MATERIAL_UNKNOWN"), obs("Q3", "NEW_MATERIAL_UNKNOWN")]))
assert ceiling["limits"][0]["status"] == "STOP_DEPTH_CEILING"
unsafe = payload([])
unsafe["material_limits"][0]["probe_queue"][0]["read_only"] = False
assert "MATERIAL_PROBE_NOT_SAFE:L1" in mod.evaluate(unsafe)["blocking_codes"]
missing_ref = payload([obs("Q1", "RESOLVED")])
missing_ref["material_limits"][0]["observations"][0]["evidence_ref"] = ""
assert "OBSERVATION_NOT_BOUND_TO_PROBE:L1" in mod.evaluate(missing_ref)["blocking_codes"]
repair = payload([obs("Q1", "RESOLVED")], "REPAIR")
repair["touched_material_surfaces"] = [{"subject_ref": "graph://A", "proof_ref": "receipt://graphA", "proof_kind": "CALL_SITE", "temporal_scope": "CURRENT", "verification_status": "VERIFIED"}]
assert mod.evaluate(repair)["repair_selection_admissible"] is True
repair["touched_material_surfaces"][0]["verification_status"] = "UNVERIFIED"
assert mod.evaluate(repair)["repair_selection_admissible"] is False
assert "REPAIR_TOUCH_UNVERIFIED:graph://A" in mod.evaluate(repair)["blocking_codes"]
repair = payload([], "REPAIR")
repair["touched_material_surfaces"] = [{"subject_ref": "graph://A", "proof_ref": "receipt://graphA", "proof_kind": "CALL_SITE", "temporal_scope": "CURRENT", "verification_status": "VERIFIED"}]
assert mod.evaluate(repair)["repair_selection_admissible"] is False
assert "REPAIR_NEEDS_MORE_EVIDENCE" in mod.evaluate(repair)["blocking_codes"]
nonmaterial = {"phase":"DIAGNOSIS","material_limits":[{"limit_id":"N1","material":False}]}
assert "NONMATERIALITY_UNPROVEN:N1" in mod.evaluate(nonmaterial)["blocking_codes"]
nonmaterial["material_limits"][0]["nonmateriality_evidence_ref"] = "receipt://n1"
assert not mod.evaluate(nonmaterial)["blocking_codes"]
print("evidence drilldown v1: 12/12 deterministic checks succeeded")
