#!/usr/bin/env python3
import copy
from pathlib import Path

import yaml

from validate_policy_operations_candidate import validate

ROOT = Path(__file__).resolve().parent
BASE = yaml.safe_load((ROOT / "policy_operations_contract.yaml").read_text(encoding="utf-8"))


def run_case(name, mutator, expected_fragment=None):
    data = copy.deepcopy(BASE)
    mutator(data)
    errors = validate(data)
    if expected_fragment is None:
        assert not errors, (name, errors)
    else:
        assert any(expected_fragment in e for e in errors), (name, expected_fragment, errors)
    print("PASS", name)


def noop(_):
    return None


def main():
    run_case("base", noop)
    run_case("invent_policy_asset_type", lambda d: d["asset_contract"].__setitem__("asset_type", "POLICY"), "ASSET_TYPE_MUST_BE_REGLA")
    run_case("unsupported_persisted_status", lambda d: d["lifecycle_model"]["persisted_status_mapping"].__setitem__("CANARY", "CANARY"), "LIFECYCLE_PERSISTENCE_MAPPING_MISMATCH")
    run_case("overwrite_prior_version", lambda d: d["update_contract"]["successor_rules"].__setitem__("overwrite_prior_version", True), "SUCCESSOR_RULE_MISMATCH:overwrite_prior_version")
    run_case("premature_supersede", lambda d: d["update_contract"]["successor_rules"].__setitem__("supersede_active_before_verified_promotion", True), "SUCCESSOR_RULE_MISMATCH:supersede_active_before_verified_promotion")
    run_case("automatic_promotion", lambda d: d["state_ceiling"].__setitem__("automatic_promotion_allowed", True), "STATE_CEILING_MISMATCH:automatic_promotion_allowed")
    run_case("create_contradictory_target_flags", lambda d: d["operations"]["create"].__setitem__("requires_existing_target", True), "CREATE_REQUIRES_EXISTING_TARGET_MISMATCH")
    run_case("production_enabled", lambda d: d["state_ceiling"].__setitem__("production_allowed", True), "STATE_CEILING_MISMATCH:production_allowed")
    run_case("cross_lane_branch_base", lambda d: d["cross_lane_dependency_policy"].__setitem__("dependency_mode", "STACKED_BRANCH_REQUIRED"), "CROSS_LANE_DEPENDENCY_MODE_MISMATCH")
    run_case("cross_lane_blocks_canary", lambda d: d["cross_lane_dependency_policy"]["non_blocking_scope"].remove("rollback_canary"), "CROSS_LANE_NON_BLOCKING_SCOPE_MISSING:rollback_canary")
    run_case("missing_isolation_guard", lambda d: d["hard_guards"].remove("NO_CROSS_LANE_BRANCH_BASE"), "HARD_GUARDS_MISSING:NO_CROSS_LANE_BRANCH_BASE")
    print("POLICY_OPERATIONS_REGRESSIONS_PASS=11/11")


if __name__ == "__main__":
    main()
