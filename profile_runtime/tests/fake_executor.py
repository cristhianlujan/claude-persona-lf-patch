#!/usr/bin/env python3
import json
import sys

payload = json.load(sys.stdin)
phase = payload.get("phase")
if phase == "PROFILE_EXECUTION":
    print(json.dumps({
        "worker": payload.get("profile", {}).get("profile_slug"),
        "activation_path": payload.get("activation_path"),
        "deliverable_created": {
            "remediation_actions": [
                {
                    "issue_id": "HARNESS-ONLY",
                    "decision": "Synthetic transport assertion only"
                }
            ]
        },
        "shell_binding": {
            "binding_state": "BOUND",
            "source_refs": ["synthetic://harness"]
        }
    }))
elif phase == "SEMANTIC_JUDGE":
    print(json.dumps({"verdict": "PASS_INDEPENDENT_SEMANTIC"}))
else:
    print(json.dumps({"error": "unknown_phase"}))
    raise SystemExit(2)
