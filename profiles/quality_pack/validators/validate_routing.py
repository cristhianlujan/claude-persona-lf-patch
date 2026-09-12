#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ROUTES = {
    "PASS_TO_COMPOSER": ("CONTINUE", "COMPOSER"),
    "PASS_WITH_RESTRICTIONS": ("CONTINUE_WITH_RESTRICTIONS", "COMPOSER"),
    "RETURN_TO_WORKER_FOR_SELF_REPAIR": ("RETURN_TO_ORCHESTRATOR", "PRODUCER_REPAIR"),
    "RETURN_TO_ORCHESTRATOR": ("RETURN_TO_ORCHESTRATOR", "AUTHORITY_OR_CONTEXT_RESOLUTION"),
    "BLOCK_PIPELINE": ("BLOCK_PIPELINE", "NONE"),
}


def validate_routing(verdict, routing):
    errors = []
    if verdict not in ROUTES:
        return ["VERDICT_UNSUPPORTED"]
    if not isinstance(routing, dict):
        return ["ROUTING_OBJECT_REQUIRED"]
    if "target_profile" in routing:
        errors.append("DIRECT_TARGET_PROFILE_FORBIDDEN")
    if routing.get("activation_path") not in {"DIRECT", "ROUTER"}:
        errors.append("ACTIVATION_PATH_INVALID")
    if routing.get("via") != "ORCHESTRATOR":
        errors.append("ROUTING_MUST_RETURN_THROUGH_ORCHESTRATOR")
    expected_action, expected_target = ROUTES[verdict]
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
    errors = validate_routing(payload.get("verdict"), payload.get("routing"))
    print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
