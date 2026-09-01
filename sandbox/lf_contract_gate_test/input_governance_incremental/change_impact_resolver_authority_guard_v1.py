from __future__ import annotations

from change_impact_resolver_readonly_v1 import (
    ChangeImpactResult,
    RuntimeAuthority,
    resolve_change_impact as _base_resolve_change_impact,
)


def resolve_change_impact(
    change_surface: str,
    mutation: str,
    runtime: RuntimeAuthority,
) -> ChangeImpactResult:
    """READ_ONLY authority guard over the research resolver.

    Cross-Audit GOV-CHANGE-IMPACT-AUTHORITY-HOLDOUT-GAP-001 requires direct
    API mutations to preserve explicit UNKNOWN signaling when the behavioral
    contract itself is absent. This wrapper changes no gold labels and delegates
    all states with behavioral authority to the existing research resolver.
    """
    base = _base_resolve_change_impact(change_surface, mutation, runtime)
    if change_surface.strip().upper() != "API_DATA_CONTRACT" or runtime.behavioral_contract_present:
        return base

    impacts = tuple(dict.fromkeys((*base.impacted_families, "SOURCE_AUTHORITY_PROVENANCE")))
    return ChangeImpactResult(
        decision="HUMAN_REQUIRED",
        impacted_families=impacts,
        uncertainty="UNKNOWN",
        shared_dependency=len(impacts) > 1,
        fail_closed=True,
        rationale_code="API_BEHAVIORAL_AUTHORITY_MISSING",
    )
