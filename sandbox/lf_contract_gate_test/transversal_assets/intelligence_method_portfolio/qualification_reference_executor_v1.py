#!/usr/bin/env python3
"""Qualification-only reference executor for Wave 2 deterministic challengers.

This is NOT a production selector, does not replace CAPABILITY_SELECTOR@CURRENT,
and never grants execution permission. It exists only to make the frozen challenger
contracts executable under deterministic/adversarial qualification.
"""
from __future__ import annotations

from itertools import combinations
from typing import Any


def _result(method_ref: str, *, selected_options=None, reasons=None, unknowns=None,
            contradictions=None, fallback: str = "NONE") -> dict[str, Any]:
    return {
        "method_ref": method_ref,
        "selected_options": selected_options or [],
        "reasons": reasons or [],
        "unknowns": unknowns or [],
        "contradictions": contradictions or [],
        "fallback": fallback,
        "execution_permission": False,
    }


def deterministic_signal_rule_classifier(signals: dict[str, Any]) -> dict[str, Any]:
    method = "DETERMINISTIC_SIGNAL_RULE_CLASSIFIER@0.1.0-candidate"
    labels: list[str] = []
    reasons: list[str] = []
    artifact_kinds = {str(x).upper() for x in signals.get("artifact_kinds", [])}
    paths = [str(x).lower() for x in signals.get("changed_paths", [])]
    if (
        "MIGRATION" in artifact_kinds
        or signals.get("governed_constraint_change")
        or any("/migrations/" in p or p.startswith("supabase/migrations/") for p in paths)
    ):
        labels.append("DB_MIGRATION")
        reasons.append("typed migration/governed-constraint signal")
    if (
        signals.get("runtime_surface")
        or signals.get("worker_runtime_change")
        or signals.get("execution_envelope_change")
    ):
        labels.append("RUNTIME")
        reasons.append("typed runtime/execution signal")
    if signals.get("api_contract_change") or "API_CONTRACT" in artifact_kinds:
        labels.append("API")
        reasons.append("typed API-contract signal")
    docs_only = bool(paths) and all(p.startswith("docs/") or p.endswith(".md") for p in paths)
    if docs_only and not labels:
        labels.append("DOCS")
        reasons.append("all changed paths are documentary and no harder material signal exists")
    if not labels:
        return _result(
            method,
            reasons=["no declared rule safely covers material signal"],
            unknowns=["UNKNOWN_MATERIAL_SIGNAL"],
            fallback="TARGETED_EVIDENCE",
        )
    return _result(method, selected_options=labels, reasons=reasons)


def hybrid_rule_first_semantic_classifier(
    signals: dict[str, Any],
    *,
    semantic_labels: list[str] | None = None,
    semantic_evidence_refs: list[str] | None = None,
) -> dict[str, Any]:
    method = "HYBRID_RULE_FIRST_SEMANTIC_CLASSIFIER@0.1.0-candidate"
    base = deterministic_signal_rule_classifier(signals)
    hard = set(base["selected_options"])
    if hard:
        additions: list[str] = []
        for label in semantic_labels or []:
            if label not in hard and label not in additions:
                additions.append(label)
        reasons = list(base["reasons"])
        if additions:
            reasons.append(
                f"semantic additions supported by {len(semantic_evidence_refs or [])} refs"
            )
        return _result(
            method,
            selected_options=base["selected_options"] + additions,
            reasons=reasons,
        )
    if not semantic_labels:
        return _result(
            method,
            reasons=base["reasons"],
            unknowns=base["unknowns"],
            fallback="TARGETED_EVIDENCE",
        )
    return _result(
        method,
        selected_options=list(dict.fromkeys(semantic_labels)),
        reasons=[
            f"semantic fallback after deterministic unknown; refs={len(semantic_evidence_refs or [])}"
        ],
    )


def deterministic_invariant_veto(
    options: list[dict[str, Any]], invariants: list[dict[str, Any]]
) -> dict[str, Any]:
    method = "DETERMINISTIC_INVARIANT_VETO@0.1.0-candidate"
    required = {i["id"] for i in invariants if i.get("material", True)}
    unknown = [
        i["id"]
        for i in invariants
        if i.get("state") == "UNKNOWN" and i.get("material", True)
    ]
    if unknown:
        return _result(
            method,
            reasons=["material invariant evidence incomplete"],
            unknowns=unknown,
            fallback="TARGETED_EVIDENCE",
        )
    safe: list[str] = []
    reasons: list[str] = []
    for option in options:
        violated = set(option.get("violated_invariants", [])) & required
        if violated:
            reasons.append(f"{option['id']} vetoed by {','.join(sorted(violated))}")
        else:
            safe.append(option["id"])
    if not safe:
        return _result(method, reasons=reasons, fallback="BLOCK_NO_SAFE_OPTION")
    return _result(
        method,
        selected_options=safe,
        reasons=reasons or ["no material invariant violation"],
    )


