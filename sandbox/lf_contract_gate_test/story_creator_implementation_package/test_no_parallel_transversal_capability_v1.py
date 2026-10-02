#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
INVENTORY = HERE / "fixtures" / "transversal_capability_inventory_20261002.json"
FORBIDDEN_PARALLEL_CODES = {
    "SOURCE_RESOLUTION_POLICY_V2",
    "CURRENTNESS_AUTHORITY_V2",
    "QUALIFICATION_FRAMEWORK_V2",
    "PROFILE_STRUCTURED_OUTPUT_BOUNDARY_V2",
    "CONSUMER_BINDINGS_V2",
    "ASSET_RETIREMENT_GOVERNANCE_V2",
    "STORY_SOURCE_RESOLUTION_ENGINE",
    "STORY_CURRENTNESS_ENGINE",
    "STORY_QUALIFICATION_ENGINE",
}
FORBIDDEN_WORK_PROTOCOL_RUNTIME = {
    "work_protocol_runtime",
    "work_protocol_orchestrator",
    "g07_controller",
    "g08_closure_controller",
    "g09_cold_replay",
    "g10_final_closure_package",
    "g11_rollout",
}


def main() -> int:
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    errors: list[str] = []

    if inv.get("schema_version") != "TRANSVERSAL_CAPABILITY_INVENTORY_SNAPSHOT_V1":
        errors.append("INVENTORY_SCHEMA_INVALID")

    assets = inv.get("assets", [])
    codes = [a.get("code") for a in assets]
    if len(codes) != len(set(codes)):
        errors.append("DUPLICATE_CANONICAL_ASSET_CODE")

    by_code = {a["code"]: a for a in assets if isinstance(a, dict) and a.get("code")}
    for need, expected_code in inv.get("protected_needs", {}).items():
        if expected_code not in by_code:
            errors.append(f"PROTECTED_CAPABILITY_MISSING:{need}:{expected_code}")

    relation_set = {
        (r.get("from"), r.get("type"), r.get("to"))
        for r in inv.get("relations", []) if isinstance(r, dict)
    }
    required_relations = {
        ("ASSET_RETIREMENT_GOVERNANCE", "DEPENDE_DE", "CURRENTNESS_AUTHORITY"),
        ("CONSUMER_BINDINGS", "DEPENDE_DE", "OWNER_RUNNER_CARRIER_AUTHORITY"),
    }
    for rel in sorted(required_relations):
        if rel not in relation_set:
            errors.append("CANONICAL_RELATION_MISSING:" + ":".join(rel))

    searchable = []
    for path in HERE.rglob("*"):
        if not path.is_file() or path == Path(__file__) or path.suffix not in {".py", ".json", ".md", ".yaml", ".yml"}:
            continue
        searchable.append(path)
        text = path.read_text(encoding="utf-8").lower()
        for code in FORBIDDEN_PARALLEL_CODES:
            if code.lower() in text:
                errors.append(f"PARALLEL_CAPABILITY_IDENTIFIER:{path.relative_to(HERE)}:{code}")
        if path.suffix != ".py":
            for token in FORBIDDEN_WORK_PROTOCOL_RUNTIME:
                if token in text:
                    errors.append(f"WORK_PROTOCOL_RUNTIME_RESIDUE:{path.relative_to(HERE)}:{token}")

    result = {
        "schema":"SC_M3_3_NO_PARALLEL_TRANSVERSAL_CAPABILITY_V1",
        "asset_count":len(assets),
        "relation_count":len(inv.get("relations", [])),
        "files_scanned":len(searchable),
        "errors":sorted(set(errors)),
    }
    result["result"] = "PASS" if not result["errors"] else "FAIL"
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
