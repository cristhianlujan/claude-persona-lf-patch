"""Generic fail-closed validation for Router-bound aggregate source attestations.

The caller MUST obtain both receipt and expected digests independently from governed
Router/currentness authority. User/model supplied claims are never authority.
PRE_INFERENCE proves materialization only; POST_INFERENCE proves actual consumption.
No adapter registration or runtime activation is performed by this module.
"""
from __future__ import annotations

import re
from collections.abc import Mapping

HEX64 = re.compile(r"^[0-9a-f]{64}$")
PHASES = frozenset({"PRE_INFERENCE", "POST_INFERENCE"})


class SourceReceiptError(ValueError):
    pass


def validate_aggregate_receipt(
    receipt: object, expected: Mapping[str, str], *, phase: str = "PRE_INFERENCE"
) -> bool:
    """Validate a governed aggregate receipt; this does not establish its provenance."""
    if phase not in PHASES:
        raise SourceReceiptError("RECEIPT_PHASE_INVALID")
    if (
        not isinstance(receipt, dict)
        or not isinstance(expected, Mapping)
        or not expected
        or any(not isinstance(k, str) or not k.strip() for k in expected)
    ):
        raise SourceReceiptError("RECEIPT_CONTRACT_INVALID")
    if receipt.get("schema") != "lf-governed-aggregate-source-receipt/v1":
        raise SourceReceiptError("RECEIPT_SCHEMA_INVALID")
    if receipt.get("authority") != "CURRENTNESS_AUTHORITY@1.0.0":
        raise SourceReceiptError("RECEIPT_AUTHORITY_INVALID")
    if receipt.get("current_release_verified") is not True:
        raise SourceReceiptError("RECEIPT_NOT_CURRENT")
    if receipt.get("router_materialization_verified") is not True:
        raise SourceReceiptError("RECEIPT_NOT_MATERIALIZED")
    if not isinstance(receipt.get("router_binding"), str) or not receipt["router_binding"].strip():
        raise SourceReceiptError("RECEIPT_ROUTER_BINDING_MISSING")
    digests = receipt.get("stage_sha256")
    if not isinstance(digests, dict) or set(digests) != set(expected):
        raise SourceReceiptError("RECEIPT_STAGE_COVERAGE_INVALID")
    for stage, wanted in expected.items():
        actual = digests[stage]
        if not isinstance(wanted, str) or not HEX64.fullmatch(wanted):
            raise SourceReceiptError("EXPECTED_DIGEST_INVALID")
        if not isinstance(actual, str) or not HEX64.fullmatch(actual):
            raise SourceReceiptError("RECEIPT_DIGEST_INVALID")
        if actual != wanted:
            raise SourceReceiptError("RECEIPT_DIGEST_MISMATCH")
    if phase == "PRE_INFERENCE":
        if receipt.get("runtime_consumption_verified") is True:
            raise SourceReceiptError("RECEIPT_PREMATURE_CONSUMPTION_CLAIM")
    else:
        if receipt.get("runtime_consumption_verified") is not True:
            raise SourceReceiptError("RECEIPT_NOT_CONSUMED")
        if not isinstance(receipt.get("execution_receipt_ref"), str) or not receipt["execution_receipt_ref"].strip():
            raise SourceReceiptError("RECEIPT_EXECUTION_EVIDENCE_MISSING")
        if not isinstance(receipt.get("model_request_sha256"), str) or not HEX64.fullmatch(receipt["model_request_sha256"]):
            raise SourceReceiptError("RECEIPT_MODEL_REQUEST_DIGEST_INVALID")
    return True
