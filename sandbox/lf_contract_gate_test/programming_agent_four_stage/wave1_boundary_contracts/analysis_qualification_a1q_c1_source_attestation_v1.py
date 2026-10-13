#!/usr/bin/env python3
"""A1Q_C1 source-attestation adapter (mechanics only, source-level).

Scope: verifies a candidate A1Q_C1 source receipt against the current bytes of
analysis_request_context_v1.schema.json, the current main SHA and the subject.
It does NOT move any checkpoint, emit a governed receipt or claim operational PASS.
A receipt produced by this script itself is self-attested and never qualifies
A1Q_C1: the governed runtime must emit the verified readback receipt.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE = HERE / "analysis_request_context_v1.schema.json"
SUBJECT = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A1Q/A1Q_C1"
REQUIRED = ("source_ref", "resolved_main_sha", "actual_sha256",
            "current_capability_binding", "readback_receipt_id",
            "source_attestation_verified")

sys.path.insert(0, str(HERE))
import validate_wave1_boundary_contracts_v1 as wave1  # noqa: E402

REFERENCE_CONTEXT = {
    "schema_version": "REQUEST_CONTEXT_V1",
    "request_identity": {"request_ref": "REQ-001", "request_kind": "USER_REQUEST"},
    "objective": {"problem_statement": "problem", "desired_outcome": "outcome"},
    "target_hints": [], "source_refs": [], "provided_facts": [], "constraints": [],
    "ambiguities": [{"code": "AMB-1", "statement": "unclear scope",
                     "materiality": "MATERIAL", "resolution_state": "OPEN"}],
    "no_solution_inferred": True,
}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def attest(receipt, live_main_sha: str, source: Path = SOURCE) -> str:
    """Return PASS_SOURCE_ATTESTATION_MECHANICS or BLOCK:<code>. Fail closed."""
    if not receipt:
        return "BLOCK:MISSING_RECEIPT"
    if receipt.get("subject_ref") != SUBJECT:
        return "BLOCK:CROSS_SUBJECT"
    for key in REQUIRED:
        if receipt.get(key) in (None, "", [], False):
            return "BLOCK:SYNTHETIC_OR_INCOMPLETE:" + key
    if receipt["resolved_main_sha"] != live_main_sha:
        return "BLOCK:STALE_MAIN"
    if sha256_file(source) != receipt["actual_sha256"]:
        return "BLOCK:SOURCE_DRIFT"
    try:
        wave1.validate_request_context(copy.deepcopy(REFERENCE_CONTEXT))
    except Exception as exc:  # structural validator must accept the reference
        return "BLOCK:STRUCTURE:" + str(exc)
    return "PASS_SOURCE_ATTESTATION_MECHANICS"


def candidate_receipt(main_sha: str, source: Path = SOURCE) -> dict:
    return {"subject_ref": SUBJECT, "source_ref": str(source.relative_to(REPO)),
            "resolved_main_sha": main_sha, "actual_sha256": sha256_file(source),
            "current_capability_binding": ["CURRENTNESS_AUTHORITY@1.0.0",
                                           "SOURCE_RESOLUTION_POLICY@1.4.0"],
            "readback_receipt_id": "SELF_ATTESTED_NOT_GOVERNED",
            "source_attestation_verified": True}


def selftest(main_sha: str) -> None:
    receipt = candidate_receipt(main_sha)
    assert attest(receipt, main_sha) == "PASS_SOURCE_ATTESTATION_MECHANICS"
    negatives = {
        "missing_receipt": ("MISSING_RECEIPT", attest(None, main_sha)),
        "stale_main": ("STALE_MAIN", attest(receipt, "0" * 40)),
        "source_drift": ("SOURCE_DRIFT", attest(dict(receipt, actual_sha256="0" * 64), main_sha)),
        "different_subject": ("CROSS_SUBJECT", attest(
            dict(receipt, subject_ref=SUBJECT.replace("C1", "C2")), main_sha)),
        "synthetic_no_readback_id": ("SYNTHETIC_OR_INCOMPLETE", attest(
            dict(receipt, readback_receipt_id=""), main_sha)),
        "synthetic_unverified_flag": ("SYNTHETIC_OR_INCOMPLETE", attest(
            dict(receipt, source_attestation_verified=False), main_sha)),
    }
    for name, (code, verdict) in negatives.items():
        assert verdict.startswith("BLOCK:" + code), (name, code, verdict)
    bad = copy.deepcopy(REFERENCE_CONTEXT)
    bad["no_solution_inferred"] = False
    try:
        wave1.validate_request_context(bad)
    except wave1.ContractError as exc:
        assert str(exc) == "REQUEST_CONTEXT_SOLUTION_INFERENCE"
    else:
        raise AssertionError("structure accepted inferred solution")
    print("PASS_A1Q_C1_SOURCE_MECHANICS_ONLY positives=1 negatives=%d "
          "structural_negatives=1 governed_receipts=0 checkpoint_transition=false"
          % len(negatives))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--main-sha", help="current main SHA; default git rev-parse HEAD")
    args = parser.parse_args()
    sha = args.main_sha or subprocess.check_output(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()
    selftest(sha)
