#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

from evaluate_s26_learning_preflight import evaluate_learning_preflight
from evaluate_s26_profile_baseline import evaluate


def build_plan(repo: Path, slug: str, preflight_payload: object, *, current_revision: str | None = None) -> dict[str, object]:
    baseline = evaluate(repo, slug)
    learning = evaluate_learning_preflight(preflight_payload, slug, repo_root=repo, current_revision=current_revision)
    preflight_pass = learning["status"] == "PASS"
    decision = baseline["decision"] if preflight_pass else "BLOCKED_LEARNING_PREFLIGHT"
    write_allowed = decision == "UPDATE_REQUIRED" and preflight_pass and not baseline["blocking_codes"]
    return {
        "schema": "S26_PROFILE_UPDATE_PLAN_V2",
        "operation_code": "ACTUALIZACION_PERFIL_LF",
        "profile_slug": slug,
        "baseline_evaluation": baseline,
        "learning_preflight": learning,
        "decision": decision,
        "ordered_actions": baseline["repair_actions"] if write_allowed else [],
        "write_allowed": write_allowed,
        "authority_resolution_required": baseline["decision"] == "BLOCKED_AUTHORITY_REQUIRED",
        "learning_preflight_required": True,
        "closure_requirement": "POST_WRITE_BASELINE_10_OF_10_PLUS_FRESH_LEARNING_PREFLIGHT_PLUS_EXISTING_OPERATION_GATES",
        "automatic_runtime_activation": False,
        "automatic_production_activation": False,
    }


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("usage: plan_s26_profile_update.py <profile_slug> <preflight_json> [repo_root]", file=sys.stderr)
        return 2
    slug = sys.argv[1]
    preflight_path = Path(sys.argv[2]).resolve()
    repo = Path(sys.argv[3]).resolve() if len(sys.argv) == 4 else Path(__file__).resolve().parents[3]
    try:
        preflight_payload = json.loads(preflight_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        preflight_payload = None
    plan = build_plan(repo, slug, preflight_payload)
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 0 if plan["decision"] in {"NO_UPDATE_REQUIRED", "UPDATE_REQUIRED"} else 3


if __name__ == "__main__":
    raise SystemExit(main())
