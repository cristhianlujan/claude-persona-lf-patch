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

# 13: administrative owner drift fails closed.
bad = copy.deepcopy(policy)
bad["administrative_owner"] = "LEGACY_OWNER"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_ADMIN_OWNER")

# 14: runner-binding policy drift fails closed.
bad = copy.deepcopy(policy)
bad["runner_binding_policy"]["INTERNAL_CI_CHECK"] = "PASS"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_RUNNER_BINDING")

# 15: active blocking cannot return without re-entry evidence.
bad = copy.deepcopy(policy)
bad["states"][0]["state"] = "ACTIVE_BLOCKING"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_EVIDENCE_MISSING")

# 16-17: a control requiring a canonical runner may return only with the full contract.
reactivated = copy.deepcopy(policy)
row = next(item for item in reactivated["states"] if item["control_id"] == "MIGRATION_SOURCE_PARITY")
row["state"] = "ACTIVE_BLOCKING"
row["reentry_evidence"] = {
    "qualification_verdict": "CANDIDATE_QUALIFIED",
    "qualification_head_sha": "b" * 40,
    "administrative_owner": "LF_GOVERNANCE",
    "reentry_class": "CANONICAL_RUNNER_REQUIRED",
    "runner_binding": "PASS",
    "equivalent_replay": "PASS",
    "exact_head_readback": "PASS",
}
reactivated_result = project_enforcement(plan, reactivated)
ok(reactivated_result["blocking_controls"] == ["MIGRATION_SOURCE_PARITY"], "bound-control re-entry")
ok(
    reactivated_result["observe_only_controls"] == ["LF_CONTRACT_CORE", "PROFILE_RUNTIME_V3"],
    "others remain quarantined",
)

# 18: every re-entry keeps LF_GOVERNANCE as the single administrative owner.
bad = copy.deepcopy(reactivated)
row = next(item for item in bad["states"] if item["control_id"] == "MIGRATION_SOURCE_PARITY")
row["reentry_evidence"]["administrative_owner"] = "LF_GOVERNANCE_S30_DB"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_ADMIN_OWNER")

# 19: unknown re-entry class cannot bypass runner requirements.
bad = copy.deepcopy(reactivated)
row = next(item for item in bad["states"] if item["control_id"] == "MIGRATION_SOURCE_PARITY")
row["reentry_evidence"]["reentry_class"] = "UNKNOWN"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_CLASS")

# 20: a canonical-runner-required control cannot claim runner NOT_REQUIRED.
bad = copy.deepcopy(reactivated)
row = next(item for item in bad["states"] if item["control_id"] == "MIGRATION_SOURCE_PARITY")
row["reentry_evidence"]["runner_binding"] = "NOT_REQUIRED"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_OWNER_RUNNER")

# 21: an applicable INTERNAL_CI_CHECK may re-enter without inventing an owner-runner.
internal = copy.deepcopy(policy)
row = next(item for item in internal["states"] if item["control_id"] == "CI_ROUTER_SELFTEST")
row["state"] = "ACTIVE_BLOCKING"
row["reentry_evidence"] = {
    "qualification_verdict": "CANDIDATE_QUALIFIED",
    "qualification_head_sha": "c" * 40,
    "administrative_owner": "LF_GOVERNANCE",
    "reentry_class": "INTERNAL_CI_CHECK",
    "runner_binding": "NOT_REQUIRED",
    "equivalent_replay": "PASS",
    "exact_head_readback": "PASS",
}
internal_required = ["CI_ROUTER_SELFTEST"]
internal_plan = {
    "schema_version": "lf-ci-execution-plan/v2",
    "coverage_complete": True,
    "control_universe": universe,
    "required_controls": internal_required,
    "not_applicable_controls": [
        {"control_id": cid, "carrier": "LEGACY", "reason": "TEST_NOT_APPLICABLE"}
        for cid in universe
        if cid not in internal_required
    ],
    "plan_sha256": "d" * 64,
}
internal_result = project_enforcement(internal_plan, internal)
ok(internal_result["blocking_controls"] == ["CI_ROUTER_SELFTEST"], "internal-check re-entry without runner")

# 22: INTERNAL_CI_CHECK must not acquire an artificial owner-runner binding.
bad = copy.deepcopy(internal)
row = next(item for item in bad["states"] if item["control_id"] == "CI_ROUTER_SELFTEST")
row["reentry_evidence"]["runner_binding"] = "PASS"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_INTERNAL_RUNNER_BINDING")

# 23: replay is mandatory for re-entry.
bad = copy.deepcopy(reactivated)
row = next(item for item in bad["states"] if item["control_id"] == "MIGRATION_SOURCE_PARITY")
row["reentry_evidence"]["equivalent_replay"] = "FAIL"
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_REENTRY_REPLAY")

# 24: incomplete applicability coverage cannot be projected.
bad_plan = copy.deepcopy(plan)
bad_plan["coverage_complete"] = False
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_COVERAGE")

# 25: overlapping applicable/not-applicable partition fails closed.
bad_plan = copy.deepcopy(plan)
bad_plan["not_applicable_controls"].append(
    {"control_id": "LF_CONTRACT_CORE", "carrier": "LEGACY", "reason": "BAD_OVERLAP"}
)
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_PARTITION_OVERLAP")

# 26: invalid source-plan digest is rejected.
bad_plan = copy.deepcopy(plan)
bad_plan["plan_sha256"] = "not-a-digest"
fails(lambda: project_enforcement(bad_plan, policy), "FAIL_REPAIR_PLAN_DIGEST")

# 27: policy ordering is deterministic and enforced.
bad = copy.deepcopy(policy)
bad["states"][0], bad["states"][1] = bad["states"][1], bad["states"][0]
fails(lambda: validate_policy(bad, control_universe=universe), "FAIL_REPAIR_POLICY_STATE_ORDER")

print(f"PASS_PASE_CONTROL_REPAIR_QUARANTINE_V1 checks={checks}")
