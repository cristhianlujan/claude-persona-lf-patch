#!/usr/bin/env python3
"""ACT-0001 semantic handoff verifier. Not a Router, LLM caller, or write gate.

This validates integrity and shape of a candidate decision from a separately
governed semantic consumer. A well-shaped proposal is still NOT an attested
execution authority or permission to modify a repository or database.
"""
from __future__ import annotations

from collections.abc import Mapping
from hashlib import sha256
from typing import Any

SCHEMA = "LF_ROUTER_INTENT_HANDOFF_V1"


def _sha(value: str) -> str:
    return sha256(value.encode("utf-8")).hexdigest()


def _blocked(code: str) -> dict[str, Any]:
    return {
        "status": "BLOCKED",
        "blocking_code": code,
        "scope_binding_state": "UNATTESTED",
        "downstream_execution_allowed": False,
        "execution_receipt": None,
    }


def _identity(candidate: Mapping[str, Any]) -> str | None:
    """Normalize only explicit canonical refs; NEVER use words as identity."""
    if candidate.get("artifact_ref"):
        ref = candidate["artifact_ref"]
        return ref if isinstance(ref, str) and ":" in ref else None
    code = candidate.get("asset_code") or candidate.get("screen_code")
    return code if isinstance(code, str) and len(code) >= 5 else None


def validate_semantic_handoff(
    input_literal: str,
    router_receipt: Mapping[str, Any],
    proposal: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Bind verbatim request + exact subjects, then validate a consumer proposal.

    Everything below remains advisory; only a separate governed admission
    consuming independent, current semantic + target/executor attestation may
    authorize downstream effects. This module cannot issue such a receipt.
    """
    if not isinstance(input_literal, str) or not input_literal.strip():
        return _blocked("BLOCK_EMPTY_REQUEST")
    if not isinstance(router_receipt, Mapping):
        return _blocked("BLOCK_ROUTER_RECEIPT_MISSING")
    digest = _sha(input_literal)
    if not (
        router_receipt.get("router") == "ACT-0001"
        and router_receipt.get("source") == "SUPABASE"
        and router_receipt.get("status") == "BLOCKED"
        and router_receipt.get("downstream_execution_allowed") is False
        and router_receipt.get("request_sha256") == digest
    ):
        return _blocked("BLOCK_ROUTER_OR_LITERAL_DRIFT")

    handoff = router_receipt.get("semantic_handoff")
    if not isinstance(handoff, Mapping) or not (
        handoff.get("schema_version") == SCHEMA
        and handoff.get("literal_request") == input_literal
        and handoff.get("request_sha256") == digest
        and handoff.get("downstream_execution_allowed") is False
        and handoff.get("scope_binding_state") == "UNATTESTED"
        and handoff.get("semantic_consumer_receipt") is None
        and handoff.get("executor_binding_state") == "NOT_SELECTED"
    ):
        return _blocked("BLOCK_SEMANTIC_HANDOFF_DRIFT")

    refs = handoff.get("candidate_subjects")
    if not isinstance(refs, list) or len(refs) > 50:
        return _blocked("BLOCK_CANONICAL_CANDIDATE_LIST_INVALID")
    mapped: dict[str, Mapping[str, Any]] = {}
    for candidate in refs:
        if not isinstance(candidate, Mapping):
            return _blocked("BLOCK_CANONICAL_CANDIDATE_INVALID")
        ref = _identity(candidate)
        if ref is None or ref in mapped:
            return _blocked("BLOCK_CANONICAL_CANDIDATE_INVALID")
        # Full file paths must be part of the literal request. A canonical asset
        # may be referred to by an alias and needs independent catalog readback.
        if candidate.get("artifact_ref"):
            path = ref.split(":", 1)[1]
            if not path or path.casefold() not in input_literal.casefold():
                return _blocked("BLOCK_ARTIFACT_LITERAL_MISMATCH")
        mapped[ref] = candidate

    result = {
        "status": "ADVISORY_ONLY",
        "schema_version": "LF_ROUTER_SEMANTIC_PROPOSAL_REVIEW_V1",
        "request_sha256": digest,
        "literal_request": input_literal,
        "canonical_subject_refs": sorted(mapped),
        "candidate_count": len(mapped),
        "scope_binding_state": "UNATTESTED",
        "consumer_attestation": None,
        "executor_selected": None,
        "current_catalog_readback": None,
        "downstream_execution_allowed": False,
        "execution_receipt": None,
    }

    if proposal is None:
        result["next"] = "GOVERNED_SEMANTIC_CONSUMER_RESOLUTION"
        return result
    if not isinstance(proposal, Mapping) or (
        proposal.get("request_sha256") != digest
    ):
        return _blocked("BLOCK_SEMANTIC_PROPOSAL_REQUEST_DRIFT")

    positives = proposal.get("positive_target_refs")
    exclusions = proposal.get("excluded_target_refs")
    forbidden = proposal.get("forbidden_scope")
    objective = proposal.get("objective")
    if not (
        isinstance(positives, list)
        and isinstance(exclusions, list)
        and all(isinstance(x, str) for x in positives + exclusions)
        and len(set(positives)) == len(positives)
        and len(set(exclusions)) == len(exclusions)
        and isinstance(objective, str) and objective.strip()
        and isinstance(forbidden, list)
        and all(isinstance(x, str) and x.strip() for x in forbidden)
    ):
        return _blocked("BLOCK_SEMANTIC_PROPOSAL_INCOMPLETE")
    positive, excluded = set(positives), set(exclusions)
    if positive & excluded:
        return _blocked("BLOCK_POSITIVE_EXCLUDED_SCOPE_OVERLAP")
    if not (positive | excluded).issubset(mapped.keys()):
        return _blocked("BLOCK_PROPOSED_TARGET_NOT_IN_CANON")
    if len(mapped) > 1 and positive | excluded != mapped.keys():
        return _blocked("BLOCK_CANDIDATE_ROLES_UNRESOLVED")
    if not positive:
        return _blocked("BLOCK_POSITIVE_TARGET_MISSING")

    # Do not grant authority from the consumer's own claim of being trusted.
    result.update({
        "status": "REVIEW_REQUIRED",
        "scope_binding_state": "CANDIDATE_UNATTESTED",
        "proposed_positive_target_refs": sorted(positive),
        "proposed_excluded_target_refs": sorted(excluded),
        "proposed_forbidden_scope": forbidden,
        "proposed_objective": objective,
        "next": "INDEPENDENT_SEMANTIC_AND_PREWRITE_AUTHORITY_VALIDATION",
    })
    return result
