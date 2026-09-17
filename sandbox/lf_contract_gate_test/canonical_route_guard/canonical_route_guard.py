#!/usr/bin/env python3
"""Soft guard for canonical-route deviations.

This helper does not replace ACT-0001. The caller must first resolve the
canonical route from the Router/current authority and then compare that route
with the route it is about to use.

The guard is intentionally non-destructive:
- canonical route -> proceed;
- alternate route without explicit exploration -> ask one routing question;
- explicit exploration -> proceed only as EXPLORATORY_NO_CANONICAL_EFFECT;
- malformed/unresolved input -> resolve the canonical route first.

Route deviations are classifications, not hard security denials. Hard approval
boundaries (production, destructive actions, spend, irreversible effects, etc.)
remain governed by their own contracts.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict


@dataclass(frozen=True)
class RouteDecision:
    status: str
    decision: str
    canonical_route: str | None
    selected_route: str | None
    ask_user: bool
    question: str | None
    exploratory: bool
    canonical_effect_allowed: bool
    merge_allowed: bool | None
    production_effect_allowed: bool | None
    canonical_close_allowed: bool | None
    pass_claim_allowed: bool | None
    effect_authorization: str
    next_action: str


def _norm(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


def evaluate_route(
    canonical_route: str | None,
    selected_route: str | None,
    explicit_exploration: bool = False,
) -> RouteDecision:
    canonical = _norm(canonical_route)
    selected = _norm(selected_route)

    if canonical is None:
        return RouteDecision(
            status="ROUTE_UNRESOLVED",
            decision="RESOLVE_CANONICAL_ROUTE_FIRST",
            canonical_route=None,
            selected_route=selected,
            ask_user=False,
            question=None,
            exploratory=False,
            canonical_effect_allowed=False,
            merge_allowed=False,
            production_effect_allowed=False,
            canonical_close_allowed=False,
            pass_claim_allowed=False,
            effect_authorization="PENDING_ROUTE_RESOLUTION",
            next_action="RESOLVE_CANONICAL_ROUTE_WITH_ACT_0001_OR_CURRENT_AUTHORITY",
        )

    if selected == canonical:
        return RouteDecision(
            status="CANONICAL_ROUTE",
            decision="PROCEED_CANONICAL",
            canonical_route=canonical,
            selected_route=selected,
            ask_user=False,
            question=None,
            exploratory=False,
            canonical_effect_allowed=True,
            merge_allowed=None,
            production_effect_allowed=None,
            canonical_close_allowed=None,
            pass_claim_allowed=None,
            effect_authorization="DEFER_TO_GOVERNING_CONTRACT",
            next_action="CONTINUE_CANONICAL_FLOW",
        )

    if explicit_exploration:
        return RouteDecision(
            status="EXPLORATORY_ROUTE",
            decision="PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT",
            canonical_route=canonical,
            selected_route=selected,
            ask_user=False,
            question=None,
            exploratory=True,
            canonical_effect_allowed=False,
            merge_allowed=False,
            production_effect_allowed=False,
            canonical_close_allowed=False,
            pass_claim_allowed=False,
            effect_authorization="DENIED_BY_EXPLORATORY_MODE",
            next_action="EXPLORE_REVERSIBLY_AND_RETURN_TO_CANONICAL_ROUTE_BEFORE_EFFECT",
        )

    attempted = selected or "ruta directa/no declarada"
    question = (
        f"Existe una ruta canónica para esta intención: {canonical}. "
        f"La ruta seleccionada es {attempted}. "
        "¿Retomo la ruta canónica o quieres explorar deliberadamente la alternativa?"
    )
    return RouteDecision(
        status="ROUTE_DEVIATION",
        decision="ASK_CANONICAL_OR_EXPLORATORY",
        canonical_route=canonical,
        selected_route=selected,
        ask_user=True,
        question=question,
        exploratory=False,
        canonical_effect_allowed=False,
        merge_allowed=False,
        production_effect_allowed=False,
        canonical_close_allowed=False,
        pass_claim_allowed=False,
        effect_authorization="PENDING_ROUTE_CHOICE",
        next_action="ASK_ROUTE_CHOICE_ONCE",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-route", required=False)
    parser.add_argument("--selected-route", required=False)
    parser.add_argument(
        "--explicit-exploration",
        action="store_true",
        help="User explicitly chose an alternative route for exploration.",
    )
    args = parser.parse_args()
    decision = evaluate_route(
        args.canonical_route,
        args.selected_route,
        args.explicit_exploration,
    )
    print(json.dumps(asdict(decision), ensure_ascii=False, sort_keys=True))
    # Route deviation is a soft guard, not a shell-level hard denial.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
