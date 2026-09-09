#!/usr/bin/env python3
import copy
from pathlib import Path

import yaml

from validate_policy_operations_candidate import validate


ROOT = Path(__file__).resolve().parent
BASE = yaml.safe_load((ROOT / "policy_operations_contract.yaml").read_text(encoding="utf-8"))


def run_case(name, mutator, expect_valid):
    data = copy.deepcopy(BASE)
    mutator(data)
    errors = validate(data)
    actual = not errors
    if actual != expect_valid:
        raise AssertionError(f"{name}: expected valid={expect_valid}, got valid={actual}, errors={errors}")
    print(f"PASS {name}: valid={actual}")


def noop(_):
    return None


def main():
    cases = [
        ("base", noop, True),
        ("invent_policy_asset_type", lambda d: d["asset_contract"].__setitem__("asset_type", "POLICY"), False),
        ("wrong_create_action", lambda d: d["asset_contract"].__setitem__("create_action_code", "REGLA_CREATE"), False),
        ("unsupported_persisted_status", lambda d: d["lifecycle_model"]["persisted_status_mapping"].__setitem__("CANARY", "CANARY"), False),
        ("overwrite_prior_version", lambda d: d["update_contract"]["successor_rules"].__setitem__("overwrite_prior_version", True), False),
        ("premature_supersede", lambda d: d["update_contract"]["successor_rules"].__setitem__("supersede_active_before_verified_promotion", True), False),
        ("automatic_promotion", lambda d: d["state_ceiling"].__setitem__("automatic_promotion_allowed", True), False),
        ("create_contradictory_target_flags", lambda d: d["operations"]["create"].__setitem__("requires_existing_target", True), False),
        ("production_enabled", lambda d: d["state_ceiling"].__setitem__("production_allowed", True), False),
    ]
    for name, mutator, expect_valid in cases:
        run_case(name, mutator, expect_valid)
    print(f"POLICY_OPERATIONS_REGRESSIONS_PASS={len(cases)}/{len(cases)}")


if __name__ == "__main__":
    main()
