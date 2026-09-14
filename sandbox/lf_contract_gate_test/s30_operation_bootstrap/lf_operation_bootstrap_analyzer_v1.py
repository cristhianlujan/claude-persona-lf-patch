#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def analyze(inventory: dict[str, Any]) -> dict[str, Any]:
    operations = inventory.get("operations") or []
    named = inventory.get("named_begin_functions") or []
    zero_groups = inventory.get("zero_step_groups") or []
    acl = inventory.get("acl_findings") or []

    structurally_ready: list[str] = []
    topology_gap: list[dict[str, Any]] = []
    for row in operations:
        code = row.get("operation_code")
        c = int(row.get("init_contracts") or 0)
        b = int(row.get("init_bindings") or 0)
        j = int(row.get("active_judges") or 0)
        if c == 1 and b == 1 and j == 1:
            structurally_ready.append(code)
        else:
            topology_gap.append({
                "operation_code": code,
                "init_contracts": c,
                "init_bindings": b,
                "active_judges": j,
                "decision": "BLOCK_BOOTSTRAP_TOPOLOGY_INCOMPLETE",
            })

    named_ops = sorted({row.get("operation_code") for row in named if row.get("operation_code")})
    ready_without_named_begin = sorted(set(structurally_ready) - set(named_ops))

    zero_total = sum(int(row.get("count") or 0) for row in zero_groups)
    zero_with_init = sum(int(row.get("count") or 0) for row in zero_groups if row.get("has_active_init") is True)
    zero_without_init = zero_total - zero_with_init

    unsafe_acl = sorted(
        row.get("function") for row in acl
        if row.get("exposure") not in ("SERVICE_ROLE_ONLY", "POSTGRES_ONLY")
    )

    return {
        "schema_version": "LF_OPERATION_BOOTSTRAP_ANALYSIS_V1",
        "status": "BOOTSTRAP_GAP_CONFIRMED" if zero_total > 0 or topology_gap else "NO_BOOTSTRAP_GAP_OBSERVED",
        "operation_count_with_active_init": len(operations),
        "named_begin_function_count": len(named_ops),
        "structurally_ready_operation_count": len(structurally_ready),
        "structurally_ready_operations": sorted(structurally_ready),
        "structurally_ready_without_named_begin": ready_without_named_begin,
        "topology_gap_operation_count": len(topology_gap),
        "topology_gaps": topology_gap,
        "zero_step_in_progress_total": zero_total,
        "zero_step_with_active_init": zero_with_init,
        "zero_step_without_active_init": zero_without_init,
        "legacy_zero_step_action": "EXECUTION_RECONCILIATION_REQUIRED_NOT_AUTO_BOOTSTRAP" if zero_total else "NONE",
        "unsafe_existing_begin_or_guard_acl_functions": unsafe_acl,
        "recommended_next": [
            "CREATE_TABLE_DRIVEN_BOOTSTRAP_POLICY",
            "CREATE_SERVICE_ROLE_ONLY_BOOTSTRAP_CORE",
            "DELEGATE_OPERATION_SPECIFIC_WRAPPERS_TO_CORE",
            "ADMIT_GENERIC_BEGIN_ONLY_AFTER_COMPLETE_INIT_TOPOLOGY_AND_POLICY",
            "KEEP_LEGACY_ZERO_STEP_REPAIR_IN_EXECUTION_RECONCILIATION_LF",
            "HARDEN_EXISTING_BEGIN_RPC_ACLS_IN_SEPARATE_SECURITY_CHANGE"
        ],
        "auto_mutation_allowed": False,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only S30 fleet analyzer for OPERATION_BOOTSTRAP_LF.")
    ap.add_argument("--inventory", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    result = analyze(json.loads(ns.inventory.read_text(encoding="utf-8")))
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
