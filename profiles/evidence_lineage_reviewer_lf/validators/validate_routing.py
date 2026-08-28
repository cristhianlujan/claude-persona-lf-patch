#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ROUTES = {
    "PASS_EVIDENCE_LINEAGE": ("CONTINUE", "QUALITY_PACK"),
    "PASS_WITH_RESTRICTIONS": ("CONTINUE_WITH_RESTRICTIONS", "QUALITY_PACK"),
    "RETURN_TO_SOURCE_FOR_READBACK": ("RETURN_TO_ORCHESTRATOR", "SOURCE_READBACK"),
    "BLOCK_PIPELINE": ("BLOCK_PIPELINE", "NONE"),
}


def routing_for_status(status, activation_path):
    if status not in ROUTES:
        raise ValueError("unsupported status")
    action, target = ROUTES[status]
    return {
        "activation_path": activation_path,
        "via": "ORCHESTRATOR",
        "pipeline_action": action,
        "resolution_target": target,
    }


def validate_routing(status, routing):
    errors = []
    if status not in ROUTES:
        return ["STATUS_UNSUPPORTED"]
    if not isinstance(routing, dict):
        return ["ROUTING_OBJECT_REQUIRED"]
    if "target_profile" in routing:
        errors.append("DIRECT_TARGET_PROFILE_FORBIDDEN")
    if routing.get("activation_path") not in {"DIRECT", "ROUTER"}:
        errors.append("ACTIVATION_PATH_INVALID")
    if routing.get("via") != "ORCHESTRATOR":
        errors.append("ROUTING_MUST_RETURN_THROUGH_ORCHESTRATOR")
    expected_action, expected_target = ROUTES[status]
    if routing.get("pipeline_action") != expected_action:
        errors.append("PIPELINE_ACTION_MISMATCH")
    if routing.get("resolution_target") != expected_target:
        errors.append("RESOLUTION_TARGET_MISMATCH")
    return sorted(set(errors))


def normalized_route(routing):
    if not isinstance(routing, dict):
        return None
    return {
        "via": routing.get("via"),
        "pipeline_action": routing.get("pipeline_action"),
        "resolution_target": routing.get("resolution_target"),
    }


def main():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    errors = validate_routing(payload.get("status"), payload.get("routing"))
    print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
