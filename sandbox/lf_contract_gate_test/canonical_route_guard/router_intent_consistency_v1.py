#!/usr/bin/env python3
"""Deterministic consistency gate for ACT-0001, NOT a classifier or a router.

A governed semantic capability proposes an intent; this guard checks its
source binding against the canonical catalog and the actual ACT-0001 result.
It NEVER promotes model output to authority and NEVER permits effects itself.
"""
from __future__ import annotations

import hashlib
import json
import unicodedata
from typing import Any, Callable, Mapping


CONTRACT = "LF_ROUTER_INTENT_PROPOSAL_V1"


def _canon(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _words(value: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", value.casefold())
    normalized = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    return normalized.replace("-", " ").split()


def _is_in(original: str, quote: str) -> bool:
    return bool(quote and quote in original)


def _overlaps(first: str, second: str) -> bool:
    first, second = first.upper(), second.upper()
    return first == second or first.startswith(second + ".") or second.startswith(first + ".")


def check(
    request_text: str,
    proposal: Mapping[str, Any] | None,
    actual_router_response: Mapping[str, Any] | None,
    catalog: Mapping[str, Any] | None,
    *,
    verify_semantic_receipt: Callable[[str, Mapping[str, Any]], bool] | None = None,
) -> dict[str, Any]:
    """Validate; caller owns the trusted receipt verifier and catalog readback.

    A fake model PASS field in proposal has no value. The verifier is injected
    by the governed consumer, never extracted from proposal itself.
    """
    def blocked(code: str) -> dict[str, Any]:
        return {
            "status": "BLOCKED",
            "blocking_code": code,
            "downstream_execution_allowed": False,
            "effects_executed": False,
        }

    if not isinstance(request_text, str) or not request_text.strip():
        return blocked("BLOCK_EMPTY_REQUEST")
    if not isinstance(proposal, Mapping):
        return blocked("BLOCK_SEMANTIC_INTENT_MISSING")
    if proposal.get("schema_version") != CONTRACT:
        return blocked("BLOCK_SEMANTIC_INTENT_CONTRACT")
    if proposal.get("request_sha256") != _sha(request_text):
        return blocked("BLOCK_SEMANTIC_INTENT_SOURCE_DRIFT")
    if proposal.get("semantic_state") != "RESOLVED":
        return blocked("BLOCK_SEMANTIC_INTENT_UNRESOLVED")
    if not isinstance(catalog, Mapping) or not catalog.get("revision_sha256"):
        return blocked("BLOCK_CATALOG_CURRENTNESS_MISSING")
    if proposal.get("catalog_revision_sha256") != catalog.get("revision_sha256"):
        return blocked("BLOCK_CATALOG_CURRENTNESS_DRIFT")
    if verify_semantic_receipt is None:
        return blocked("BLOCK_TRUSTED_SEMANTIC_ASSURANCE_MISSING")
    try:
        verified = verify_semantic_receipt(_sha(_canon(proposal)), proposal)
    except Exception:
        verified = False
    if verified is not True:
        return blocked("BLOCK_TRUSTED_SEMANTIC_ASSURANCE_FAILED")

    target_type = proposal.get("target_type")
    target_code = proposal.get("target_code")
    action_code = proposal.get("action_code")
    evidence = proposal.get("evidence")
    allow = proposal.get("allowed_scopes")
    deny = proposal.get("denied_scopes")
    if not all(isinstance(x, str) and x.strip() for x in (target_type, target_code, action_code)):
        return blocked("BLOCK_SEMANTIC_TARGET_OR_ACTION_MISSING")
    if not isinstance(evidence, Mapping) or not all(
        isinstance(evidence.get(key), str) and _is_in(request_text, evidence[key])
        for key in ("target_quote", "action_quote", "allow_quote")
    ):
        return blocked("BLOCK_SEMANTIC_EVIDENCE_UNGROUNDED")
    if not isinstance(allow, list) or not allow or not isinstance(deny, list):
        return blocked("BLOCK_SCOPE_CONTRACT_INVALID")
    if any(not isinstance(x, str) or not x.strip() for x in allow + deny):
        return blocked("BLOCK_SCOPE_CONTRACT_INVALID")
    if deny and not _is_in(request_text, evidence.get("deny_quote", "")):
        return blocked("BLOCK_NEGATED_SCOPE_EVIDENCE_UNGROUNDED")
    if any(_overlaps(a, b) for a in allow for b in deny):
        return blocked("BLOCK_SCOPE_CONTRADICTION")

    aliases_map = catalog.get("type_aliases")
    if not isinstance(aliases_map, Mapping):
        return blocked("BLOCK_CATALOG_TYPE_ALIASES_INVALID")
    type_aliases = aliases_map.get(target_type, [])
    if not isinstance(type_aliases, list) or not any(
        isinstance(alias, str) and _words(alias)
        and all(word in _words(evidence["target_quote"]) for word in _words(alias))
        for alias in type_aliases
    ):
        return blocked("BLOCK_SEMANTIC_TARGET_TYPE_UNGROUNDED")

    if not isinstance(actual_router_response, Mapping):
        return blocked("BLOCK_ROUTER_RECEIPT_MISSING")
    if actual_router_response.get("status") != "READY_TO_EXECUTE":
        return blocked("BLOCK_ROUTER_NOT_READY")
    if actual_router_response.get("asset_type") != target_type:
        return blocked("BLOCK_ROUTER_SEMANTIC_TYPE_MISMATCH")
    if actual_router_response.get("action_code") != action_code:
        return blocked("BLOCK_ROUTER_SEMANTIC_ACTION_MISMATCH")

    assets = catalog.get("assets") or {}
    if not isinstance(assets, Mapping) or target_code not in assets:
        return blocked("BLOCK_CANONICAL_TARGET_NOT_REGISTERED")
    asset = assets[target_code]
    if not isinstance(asset, Mapping) or asset.get("type") != target_type or asset.get("active") is not True:
        return blocked("BLOCK_CANONICAL_TARGET_NOT_ACTIVE")
    router_asset = actual_router_response.get("asset")
    if not isinstance(router_asset, Mapping):
        return blocked("BLOCK_ROUTER_TARGET_RECEIPT_INVALID")
    if router_asset.get("codigo_activo") != target_code:
        return blocked("BLOCK_ROUTER_SEMANTIC_TARGET_MISMATCH")

    routes = catalog.get("active_routes")
    if not isinstance(routes, list):
        return blocked("BLOCK_CANONICAL_ROUTE_REGISTRY_MISSING")
    matches = [
        row for row in routes
        if isinstance(row, Mapping) and row.get("asset_type") == target_type
        and row.get("action_code") == action_code and row.get("active") is True
    ]
    if not matches:
        return blocked("BLOCK_CANONICAL_OPERATION_NOT_REGISTERED")
    if len(matches) != 1 or not isinstance(matches[0].get("operation_code"), str):
        return blocked("BLOCK_CANONICAL_OPERATION_AMBIGUOUS")
    operation = matches[0]["operation_code"]
    if operation != actual_router_response.get("operation_code"):
        return blocked("BLOCK_ROUTER_OPERATION_MISMATCH")

    effects = actual_router_response.get("declared_effect_scopes")
    if not isinstance(effects, list) or not effects:
        return blocked("BLOCK_ROUTER_EFFECT_SCOPE_UNDECLARED")
    if any(not isinstance(effect, str) for effect in effects):
        return blocked("BLOCK_ROUTER_EFFECT_SCOPE_INVALID")
    if any(_overlaps(effect, forbidden) for effect in effects for forbidden in deny):
        return blocked("BLOCK_ROUTER_FORBIDDEN_EFFECT")
    if any(not any(effect == permitted or effect.startswith(permitted + ".") for permitted in allow) for effect in effects):
        return blocked("BLOCK_ROUTER_EFFECT_OUT_OF_SCOPE")

    return {
        "status": "ROUTE_CONSISTENCY_PASS",
        "operation_code": operation,
        "target_code": target_code,
        "downstream_execution_allowed": False,
        "effects_executed": False,
        "next": "DEFER_TO_CANONICAL_OPERATION_CONTRACT",
    }
