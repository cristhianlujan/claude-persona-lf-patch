#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from validate_lf_work_package_bootstrap_v0_1 import FAIL, PASS, validate

ROOT = Path(__file__).resolve().parent
WP_PATH = ROOT / "wp_s31_a_canonical_capability_model_v0_1.json"


def main() -> int:
    base = json.loads(WP_PATH.read_text(encoding="utf-8"))

    positive = validate(base)
    assert positive["result"] == PASS, positive
    assert positive["material_work_allowed"] is True, positive

    stale = copy.deepcopy(base)
    stale["currentness"]["base_main_sha"] = "STALE"
    negative_stale = validate(stale)
    assert negative_stale["result"] == FAIL, negative_stale
    assert "BASE_MAIN_SHA_INVALID" in negative_stale["failures"], negative_stale

    cross_lane = copy.deepcopy(base)
    cross_lane["scope"]["allowed_write_scope"] = ["gobernanza/contratos/"]
    negative_scope = validate(cross_lane)
    assert negative_scope["result"] == FAIL, negative_scope
    assert any(x.startswith("WRITE_SCOPE_ESCAPES_S31:") for x in negative_scope["failures"]), negative_scope

    weakened = copy.deepcopy(base)
    weakened["scope"]["forbidden_actions"].remove("MUTATE_S30_INTERNALS")
    negative_guard = validate(weakened)
    assert negative_guard["result"] == FAIL, negative_guard
    assert any(x.startswith("MANDATORY_FORBIDDEN_MISSING:") for x in negative_guard["failures"]), negative_guard

    unresolved = copy.deepcopy(base)
    unresolved["frontier"]["next_gate"] = "MATERIAL_WORK"
    unresolved["capability_binding"]["unresolved_capabilities"] = ["UNKNOWN_REQUIRED_CAPABILITY"]
    negative_unresolved = validate(unresolved)
    assert negative_unresolved["result"] == FAIL, negative_unresolved
    assert "UNRESOLVED_CAPABILITY_BLOCKS_MATERIAL_WORK" in negative_unresolved["failures"], negative_unresolved

    print(json.dumps({
        "contract": "LF_WORK_PACKAGE_BOOTSTRAP_V0_1_SELF_TEST",
        "positive": positive["result"],
        "negative_stale": negative_stale["result"],
        "negative_cross_lane": negative_scope["result"],
        "negative_guard_weakening": negative_guard["result"],
        "negative_unresolved_capability": negative_unresolved["result"],
        "result": "PASS"
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
