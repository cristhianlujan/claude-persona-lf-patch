#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from lf_pase_control_repair_quarantine_v1 import (
    RepairQuarantineError,
    load_policy,
    project_enforcement,
    validate_policy,
)

ROOT = Path(__file__).resolve().parent
REGISTRY = ROOT / "lf_ci_control_impact_registry_v2.json"

checks = 0


def ok(condition: bool, label: str) -> None:
    global checks
    if not condition:
        raise AssertionError(label)
    checks += 1


def fails(fn, code: str) -> None:
    global checks
    try:
        fn()
    except RepairQuarantineError as exc:
        if not str(exc).startswith(code):
            raise AssertionError(f"expected {code}, got {exc}") from exc
        checks += 1
        return
    raise AssertionError(f"expected failure {code}")


registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
universe = sorted(row["control_id"] for row in registry["controls"])
policy = load_policy()

# 1: policy exactly covers the live applicability universe.
by_id = validate_policy(policy, control_universe=universe)
ok(sorted(by_id) == universe and len(universe) == 25, "live universe coverage")

required = ["LF_CONTRACT_CORE", "MIGRATION_SOURCE_PARITY", "PROFILE_RUNTIME_V3"]
not_applicable = [
    {"control_id": cid, "carrier": "LEGACY", "reason": "TEST_NOT_APPLICABLE"}
    for cid in universe
    if cid not in required
]
plan = {
    "schema_version": "lf-ci-execution-plan/v2",
    "coverage_complete": True,
    "control_universe": universe,
    "required_controls": required,
    "not_applicable_controls": not_applicable,
    "plan_sha256": "a" * 64,
}

result = project_enforcement(plan, policy)
# 2-8: temporary repair window removes applicable legacy validators from merge authority.
ok(result["blocking_controls"] == [], "no legacy blockers")
ok(result["observe_only_controls"] == required, "all applicable legacy controls observe-only")
ok(result["required_controls"] == required, "applicability preserved")
ok(result["observe_only_results_cannot_block_merge"] is True, "observe-only nonblocking")
ok(result["manual_diagnostic_execution_allowed"] is True, "diagnostics still allowed")
ok(result["no_applicability_reclassification"] is True, "no second router")
ok(result["structural_governance_fail_closed"] is True, "structural governance remains fail-closed")

# 9: deterministic projection.
ok(project_enforcement(plan, policy)["result_sha256"] == result["result_sha256"], "deterministic digest")

# 10: stale policy cannot silently cover a changed control universe.
bad = copy.deepcopy(policy)
bad["control_universe_sha256"] = "0" * 64
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_UNIVERSE_DIGEST")

# 11: missing policy state fails closed.
bad = copy.deepcopy(policy)
bad["states"] = bad["states"][:-1]
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_COVERAGE")

# 12: unknown state fails closed.
bad = copy.deepcopy(policy)
bad["states"][0]["state"] = "DISABLED"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_STATE")

# 13: active blocking cannot return without re-entry evidence.
bad = copy.deepcopy(policy)
bad["states"][0]["state"] = "ACTIVE_BLOCKING"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_EVIDENCE_MISSING")

# 14-15: a single control may return only with the full re-entry contract.
reactivated = copy.deepcopy(policy)
row = next(item for item in reactivated["states"] if item["control_id"] == "LF_CONTRACT_CORE")
row["state"] = "ACTIVE_BLOCKING"
row["reentry_evidence"] = {
    "qualification_verdict": "CANDIDATE_QUALIFIED",
    "qualification_head_sha": "b" * 40,
    "owner_runner_binding": "PASS",
    "equivalent_replay": "PASS",
    "exact_head_readback": "PASS",
}
reactivated_result = project_enforcement(plan, reactivated)
ok(reactivated_result["blocking_controls"] == ["LF_CONTRACT_CORE"], "one-control re-entry")
ok(
    reactivated_result["observe_only_controls"] == ["MIGRATION_SOURCE_PARITY", "PROFILE_RUNTIME_V3"],
    "others remain quarantined",
)

# 16: replay is mandatory for re-entry.
bad = copy.deepcopy(reactivated)
row = next(item for item in bad["states"] if item["control_id"] == "LF_CONTRACT_CORE")
row["reentry_evidence"]["equivalent_replay"] = "FAIL"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_REPLAY")

# 17: incomplete applicability coverage cannot be projected.
bad_plan = copy.deepcopy(plan)
bad_plan["coverage_complete"] = False
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_COVERAGE")

# 18: overlapping applicable/not-applicable partition fails closed.
bad_plan = copy.deepcopy(plan)
bad_plan["not_applicable_controls"].append(
    {"control_id": "LF_CONTRACT_CORE", "carrier": "LEGACY", "reason": "BAD_OVERLAP"}
)
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_PARTITION_OVERLAP")

# 19: invalid source-plan digest is rejected.
bad_plan = copy.deepcopy(plan)
bad_plan["plan_sha256"] = "not-a-digest"
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_DIGEST")

# 20: policy ordering is deterministic and enforced.
bad = copy.deepcopy(policy)
bad["states"][0], bad["states"][1] = bad["states"][1], bad["states"][0]
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_STATE_ORDER")

print(f"PASS_PASE_CONTROL_REPAIR_QUARANTINE_V1 checks={checks}")
