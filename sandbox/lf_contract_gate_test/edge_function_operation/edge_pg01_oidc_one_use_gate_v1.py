#!/usr/bin/env python3
"""Fail-closed testable acceptance of an external one-use deploy receipt.

The receipt is not created or consumed here. Only a separate governed issuer
with an atomic consume store may provide the evidence used by this gate.
"""
import re

SHA = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
SLUG = "lf-pg01-oidc-authority-v1"
SCHEMA = "LF_PG01_EDGE_DEPLOY_CONSUMPTION_V1"


def qualify(receipt, *, main_sha, source_sha256, operation_id):
    if not isinstance(receipt, dict):
        return "CONSUMPTION_RECEIPT_MISSING"
    if not isinstance(main_sha, str) or not SHA.fullmatch(main_sha):
        return "MAIN_SHA_INVALID"
    if not isinstance(source_sha256, str) or not DIGEST.fullmatch(source_sha256):
        return "SOURCE_DIGEST_INVALID"
    if not isinstance(operation_id, str) or not operation_id.strip():
        return "OPERATION_ID_INVALID"
    if receipt.get("schema_version") != SCHEMA or receipt.get("decision") != "CONSUMED" or receipt.get("ready") is not True:
        return "CONSUMPTION_AUTHORITY_UNVERIFIED"
    # Fields must originate from a separately authenticated authority. A local
    # JSON file / workflow output is not sufficient to establish authenticity.
    if receipt.get("authority_layer") != "INDEPENDENT_ATOMIC_CONSUMER":
        return "CONSUMPTION_AUTHORITY_UNVERIFIED"
    if receipt.get("target_slug") != SLUG or receipt.get("main_sha") != main_sha:
        return "CONSUMPTION_CONTEXT_MISMATCH"
    if receipt.get("source_sha256") != source_sha256 or receipt.get("consumer_execution_id") != operation_id:
        return "CONSUMPTION_CONTEXT_MISMATCH"
    if receipt.get("max_uses") != 1 or receipt.get("uses_count") != 1 or receipt.get("active") is not False:
        return "CONSUMPTION_NOT_EXHAUSTED"
    return None
