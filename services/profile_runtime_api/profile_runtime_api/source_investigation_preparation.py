"""Inactive Hetzner-side adapter for LF D1-D3 *metadata preparation only*.

Supabase owns discovery, bindings, policy and procedure. This adapter never
executes a business data facade, writes to SQL, routes a job or grants access.
It is not wired into the worker; installing it does not enable a new route.
"""
from __future__ import annotations

from collections.abc import Mapping
from typing import Any

PREPARATION_SQL = (
    "SELECT private.fn_lf_source_investigation_prepare_v1(%s, %s) AS preparation"
)
SCHEMA = "LF_SOURCE_INVESTIGATION_PREPARATION_V1"
ALLOWED_NEXT_ACTIONS = frozenset({
    "BLOCK_MANAGED_INVENTORY_NOT_CURRENT",
    "BLOCK_INVENTORY_LOOKUP_CURRENTNESS_UNSTABLE",
    "BLOCK_CANONICAL_AUTHORITY_ACL_DENIED",
    "BLOCK_DISCOVERY_POLICY_OR_TECHNICAL_ERROR",
    "BLOCK_MALFORMED_PROCEDURE_INPUT",
    "EXPAND_DISCOVERY_SCOPE_OR_OBTAIN_MORE_CONTEXT",
    "RESOLVE_CANONICAL_BINDING_FOR_CANDIDATES",
    "RETURN_TO_CANONICAL_SOURCE_DISCOVERY",
    "SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING",
    "REQUEST_REAL_IDENTITY_AND_TENANT_FACADE_ADMISSION",
    "BLOCK_UNVERIFIED_OR_UNAUTHORIZED_SOURCE",
    "RETURN_TO_TARGETED_EVIDENCE_ACQUISITION",
})
_FALSE_FIELDS = (
    "business_data_read_authorized",
    "rows_accessed",
    "runtime_dispatched",
    "final_business_answer_allowed",
    "effects_executed",
    "global_discovery_exhausted",
)


class PreparationContractError(RuntimeError):
    """Stable, non-sensitive failure code for a refused procedure handoff."""


def prepare_source_investigation(
    cursor: Any, objective: str, max_candidates: int = 12,
) -> dict[str, Any]:
    """Read only the pre-installed, canonical Supabase preparation function.

    Caller owns a trusted DB connection; objective is merely query text, not
    policy, tenant, authority, ACL, raw SQL or an asserted evidence receipt.
    No fallback to a privileged SELECT on a business table is allowed.
    """
    if not isinstance(objective, str) or not 3 <= len(objective.strip()) <= 1000:
        raise PreparationContractError("LF_D4_OBJECTIVE_INVALID")
    if type(max_candidates) is not int or not 1 <= max_candidates <= 25:
        raise PreparationContractError("LF_D4_CANDIDATE_LIMIT_INVALID")

    try:
        cursor.execute(PREPARATION_SQL, (objective.strip(), max_candidates))
        row = cursor.fetchone()
    except Exception as exc:
        raise PreparationContractError("LF_D4_CANONICAL_READBACK_FAILED") from None

    if not isinstance(row, (list, tuple)) or len(row) != 1:
        raise PreparationContractError("LF_D4_CANONICAL_RESULT_SHAPE_INVALID")
    plan = row[0]
    if not isinstance(plan, Mapping) or plan.get("schema_version") != SCHEMA:
        raise PreparationContractError("LF_D4_CANONICAL_SCHEMA_MISMATCH")
    if any(plan.get(flag) is not False for flag in _FALSE_FIELDS):
        raise PreparationContractError("LF_D4_UNAUTHORIZED_EFFECT_IN_PREPARATION")
    if plan.get("planner_stop_is_local_only") is not True:
        raise PreparationContractError("LF_D4_DISCOVERY_EXHAUSTION_SCOPE_INVALID")

    action = plan.get("next_action")
    if action not in ALLOWED_NEXT_ACTIONS:
        raise PreparationContractError("LF_D4_NEXT_ACTION_NOT_RECOGNIZED")
    observation = plan.get("discovery")
    if not isinstance(observation, Mapping) or not isinstance(
        observation.get("discovery_state"), str
    ):
        raise PreparationContractError("LF_D4_DISCOVERY_RESULT_INVALID")
    checks = plan.get("binding_checks", [])
    checked_count = plan.get("binding_checks_count")
    if (
        not isinstance(checks, list) or type(checked_count) is not int
        or checked_count != len(checks) or checked_count > max_candidates
    ):
        raise PreparationContractError("LF_D4_BINDING_READBACK_COUNT_MISMATCH")
    if any(
        not isinstance(check, Mapping)
        or check.get("access_authorized") is not False
        or check.get("rows_accessed") is not False
        for check in checks
    ):
        raise PreparationContractError("LF_D4_SOURCE_READ_NOT_ADMITTED")

    decision = plan.get("d3")
    if decision is not None:
        if not isinstance(decision, Mapping) or decision.get("next_action") != action:
            raise PreparationContractError("LF_D4_D3_ACTION_MISMATCH")
        if decision.get("final_business_answer_allowed") is not False:
            raise PreparationContractError("LF_D4_D3_BUSINESS_ANSWER_FORBIDDEN")
    elif not action.startswith("BLOCK_"):
        raise PreparationContractError("LF_D4_D3_DECISION_MISSING")

    if any(k in plan for k in ("business_rows", "customer_records", "raw_sql")):
        raise PreparationContractError("LF_D4_UNAUTHORIZED_DATA_PLANE_PAYLOAD")
    return dict(plan)
