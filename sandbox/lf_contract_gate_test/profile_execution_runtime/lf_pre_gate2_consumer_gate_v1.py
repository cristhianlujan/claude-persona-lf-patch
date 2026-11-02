#!/usr/bin/env python3
"""Consumer-neutral, fail-closed PRE-Gate2 completion check for LF.

This is a shared *consumer* assertion, not a Router, authorization token,
provider attestation, or automatic ChatGPT/Claude runtime hook.
The canonical execution/readback is always the authority for effects.
"""
import json
import re
import sys

MODES = frozenset(("GPT_NATIVE", "CLAUDE_NATIVE"))
BLOCKERS = (
    "BLOCK_SCOPE_SEMANTICS_UNATTESTED",
    "BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED",
)
GATE2 = "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION"
ADVISORY = "PROPOSE_ONLY_OPEN"
ROUTER_REQUEST = re.compile(r"\b(?:router|ACT-0001)\b", re.I)
AUTHORITY_CLAIM = re.compile(
    r"\b(?:vigente|activad[ao]|aplicad[ao]|persistid[ao]|"
    r"integrad[ao]|desplegad[ao])\b", re.I)
DENIAL = re.compile(
    r"\b(?:TOOL_ACCESS_DENIED|CONNECTOR_DENIED|PROVIDER_BLOCKED|"
    r"PERMISSION_DENIED|ERROR_HTTP_[45]\d\d)\b", re.I)
FALSE_CLOSE = re.compile(
    r"\b(?:COMPLETED|READY|PASS)\b|100\s*%|"
    r"\b(?:definici[oó]n|regla|pol[ií]tica)\s+"
    r"(?:(?:can[oó]nica|oficial)\s+)?"
    r"(?:creada|registrada|publicada|completada|finalizada)\b", re.I)


def evaluate(payload):
    """Classify PRE-Gate2 continuation for either native consumer.

    Evidence is untrusted tool-result text. ALLOW_TRUTHFUL_BLOCK means only
    that an accurate non-execution report can be emitted; it never grants
    authority to complete an operation or persist an official artifact.
    """
    if not isinstance(payload, dict) or payload.get("consumer_mode") not in MODES:
        return {"decision": "BLOCK", "reason_code": "CONSUMER_MODE_INVALID",
                "canonical_effect_allowed": False}
    request = payload.get("request_text")
    receipts = payload.get("tool_receipts")
    final = payload.get("final_text")
    if not all(isinstance(v, str) for v in (request, receipts, final)):
        return {"decision": "BLOCK", "reason_code": "EVIDENCE_INPUT_INVALID",
                "canonical_effect_allowed": False}
    if not request.strip():
        return {"decision": "BLOCK", "reason_code": "REQUEST_MISSING",
                "canonical_effect_allowed": False}

    # If the consumer already got an actual Gate2, leave the terminal
    # completeness test to the *existing* same-run, 11/11 authority gate.
    if GATE2 in receipts:
        return {"decision": "DEFER_TO_GATE2_RECEIPT_GUARD",
                "reason_code": "GATE2_RECEIPT_REQUIRED",
                "canonical_effect_allowed": False}

    blocker = next((code for code in BLOCKERS if code in receipts), None)
    truthful_without_effect = (
        "NOT_EXECUTED" in final and "NO_CANONICAL_EFFECT" in final
        and not (FALSE_CLOSE.search(final) or AUTHORITY_CLAIM.search(final))
    )
    if not blocker:
        # Explicit Router requests must not be marked complete just because
        # Router evidence never arrived (or an advisory reply lacks a Router
        # receipt). This is a consumer assertion, not server attestation.
        if ROUTER_REQUEST.search(request) and (
            not receipts.strip() or ADVISORY in receipts
        ):
            if truthful_without_effect:
                return {"decision": "ALLOW_TRUTHFUL_BLOCK",
                        "reason_code": "ROUTER_RECEIPT_UNAVAILABLE_NOT_EXECUTED",
                        "canonical_effect_allowed": False}
            return {"decision": "BLOCK",
                    "reason_code": "ROUTER_RECEIPT_MISSING",
                    "canonical_effect_allowed": False}
        return {"decision": "NOT_APPLICABLE",
                "reason_code": "NO_PRE_GATE2_ROUTER_BLOCK_OBSERVED",
                "canonical_effect_allowed": False}

    # With a blocked Router, only an explicit no-effect status or an observed
    # provider denial can be reported. Never imply a governed execution.
    if FALSE_CLOSE.search(final) or AUTHORITY_CLAIM.search(final):
        return {"decision": "BLOCK", "reason_code": "PRE_GATE2_FALSE_COMPLETION",
                "router_blocking_code": blocker, "canonical_effect_allowed": False}
    if blocker in final and truthful_without_effect:
        return {"decision": "ALLOW_TRUTHFUL_BLOCK",
                "reason_code": "PRE_GATE2_BLOCK_EXPLICITLY_REPORTED",
                "router_blocking_code": blocker, "canonical_effect_allowed": False}
    if (DENIAL.search(final) and "NOT_EXECUTED" in final
            and DENIAL.search(receipts)):
        return {"decision": "ALLOW_TRUTHFUL_BLOCK",
                "reason_code": "PROVIDER_DENIAL_OBSERVED",
                "router_blocking_code": blocker, "canonical_effect_allowed": False}
    return {"decision": "BLOCK", "reason_code": "PRE_GATE2_ROUTE_CONTINUITY_BLOCK",
            "router_blocking_code": blocker, "canonical_effect_allowed": False}


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        payload = None
    result = evaluate(payload)
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    # Exit 0 is reserved for a truthful no-effect report. Defer/unknown
    # states are NOT success and must be handled by the owning receipt gate.
    return {
        "BLOCK": 2,
        "ALLOW_TRUTHFUL_BLOCK": 0,
        "DEFER_TO_GATE2_RECEIPT_GUARD": 3,
        "NOT_APPLICABLE": 4,
    }[result["decision"]]


if __name__ == "__main__":
    sys.exit(main())
