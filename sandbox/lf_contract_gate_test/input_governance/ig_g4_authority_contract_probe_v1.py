"""G4 isolated contract probe; no DB IO, no policy engine, no approvals issued.

All authority sources, route policies and receipts MUST be fetched by authorized
readers; the caller cannot use proposed rule/category/origin as an authority.
The two verification callbacks MUST call real canonical receipt/source verifiers
when later integrated. This module itself cannot certify real governance.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable

KEYS = ("rule_ref", "rule_sha256", "selector_sha256", "scope_diff_sha256", "consumer", "operation")


def _has_exact_fields(row: dict[str, Any], request: dict[str, Any]) -> bool:
    return all(bool(request.get(k)) and row.get(k) == request[k] for k in KEYS)


def check_authority_contract(
    request: dict[str, Any],
    trusted_source: dict[str, Any] | None,
    routes: list[dict[str, Any]],
    receipts: list[dict[str, Any]],
    *,
    verify_source: Callable[[dict[str, Any]], bool] | None = None,
    verify_receipt: Callable[[dict[str, Any]], bool] | None = None,
    now: datetime | None = None,
) -> str:
    """Synthetic shape contract, not a runtime admission. Only returns HOLD or PROOF_READY_FOR_TECHNICAL_ADMISSION."""
    now = now or datetime.now(timezone.utc)
    if not isinstance(now, datetime) or now.tzinfo is None:
        return "HOLD_UNTRUSTED_TIME"
    if not isinstance(request, dict) or any(not request.get(k) for k in KEYS):
        return "HOLD_REQUEST_INVALID"
    if not isinstance(trusted_source, dict) or verify_source is None or not verify_source(trusted_source):
        return "HOLD_SOURCE_UNVERIFIED"
    if trusted_source.get("status") != "ACTIVE" or trusted_source.get("revoked") is True:
        return "HOLD_SOURCE_INACTIVE"
    if trusted_source.get("operation") != request["operation"] or not trusted_source.get("source_ref") or not trusted_source.get("source_sha256"):
        return "HOLD_OPERATION_OR_SOURCE_MISMATCH"
    if request["consumer"] not in trusted_source.get("allowed_consumers", []):
        return "HOLD_CONSUMER_NOT_AUTHORIZED"
    if not _has_exact_fields(trusted_source, request):
        return "HOLD_SOURCE_SCOPE_MISMATCH"
    domains = trusted_source.get("required_domains")
    if not isinstance(domains, list) or not domains or any(not isinstance(d, str) or not d for d in domains) or len(domains) != len(set(domains)):
        return "HOLD_AUTHORITY_DOMAINS_UNRESOLVED"
    if any(r.get("veto") is True for r in routes if isinstance(r, dict)):
        return "HOLD_POLICY_VETO"
    if verify_receipt is None:
        return "HOLD_RECEIPT_VERIFIER_MISSING"
    for domain in domains:
        available_routes = [r for r in routes if isinstance(r, dict) and r.get("domain") == domain and r.get("operation") == request["operation"] and r.get("status") == "ACTIVE"]
        if len(available_routes) != 1:
            return "HOLD_ROUTE_NOT_UNIQUE_ACTIVE"
        route = available_routes[0]
        if not route.get("authority_ref") or route.get("revoked") is True:
            return "HOLD_ROUTE_AUTHORITY_INVALID"
        candidates = [r for r in receipts if isinstance(r, dict) and r.get("domain") == domain and r.get("operation") == request["operation"]]
        if len(candidates) != 1:
            return "HOLD_RECEIPT_MISSING_OR_DUPLICATE"
        receipt = candidates[0]
        if receipt.get("status") != "VERIFIED" or receipt.get("revoked") is True:
            return "HOLD_RECEIPT_INACTIVE"
        if receipt.get("authority_ref") != route["authority_ref"] or not _has_exact_fields(receipt, request):
            return "HOLD_RECEIPT_SCOPE_MISMATCH"
        try:
            expires_at = datetime.fromisoformat(receipt["expires_at"].replace("Z", "+00:00"))
            if expires_at.tzinfo is None or expires_at <= now:
                return "HOLD_RECEIPT_EXPIRED"
        except (TypeError, KeyError, ValueError, AttributeError):
            return "HOLD_RECEIPT_EXPIRATION_UNVERIFIED"
        if not verify_receipt(receipt):
            return "HOLD_RECEIPT_PROVENANCE_UNVERIFIED"
    # This is NOT APPROVED/PUBLISHED: requires real source/receipt verification and technical admission.
    return "PROOF_READY_FOR_TECHNICAL_ADMISSION"
