#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from context_budget_gate_v1 import build_task_view, canonical_bytes, evaluate_context_budget
from story_implementation_authority_checks_v1 import validate_authority
from validate_story_implementation_package_v1 import validate_package

HERE = Path(__file__).resolve().parent
PACKAGE = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"
AUTHORITY = HERE / "fixtures" / "onb_004_authority_snapshot_20261002.json"
SOURCE_PACK_SHA = "e24475612abd6b4011339621a9c8628005ef2f1c4111711d06ac03dd0b18a472"


def main() -> int:
    pkg = json.loads(PACKAGE.read_text(encoding="utf-8"))
    authority = json.loads(AUTHORITY.read_text(encoding="utf-8"))
    errors = validate_package(pkg)
    errors.extend(validate_authority(pkg, authority))

    if pkg.get("canonical_story_sha256") != SOURCE_PACK_SHA:
        errors.append("SOURCE_PACK_SHA_MISMATCH:canonical_story_sha256")
    if pkg.get("story_identity", {}).get("source_snapshot_sha256") != SOURCE_PACK_SHA:
        errors.append("SOURCE_PACK_SHA_MISMATCH:source_snapshot_sha256")

    closure = pkg.get("decision_closure", {})
    if closure.get("ready") is not False:
        errors.append("SOURCE_CONFLICT_FALSE_READY")
    blocker_codes = {item.get("code") for item in pkg.get("blocked_if", [])}
    required_blockers = {
        "ONB004_EMAIL_REQUIREMENT_CONFLICT",
        "ONB004_LEGAL_ROUTES_PENDING",
        "PROGRAMMING_TARGET_SCOPE_UNRESOLVED",
    }
    for blocker in sorted(required_blockers - blocker_codes):
        errors.append(f"REQUIRED_BLOCKER_MISSING:{blocker}")

    task_view = pkg["task_views"][0]
    computed_view_sha = hashlib.sha256(canonical_bytes(build_task_view(pkg, task_view))).hexdigest()
    if task_view.get("view_sha256") != computed_view_sha:
        errors.append("TASK_VIEW_SHA_MISMATCH")
    budget = evaluate_context_budget(pkg, task_view)
    if budget["result"] != "PASS":
        errors.append("COMPILED_PACKAGE_CONTEXT_BUDGET_BLOCKED")

    out = {
        "schema":"SC_M4_1_ONB_004_COMPILED_PACKAGE_READBACK_V1",
        "result":"PASS" if not errors else "FAIL",
        "errors":errors,
        "source_pack_sha256":SOURCE_PACK_SHA,
        "task_view_sha256":computed_view_sha,
        "context_budget":budget,
        "blocker_codes":sorted(blocker_codes),
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