def constraint_elimination(
    options: list[dict[str, Any]], constraints: list[dict[str, Any]]
) -> dict[str, Any]:
    method = "CONSTRAINT_ELIMINATION@0.1.0-candidate"
    material = {c["id"] for c in constraints if c.get("material", True)}
    unknown = [
        c["id"]
        for c in constraints
        if c.get("state") == "UNKNOWN" and c.get("material", True)
    ]
    if unknown:
        return _result(
            method,
            unknowns=unknown,
            reasons=["material constraint unresolved"],
            fallback="TARGETED_EVIDENCE",
        )
    feasible: list[str] = []
    reasons: list[str] = []
    for option in options:
        violations = set(option.get("violates", [])) & material
        if violations:
            reasons.append(f"{option['id']} eliminated by {','.join(sorted(violations))}")
        else:
            feasible.append(option["id"])
    if not feasible:
        return _result(method, reasons=reasons, fallback="BLOCK_NO_FEASIBLE_STRATEGY")
    if len(feasible) > 1:
        return _result(
            method,
            selected_options=feasible,
            reasons=reasons + ["multiple non-dominated feasible options"],
            fallback="BOUNDED_ALTERNATIVES",
        )
    return _result(
        method,
        selected_options=feasible,
        reasons=reasons + ["single feasible option"],
    )


def dependency_constraint_partition_selector(
    options: list[dict[str, Any]],
) -> dict[str, Any]:
    method = "DEPENDENCY_CONSTRAINT_PARTITION_SELECTOR@0.1.0-candidate"
    safe: list[dict[str, Any]] = []
    reasons: list[str] = []
    for option in options:
        bad: list[str] = []
        if option.get("breaks_dependency"):
            bad.append("DEPENDENCY")
        if option.get("write_conflict"):
            bad.append("WRITE_CONFLICT")
        if option.get("breaks_atomicity"):
            bad.append("ATOMICITY")
        if not option.get("context_budget_ok", True):
            bad.append("CONTEXT_BUDGET")
        if bad:
            reasons.append(f"{option['id']} rejected:{','.join(bad)}")
        else:
            safe.append(option)
    if not safe:
        return _result(method, reasons=reasons, fallback="REPARTITION_REQUIRED")
    reusable = [o for o in safe if o.get("reuses_shared_capability")]
    candidates = reusable or safe
    return _result(
        method,
        selected_options=[o["id"] for o in candidates],
        reasons=reasons + ["safe partitions preserved; reusable candidates preferred"],
    )


def claim_method_constraint_selector(
    claims: list[dict[str, Any]], methods: list[dict[str, Any]]
) -> dict[str, Any]:
    method_ref = "CLAIM_METHOD_CONSTRAINT_SELECTOR@0.1.0-candidate"
    required: set[str] = set()
    for claim in claims:
        required.update(claim.get("required_observations", []))
    capabilities = {m["id"]: set(m.get("observes", [])) for m in methods}
    ids = list(capabilities)
    covering_sets: list[tuple[str, ...]] = []
    for size in range(1, len(ids) + 1):
        for combo in combinations(ids, size):
            observed = set().union(*(capabilities[x] for x in combo))
            if required <= observed:
                covering_sets.append(combo)
        if covering_sets:
            break
    if not covering_sets:
        observed = set().union(*(capabilities[x] for x in ids)) if ids else set()
        return _result(
            method_ref,
            unknowns=sorted(required - observed),
            fallback="BLOCK_CLAIM_UNTESTABLE",
        )
    if len(covering_sets) > 1:
        return _result(
            method_ref,
            selected_options=["+".join(x) for x in covering_sets],
            reasons=["multiple minimal complementary method sets"],
            fallback="BOUNDED_ALTERNATIVES",
        )
    return _result(
        method_ref,
        selected_options=list(covering_sets[0]),
        reasons=["minimum method set covers every material observation"],
    )


def obligation_preserving_budget(
    obligations: list[dict[str, Any]], tiers: list[dict[str, Any]]
) -> dict[str, Any]:
    method = "OBLIGATION_PRESERVING_BUDGET@0.1.0-candidate"
    required = {o["id"] for o in obligations if o.get("material", True)}
    for tier in tiers:
        if required <= set(tier.get("covers", [])) and tier.get("within_budget", False):
            return _result(
                method,
                selected_options=[tier["id"]],
                reasons=["lowest feasible tier preserves all material obligations"],
            )
    return _result(
        method,
        unknowns=sorted(required),
        reasons=["no current budget tier preserves every material obligation"],
        fallback="ESCALATE_BUDGET_OR_BLOCK",
    )


def adaptive_evidence_escalation(
    state: dict[str, Any], tiers: list[dict[str, Any]]
) -> dict[str, Any]:
    method = "ADAPTIVE_EVIDENCE_ESCALATION@0.1.0-candidate"
    if (
        state.get("sufficient")
        and not state.get("material_uncertainty")
        and not state.get("contradiction")
    ):
        return _result(
            method,
            selected_options=[state["current_tier"]],
            reasons=["material evidence sufficient"],
            fallback="STOP_SUFFICIENT",
        )
    ids = [t["id"] for t in tiers]
    try:
        index = ids.index(state["current_tier"])
    except ValueError:
        return _result(method, unknowns=["CURRENT_TIER_UNKNOWN"], fallback="BLOCK")
    if index + 1 >= len(ids):
        return _result(
            method,
            unknowns=["MATERIAL_UNCERTAINTY_REMAINS"],
            fallback="BLOCK_ESCALATION_LIMIT",
        )
    return _result(
        method,
        selected_options=[ids[index + 1]],
        reasons=["material uncertainty/contradiction requires escalation"],
        fallback="ESCALATE",
    )
