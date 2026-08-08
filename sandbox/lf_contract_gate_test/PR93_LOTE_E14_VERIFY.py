#!/usr/bin/env python3
"""Authoritative verifier for PR #93 LOTE-E.14 evidence bundles."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from PR93_LOTE_E14_VERIFY_COMMON import (
    HEAD_RE,
    RECEIPT_FILENAME,
    SCHEMA_VERSION,
    SHA256_RE,
    canonical_json_bytes,
    fail,
    sha256_bytes,
    verify_bundle_inventory,
    verify_evidence,
    verify_sources,
)
from PR93_LOTE_E14_VERIFY_TRANSCRIPT import verify_transcript

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    if SHA256_RE.fullmatch(args.trusted_receipt_sha256) is None:
        fail("trusted receipt digest must be 64 lowercase hexadecimal characters")

    # CA-N137: the unresolved argument is validated before canonicalisation.
    bundle_dir = verify_bundle_inventory(args.bundle_dir)
    receipt_path = (args.receipt or bundle_dir / RECEIPT_FILENAME).resolve()
    if receipt_path.parent != bundle_dir:
        fail("receipt must be inside bundle directory")
    if receipt_path.name != RECEIPT_FILENAME:
        fail(f"receipt must be named {RECEIPT_FILENAME}")
    receipt_bytes = receipt_path.read_bytes()
    observed_receipt_sha = sha256_bytes(receipt_bytes)
    if observed_receipt_sha != args.trusted_receipt_sha256:
        fail("receipt does not match externally trusted digest")

    try:
        receipt = json.loads(receipt_bytes.decode("utf-8", "strict"))
    except json.JSONDecodeError as exc:
        raise ValueError("receipt JSON is invalid") from exc
    if receipt_bytes != canonical_json_bytes(receipt):
        fail("receipt JSON is not canonical")
    if receipt.get("schema_version") != SCHEMA_VERSION:
        fail("unsupported receipt schema")
    if receipt.get("governance_contract_version") != "PR93_E15_V1":
        fail("missing E.15 governance contract")
    head_sha = receipt.get("head_sha")
    if not isinstance(head_sha, str) or HEAD_RE.fullmatch(head_sha) is None:
        fail("invalid head SHA in receipt")

    connectivity = receipt.get("connectivity_preflight")
    if not isinstance(connectivity, dict):
        fail("missing connectivity preflight")
    if connectivity.get("passed") is not True:
        fail("connectivity preflight did not pass")
    if connectivity.get("exit_code") != 0:
        fail("connectivity preflight exit code is not zero")
    if connectivity.get("output_was_exact_select_one") is not True:
        fail("connectivity preflight output was not exact")
    if connectivity.get("completed_before_output_directory_creation") is not True:
        fail("connectivity preflight was not completed before output creation")

    invariants = receipt.get("capture_invariants", {})
    required_true = (
        "receipt_requires_external_trust_anchor",
        "output_directory_created_exclusively",
        "receipt_written_once_exclusively",
        "legacy_entrypoints_fail_closed",
        "database_url_not_persisted",
    )
    if any(invariants.get(key) is not True for key in required_true):
        fail("capture invariants are incomplete")

    verify_sources(receipt, args.repo_root.resolve())
    loaded = verify_evidence(receipt, bundle_dir)
    verify_transcript(receipt, loaded)

    print("PASS_E14_RECEIPT_VERIFIED")
    print(f"HEAD_SHA={head_sha}")
    print(f"RECEIPT_SHA256={observed_receipt_sha}")
    print(f"OVERALL_STATUS={receipt.get('overall_status')}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        print(f"FAIL_E14_RECEIPT_VERIFICATION={exc}", file=sys.stderr)
        raise SystemExit(2)
