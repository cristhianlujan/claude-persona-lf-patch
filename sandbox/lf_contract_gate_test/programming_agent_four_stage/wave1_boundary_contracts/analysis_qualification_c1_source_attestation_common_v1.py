#!/usr/bin/env python3
"""Shared mechanics for the A<N>Q_C1 source-attestation adapters (source-level only).

Verifies a candidate receipt against the current bytes of the checkpoint's canonical
source, the current main SHA and the exact subject, binds the adapter to the checkpoint
catalog entry, and runs the stage's existing structural validator.

It does NOT transition any checkpoint, emit a governed receipt or claim operational PASS.
A receipt built by this module is self-attested and never qualifies a checkpoint: the
governed runtime must emit the verified readback receipt.
"""
from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CATALOG = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json"
PLAN = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1"
REQUIRED = ("source_ref", "resolved_main_sha", "actual_sha256",
            "current_capability_binding", "readback_receipt_id",
            "source_attestation_verified")


@dataclass(frozen=True)
class Spec:
    unit: str                                  # e.g. "A2"
    source_name: str                           # canonical source file name
    callable_name: str                         # structural validator named in the catalog
    validate: Callable[[Any], None]            # existing validator (raises ValueError subclass)
    structural_object: Callable[[], Any]       # fresh object the validator accepts

    @property
    def subject(self) -> str:
        return f"{PLAN}/{self.unit}Q/{self.unit}Q_C1"

    @property
    def source(self) -> Path:
        return HERE / self.source_name


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def candidate_receipt(spec: Spec, main_sha: str) -> dict:
    return {"subject_ref": spec.subject, "source_ref": str(spec.source.relative_to(REPO)),
            "resolved_main_sha": main_sha, "actual_sha256": sha256_file(spec.source),
            "current_capability_binding": ["CURRENTNESS_AUTHORITY@1.0.0",
                                           "SOURCE_RESOLUTION_POLICY@1.4.0"],
            "readback_receipt_id": "SELF_ATTESTED_NOT_GOVERNED",
            "source_attestation_verified": True}


def attest(spec: Spec, receipt, live_main_sha: str) -> str:
    """Return PASS_SOURCE_ATTESTATION_MECHANICS or BLOCK:<code>. Fail closed."""
    if not receipt:
        return "BLOCK:MISSING_RECEIPT"
    if receipt.get("subject_ref") != spec.subject:
        return "BLOCK:CROSS_SUBJECT"
    for key in REQUIRED:
        if receipt.get(key) in (None, "", [], False):
            return "BLOCK:SYNTHETIC_OR_INCOMPLETE:" + key
    if receipt["resolved_main_sha"] != live_main_sha:
        return "BLOCK:STALE_MAIN"
    if sha256_file(spec.source) != receipt["actual_sha256"]:
        return "BLOCK:SOURCE_DRIFT"
    try:
        spec.validate(spec.structural_object())
    except Exception as exc:  # the stage validator must accept the current object
        return "BLOCK:STRUCTURE:" + str(exc)
    return "PASS_SOURCE_ATTESTATION_MECHANICS"


def _bool_paths(node, path=()):
    if isinstance(node, bool):
        yield path
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from _bool_paths(value, path + (key,))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _bool_paths(value, path + (index,))


def _flip(obj, path):
    node = obj
    for step in path[:-1]:
        node = node[step]
    node[path[-1]] = not node[path[-1]]


def structural_flip_rejections(spec: Spec) -> tuple[int, int]:
    """Flip each boolean of the validated object one at a time; return (rejected, tried)."""
    base = spec.structural_object()
    rejected = tried = 0
    for path in _bool_paths(base):
        mutated = copy.deepcopy(base)
        _flip(mutated, path)
        tried += 1
        try:
            spec.validate(mutated)
        except ValueError:
            rejected += 1
    return rejected, tried


def catalog_binding(spec: Spec) -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    unit = next(u for u in catalog["units"] if u["unit_code"] == spec.unit)
    contract = unit["checkpoints"][0]["validator_contract"]
    assert contract["checkpoint_code"] == f"{spec.unit}Q_C1"
    assert contract["subject_ref"] == spec.subject, contract["subject_ref"]
    assert contract["canonical_source"]["path"].endswith("/" + spec.source_name)
    assert contract["stage_structure_validator"]["callable"] == spec.callable_name


def selftest(spec: Spec, main_sha: str | None = None) -> str:
    main_sha = main_sha or subprocess.check_output(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()
    catalog_binding(spec)
    receipt = candidate_receipt(spec, main_sha)
    assert attest(spec, receipt, main_sha) == "PASS_SOURCE_ATTESTATION_MECHANICS"
    other = spec.subject.replace("Q_C1", "Q_C2")
    negatives = {
        "missing_receipt": ("MISSING_RECEIPT", attest(spec, None, main_sha)),
        "stale_main": ("STALE_MAIN", attest(spec, receipt, "0" * 40)),
        "source_drift": ("SOURCE_DRIFT", attest(spec, dict(receipt, actual_sha256="0" * 64), main_sha)),
        "different_subject": ("CROSS_SUBJECT", attest(spec, dict(receipt, subject_ref=other), main_sha)),
        "synthetic_no_readback_id": ("SYNTHETIC_OR_INCOMPLETE", attest(
            spec, dict(receipt, readback_receipt_id=""), main_sha)),
        "synthetic_unverified_flag": ("SYNTHETIC_OR_INCOMPLETE", attest(
            spec, dict(receipt, source_attestation_verified=False), main_sha)),
    }
    for name, (code, verdict) in negatives.items():
        assert verdict.startswith("BLOCK:" + code), (name, code, verdict)
    rejected, tried = structural_flip_rejections(spec)
    assert tried > 0 and rejected >= 1, (rejected, tried)
    return ("PASS_%sQ_C1_SOURCE_MECHANICS_ONLY positives=1 negatives=%d "
            "structural_flips_rejected=%d/%d catalog_bound=true governed_receipts=0 "
            "checkpoint_transition=false" % (spec.unit, len(negatives), rejected, tried))


def main(spec: Spec) -> None:
    sys.exit(print(selftest(spec)) or 0)
