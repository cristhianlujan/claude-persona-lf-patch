"""Candidate-only LF product decision proof. NOT an authorization service.

Inputs MUST come from already verified governed business sources; this pure helper
does not authenticate signatures, attest sources, query data or grant writes.
"""
from datetime import datetime, timezone
from re import fullmatch


def _utc(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if result.tzinfo is None:
        return None
    return result.astimezone(timezone.utc)


def check_bounded_offer_mandate(mandate, offer, *, current_owner, at):
    """Check exact covered obligation/offer/version/owner/signed terms for a proposal.

    Return ELIGIBLE_FOR_SCOPED_PRESENTATION_IN_MODEL only for a complete match,
    never an executable backend approval.
    """
    errors = []
    if not isinstance(mandate, dict) or not isinstance(offer, dict):
        return {"decision": "BLOCK", "blocking_codes": ["INPUT_INVALID"], "backend_authorized": False}
    now = _utc(at)
    start, end = _utc(mandate.get("valid_from")), _utc(mandate.get("valid_until"))
    if now is None or start is None or end is None or not start <= now <= end:
        errors.append("MANDATE_TIME_INVALID")
    if mandate.get("active") is not True or mandate.get("verification_state") != "VERIFIED" \
            or not isinstance(mandate.get("verification_receipt_ref"), str) \
            or not mandate["verification_receipt_ref"].strip():
        errors.append("MANDATE_UNVERIFIED_OR_INACTIVE")
    if offer.get("eligible") is not True or offer.get("available") is not True \
            or offer.get("matched") is not True:
        errors.append("OFFER_NOT_READY")
    for key, code in (
        ("obligation_id", "OBLIGATION_OUTSIDE_SCOPE"),
        ("offer_id", "OFFER_OUTSIDE_SCOPE"),
        ("offer_version", "VERSION_OUTSIDE_SCOPE"),
    ):
        m, o = mandate.get(key), offer.get(key)
        if not isinstance(m, str) or not m.strip() or not isinstance(o, str) or not o.strip() or m != o:
            errors.append(code)
    m_owner = mandate.get("owner_id")
    o_owner = offer.get("owner_id")
    if not isinstance(current_owner, str) or not current_owner.strip() \
            or not isinstance(m_owner, str) or not m_owner.strip() \
            or not isinstance(o_owner, str) or not o_owner.strip() \
            or m_owner != current_owner or o_owner != current_owner:
        errors.append("CURRENT_OWNER_SCOPE_MISMATCH")
    m_terms, o_terms = mandate.get("signed_terms_sha256"), offer.get("terms_sha256")
    if not isinstance(m_terms, str) or not fullmatch("[0-9a-f]{64}", m_terms) \
            or not isinstance(o_terms, str) or not fullmatch("[0-9a-f]{64}", o_terms) \
            or m_terms != o_terms:
        errors.append("SIGNED_TERMS_MISMATCH_OR_UNKNOWN")
    if errors:
        return {"decision": "BLOCK", "blocking_codes": errors, "backend_authorized": False}
    return {
        "decision": "ELIGIBLE_FOR_SCOPED_PRESENTATION_IN_MODEL",
        "blocking_codes": [],
        "scope": {key: offer[key] for key in ("obligation_id", "offer_id", "offer_version")},
        "backend_authorized": False,
    }