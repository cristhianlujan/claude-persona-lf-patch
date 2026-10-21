#!/usr/bin/env python3
"""Read-only, bounded evidence drilldown plan for profile creation/evolution.

This planner validates supplied evidence references; it does not execute probes,
validate remote attestations, or authorize any source write / runtime transition.
"""
from __future__ import annotations
import json
import sys
from typing import Any

OUTCOMES = {"RESOLVED", "REFUTED", "NEW_MATERIAL_UNKNOWN", "NO_NEW_EVIDENCE"}
PHASES = {"DIAGNOSIS", "REPAIR"}
MAX_DEPTH = 3


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict) or payload.get("phase") not in PHASES:
        raise ValueError("INVALID_PHASE_OR_PAYLOAD")
    limits = payload.get("material_limits")
    if not isinstance(limits, list):
        raise ValueError("MATERIAL_LIMITS_REQUIRED")
    phase = payload["phase"]
    output: dict[str, Any] = {
        "contract": "LF_TARGETED_EVIDENCE_DRILLDOWN_V1",
        "phase": phase,
        "read_only": True,
        "automatic_execution_allowed": False,
        "diagnostic_depth_ceiling": MAX_DEPTH,
        "limits": [],
        "new_probes": [],
        "repair_selection_admissible": False,
        "blocking_codes": [],
    }
    seen_ids: set[str] = set()
    for item in limits:
        if not isinstance(item, dict) or not _nonempty(item.get("limit_id")):
            raise ValueError("LIMIT_ID_REQUIRED")
        ident = item["limit_id"]
        if ident in seen_ids:
            raise ValueError("DUPLICATE_LIMIT_ID")
        seen_ids.add(ident)
        if item.get("material") is not True:
            if not _nonempty(item.get("nonmateriality_evidence_ref")):
                output["blocking_codes"].append(f"NONMATERIALITY_UNPROVEN:{ident}")
                output["limits"].append({"limit_id": ident, "status": "BLOCKED_UNPROVEN_NONMATERIALITY", "steps": 0})
            else:
                output["limits"].append({"limit_id": ident, "status": "NOT_MATERIAL_WITH_EVIDENCE", "steps": 0})
            continue
        steps = item.get("observations", [])
        probes = item.get("probe_queue", [])
        if not isinstance(steps, list) or not isinstance(probes, list):
            raise ValueError("INVALID_PROBE_QUEUE_OR_OBSERVATIONS")
        if len(steps) > MAX_DEPTH:
            output["blocking_codes"].append(f"DEPTH_CEILING_EXCEEDED:{ident}")
            output["limits"].append({"limit_id": ident, "status": "STOP_DEPTH_CEILING", "steps": len(steps)})
            continue
        observation_invalid = False
        for index, step in enumerate(steps):
            if (not isinstance(step, dict) or index >= len(probes) or not isinstance(probes[index], dict) or
                step.get("probe_id") != probes[index].get("probe_id") or
                step.get("outcome") not in OUTCOMES or
                not _nonempty(step.get("evidence_ref")) or
                step.get("temporal_scope") not in {"P0_HISTORICAL", "CURRENT", "UNKNOWN_ASOF"}):
                observation_invalid = True
                break
        if observation_invalid:
            output["blocking_codes"].append(f"OBSERVATION_NOT_BOUND_TO_PROBE:{ident}")
            output["limits"].append({"limit_id": ident, "status": "BLOCKED_UNBOUND_EVIDENCE", "steps": len(steps)})
            continue
        if steps and steps[-1]["outcome"] in {"RESOLVED", "REFUTED"}:
            status = "STOP_RESOLVED"
        elif steps and steps[-1]["outcome"] == "NO_NEW_EVIDENCE":
            status = "STOP_NO_GAIN"
            output["blocking_codes"].append(f"MATERIAL_UNKNOWN_REMAINS:{ident}")
        elif len(steps) == MAX_DEPTH:
            status = "STOP_DEPTH_CEILING"
            output["blocking_codes"].append(f"MATERIAL_UNKNOWN_REMAINS:{ident}")
        elif len(steps) >= len(probes):
            status = "STOP_PROBE_UNAVAILABLE"
            output["blocking_codes"].append(f"MATERIAL_PROBE_UNAVAILABLE:{ident}")
        else:
            probe = probes[len(steps)]
            if (not isinstance(probe, dict) or not _nonempty(probe.get("probe_id")) or
                not _nonempty(probe.get("source_ref")) or
                not _nonempty(probe.get("discriminator")) or probe.get("read_only") is not True):
                status = "STOP_UNSAFE_OR_UNBOUND_PROBE"
                output["blocking_codes"].append(f"MATERIAL_PROBE_NOT_SAFE:{ident}")
            else:
                status = "PROBE_REQUIRED"
                output["new_probes"].append({
                    "limit_id": ident, "depth": len(steps) + 1,
                    "probe_id": probe["probe_id"], "source_ref": probe["source_ref"],
                    "discriminator": probe["discriminator"], "read_only": True,
                })
        output["limits"].append({"limit_id": ident, "status": status, "steps": len(steps)})
    if phase == "REPAIR":
        checks = payload.get("touched_material_surfaces")
        if not isinstance(checks, list) or not checks:
            output["blocking_codes"].append("REPAIR_TOUCH_VERIFICATIONS_MISSING")
        else:
            for check in checks:
                if (not isinstance(check, dict) or
                    not _nonempty(check.get("subject_ref")) or
                    not _nonempty(check.get("proof_ref")) or
                    not _nonempty(check.get("proof_kind")) or
                    check.get("verification_status") != "VERIFIED" or
                    check.get("temporal_scope") not in {"P0_HISTORICAL", "CURRENT"}):
                    ident = check.get("subject_ref", "UNKNOWN") if isinstance(check, dict) else "UNKNOWN"
                    output["blocking_codes"].append(f"REPAIR_TOUCH_UNVERIFIED:{ident}")
        if output["new_probes"]:
            output["blocking_codes"].append("REPAIR_NEEDS_MORE_EVIDENCE")
        output["repair_selection_admissible"] = not output["blocking_codes"]
    output["blocking_codes"] = list(dict.fromkeys(output["blocking_codes"]))
    output["next_gate"] = ("TARGETED_READ_ONLY_PROBE" if output["new_probes"] else
                           "REPAIR_CANDIDATE_DESIGN_ONLY" if output["repair_selection_admissible"] else
                           "STOP_OR_READBACK")
    return output


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: evidence_drilldown_v1.py <json-payload-path>")
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    print(json.dumps(evaluate(data), indent=2, ensure_ascii=False))
