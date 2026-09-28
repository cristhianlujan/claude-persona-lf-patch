#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "wp4_owner_decomposition_v1.json"
GUARD = HERE / "s36_wp4_identity_authority_guard.py"
README = HERE / "README.md"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    guard = GUARD.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")

    assert contract["legacy_lane"] == "S36_WP4_ADVERSARIAL"
    assert contract["role"] == "HISTORICAL_INTEGRATION_REGRESSION"
    assert contract["new_umbrella_capability_allowed"] is False

    routes = contract["invariant_routes"]
    for code in ("REVIEW_IDENTITY_MISSING", "PRODUCER_AS_REVIEWER", "REVIEW_MODE_NOT_INDEPENDENT"):
        assert code in guard
        assert routes[code]["owner"] == "INDEPENDENT_REVIEW"
        assert routes[code]["inventory_identity"] == "INDEPENDENT_ASSURANCE"
        assert routes[code]["operation"] == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"

    for code in ("REQUESTED_AUTHORITY_MISSING", "AUTHORITY_ESCALATION_ATTEMPT"):
        assert code in guard
        assert routes[code]["owner_chain"] == ["POLICY_CONSUMPTION", "ROUTER_DOWNSTREAM_AUTHORITY"]

    # Historical compatibility remains explicit, but S36 cannot remain canonical owner.
    assert '"S36_ASSURANCE"' in guard
    assert contract["legacy_aliases"]["rule"] == "COMPATIBILITY_ONLY_NOT_CANONICAL_OWNER"
    assert "not an end-to-end owner" in readme
    assert "Do not create `ADVERSARIAL_SECURITY`" in readme

    assert contract["open_states"]["REQUIRED_STEP_BYPASS_TRANSVERSAL_DYNAMIC"] == "NOT_COVERED"
    assert contract["open_states"]["INVALID_STATE_TRANSITION_TRANSVERSAL_NEGATIVE"] == "NOT_COVERED"
    assert contract["open_states"]["LIVE_DESTRUCTIVE_AUTHORITY_ESCALATION"] == "BLOCKED"

    # Boundary package must not materialize another router/security/reviewer engine.
    package = readme + "\n" + CONTRACT.read_text(encoding="utf-8")
    lowered = package.lower()
    for token in (
        "create table",
        "create or replace function",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_WP4_PARALLEL_OWNER:{token}"

    print("WP4_OWNER_DECOMPOSITION=PASS")


if __name__ == "__main__":
    main()
