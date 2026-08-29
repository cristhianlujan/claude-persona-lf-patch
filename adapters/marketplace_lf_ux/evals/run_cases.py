#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "validators/validate_marketplace_lf_ux_adapter.py"
spec = importlib.util.spec_from_file_location("ux_validator", VALIDATOR)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)

PROFILE = "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531"


def base_result():
    return {
        "state": "BOUND_CANDIDATE_ONLY",
        "marketplace_ux_binding": {
            "source_refs": ["marketplace:surface-1"],
            "marketplace_context": {"objective": "reduce selection friction"},
            "prioritized_frictions": [{"id": "UX-1", "evidence": "supplied"}],
            "improvements": [{"id": "P-1", "status": "PROPOSED_NOT_CANONICAL"}],
            "protected_constraints": ["preserve product truth"],
            "downstream_dependencies": ["UI authority if visual change is needed"],
            "blockers": [],
        },
        "lf_adapter_invocations": [{
            "invocation_id": "lfai-ux-positive-001",
            "adapter_code": "ADAPTER_MARKETPLACE_LF_UX",
            "assurance_revision": "v2",
            "activation_source": "ROUTER",
            "binding_ref": "public.v_lf_router_adapter_bindings:ADAPTER-MARKETPLACE-LF-UX-20260531:" + PROFILE,
            "profile_id": PROFILE,
            "target_ref": PROFILE,
            "capsule_ref": "adapters/marketplace_lf_ux/runtime/runtime_capsule.yaml",
            "capsule_char_count": 700,
            "source_refs": ["adapters/marketplace_lf_ux/runtime/runtime_capsule.yaml"],
            "verdict": "APPLIED",
        }],
    }


def expect_fail(code: str, payload) -> None:
    try:
        module.validate_result(payload)
    except ValueError as exc:
        if str(exc) != code:
            raise AssertionError(f"expected {code}, got {exc}") from exc
    else:
        raise AssertionError(f"expected {code}")


def main() -> int:
    module.validate_package(ROOT)
    good = base_result()
    module.validate_result(good)
    count = 1

    missing = deepcopy(good); missing["lf_adapter_invocations"] = []
    expect_fail("EXACTLY_ONE_INVOCATION_REQUIRED", missing); count += 1

    duplicate = deepcopy(good); duplicate["lf_adapter_invocations"].append(deepcopy(duplicate["lf_adapter_invocations"][0]))
    expect_fail("EXACTLY_ONE_INVOCATION_REQUIRED", duplicate); count += 1

    direct = deepcopy(good); direct["lf_adapter_invocations"][0]["activation_source"] = "PROFILE"
    expect_fail("BLOCK_UNBOUND_ADAPTER_INVOCATION", direct); count += 1

    wrong_target = deepcopy(good); wrong_target["lf_adapter_invocations"][0]["target_ref"] = "OTHER"
    expect_fail("INVOCATION_TARGET_MISMATCH", wrong_target); count += 1

    over_budget = deepcopy(good); over_budget["lf_adapter_invocations"][0]["capsule_char_count"] = 1601
    expect_fail("BLOCK_CONTEXT_BUDGET_EXCEEDED", over_budget); count += 1

    blocked_without_reason = deepcopy(good); blocked_without_reason["state"] = "BLOCKED_SOURCE_CONFLICT"
    expect_fail("BLOCKER_STATE_INCONSISTENT", blocked_without_reason); count += 1

    unsupported_invocation = deepcopy(good); unsupported_invocation["lf_adapter_invocations"][0]["adapter_code"] = "ADAPTER_LF_SHELL_PROFILE"
    expect_fail("INVOCATION_IDENTITY_INVALID", unsupported_invocation); count += 1

    if count != 8:
        raise SystemExit(f"MARKETPLACE_LF_UX_CASES_FAIL {count}/8")
    print("MARKETPLACE_LF_UX_CASES_PASS 8/8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
