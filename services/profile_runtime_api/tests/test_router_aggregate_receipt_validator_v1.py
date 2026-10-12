"""Fail-closed reusable validation of an aggregate Router source receipt.

Source-only candidate: no Router binding or production activation.
"""
from __future__ import annotations

import re
from collections.abc import Mapping

HEX64 = re.compile(r"^[0-9a-f]{64}$")
STAGES = tuple(f"A{i}" for i in range(1, 10))


class SourceReceiptError(ValueError):
    pass


def validate_aggregate_receipt(receipt: object, expected: Mapping[str, str]) -> bool:
    """Require nine exact source digests and an externally attested current release."""
    if not isinstance(receipt, dict) or set(expected) != set(STAGES):
        raise SourceReceiptError("RECEIPT_CONTRACT_INVALID")
    if receipt.get("authority") != "CURRENTNESS_AUTHORITY@1.0.0":
        raise SourceReceiptError("RECEIPT_AUTHORITY_INVALID")
    if receipt.get("current_release_verified") is not True:
        raise SourceReceiptError("RECEIPT_NOT_CURRENT")
    if receipt.get("runtime_consumption_verified") is not True:
        raise SourceReceiptError("RECEIPT_NOT_CONSUMED")
    if not isinstance(receipt.get("router_binding"), str) or not receipt["router_binding"].strip():
        raise SourceReceiptError("RECEIPT_ROUTER_BINDING_MISSING")
    digests = receipt.get("stage_sha256")
    if not isinstance(digests, dict) or set(digests) != set(STAGES):
        raise SourceReceiptError("RECEIPT_STAGE_COVERAGE_INVALID")
    for stage in STAGES:
        actual, wanted = digests[stage], expected[stage]
        if not isinstance(wanted, str) or not HEX64.fullmatch(wanted):
            raise SourceReceiptError("EXPECTED_DIGEST_INVALID")
        if not isinstance(actual, str) or not HEX64.fullmatch(actual):
            raise SourceReceiptError("RECEIPT_DIGEST_INVALID")
        if actual != wanted:
            raise SourceReceiptError("RECEIPT_DIGEST_MISMATCH")
    return True
