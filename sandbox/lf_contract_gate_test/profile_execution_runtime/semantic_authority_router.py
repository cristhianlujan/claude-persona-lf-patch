#!/usr/bin/env python3
"""Strategy 26 sandbox-only deterministic semantic authority routing candidate.

This is not a new governance layer and is not wired into production runtime.
It is a candidate helper for the existing Router/ACTIVATION_ROUTING path.
Unknown, ambiguous, or insufficiently grounded tasks fail to the stronger
semantic authority rather than silently using the local 3B runtime.
"""

from __future__ import annotations

from dataclasses import dataclass

LOCAL_3B_SOURCE_GROUNDED = "LOCAL_3B_SOURCE_GROUNDED"
STRONG_SEMANTIC_AUTHORITY = "STRONG_SEMANTIC_AUTHORITY"

SOURCE_GROUNDED_KINDS = frozenset(
    {
        "EXTRACT_EXISTING",
        "VERIFY_EXISTING",
        "REPRODUCE_EXISTING",
        "APPLY_EXISTING_DECISION",
    }
)
NOVEL_SEMANTIC_KINDS = frozenset(
    {
        "NOVEL_DECISION",
        "SYNTHESIZE_NOVEL",
        "DESIGN_NOVEL",
        "PRIORITIZE_TRADEOFFS",
    }
)


@dataclass(frozen=True)
class SemanticAuthorityDecision:
    route: str
    reason_code: str
    task_kind: str


def select_semantic_authority(
    *,
    task_kind: str | None,
    source_grounding_ready: bool,
    authority_ref: str | None,
    requires_novel_judgment: bool,
) -> SemanticAuthorityDecision:
    """Select the semantic authority with deterministic fail-closed behavior.

    The local 3B route is allowed only when the task kind is explicitly
    source-grounded, novel judgment is not required, and a concrete authority
    reference is present. Everything else routes to the stronger authority.
    """

    normalized = task_kind.strip().upper() if isinstance(task_kind, str) else ""

    if not normalized:
        return SemanticAuthorityDecision(
            STRONG_SEMANTIC_AUTHORITY,
            "UNKNOWN_FAILS_TO_STRONG",
            normalized,
        )

    if normalized in SOURCE_GROUNDED_KINDS:
        if requires_novel_judgment:
            return SemanticAuthorityDecision(
                STRONG_SEMANTIC_AUTHORITY,
                "NOVEL_FLAG_OVERRIDES_SOURCE_KIND",
                normalized,
            )
        if source_grounding_ready and isinstance(authority_ref, str) and authority_ref.strip():
            return SemanticAuthorityDecision(
                LOCAL_3B_SOURCE_GROUNDED,
                "SOURCE_GROUNDING_PROVEN",
                normalized,
            )
        return SemanticAuthorityDecision(
            STRONG_SEMANTIC_AUTHORITY,
            "SOURCE_KIND_WITHOUT_PROVEN_GROUNDING_FAILS_TO_STRONG",
            normalized,
        )

    if normalized in NOVEL_SEMANTIC_KINDS:
        return SemanticAuthorityDecision(
            STRONG_SEMANTIC_AUTHORITY,
            "NOVEL_SEMANTIC_TASK",
            normalized,
        )

    return SemanticAuthorityDecision(
        STRONG_SEMANTIC_AUTHORITY,
        "UNRECOGNIZED_KIND_FAILS_TO_STRONG",
        normalized,
    )
