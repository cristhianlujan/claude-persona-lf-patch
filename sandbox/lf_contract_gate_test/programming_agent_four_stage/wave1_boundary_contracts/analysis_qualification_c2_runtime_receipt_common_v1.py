#!/usr/bin/env python3
"""Shared mechanics for the A<N>Q_C2 real-execution-receipt adapters (source-level only).

Checks the SHAPE and BINDINGS of a candidate execution receipt: exact subject and stage,
all contract evidence fields, provider response id attested by the governed transport
(never self-declared), digest bindings against the actual stage output bytes, and rejection
of replay/fixture/test-vector receipts.

Known limits (not closed here):
* It does not call profiles/programming_analysis_lf/validators/runtime_validate.py: that
  validator checks a whole A1-A9 package and no verified real-model package exists to feed it.
* It cannot prove a model really ran. Only the governed runtime/ledger can emit that proof.
* It does not transition any checkpoint or claim operational PASS.
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CATALOG = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json"
PLAN = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
FIELDS = ("governed_execution_id", "router_dispatch_receipt_id", "producer_execution_id",
          "provider_response_id_attested_by_transport", "exact_profile_version",
          "input_digest_sha256", "output_digest_sha256", "stage_output_ref",
          "stage_source_receipt_refs", "evidence_ledger_verified_ref")
NOT_GOVERNED_PREFIXES = ("FIXTURE", "REPLAY", "SELF", "DUMMY", "SYNTHETIC")


@dataclass(frozen=True)
class Spec:
    unit: str

    @property
    def subject(self) -> str:
        return f"{PLAN}/{self.unit}Q/{self.unit}Q_C2"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def attest(spec: Spec, receipt, output_bytes: bytes, input_bytes: bytes,
           allow_test_vector: bool = False) -> str:
    """Return PASS_RECEIPT_SHAPE_MECHANICS or BLOCK:<code>. Fail closed."""
    if not receipt:
        return "BLOCK:MISSING_RECEIPT"
    if receipt.get("subject_ref") != spec.subject:
        return "BLOCK:CROSS_SUBJECT"
    if receipt.get("stage_output_selector") != spec.unit:
        return "BLOCK:CROSS_STAGE"
    if receipt.get("_test_vector") and not allow_test_vector:
        return "BLOCK:TEST_VECTOR_NOT_ADMISSIBLE"
    for key in FIELDS:
        if receipt.get(key) in (None, "", [], {}):
            return "BLOCK:SYNTHETIC_OR_INCOMPLETE:" + key
    provider = receipt["provider_response_id_attested_by_transport"]
    if (not isinstance(provider, dict) or provider.get("attested_by") != "TRANSPORT"
            or not provider.get("attestation_ref") or not provider.get("id")):
        return "BLOCK:SELF_DECLARED_PROVIDER_ID"
    for key in ("governed_execution_id", "producer_execution_id"):
        if str(receipt[key]).upper().startswith(NOT_GOVERNED_PREFIXES):
            return "BLOCK:REPLAY_OR_FIXTURE"
    if receipt.get("replay") is True:
        return "BLOCK:REPLAY_OR_FIXTURE"
    for key in ("input_digest_sha256", "output_digest_sha256"):
        if not HEX64.match(str(receipt[key])):
            return "BLOCK:DIGEST_FORMAT:" + key
    if receipt["input_digest_sha256"] != sha256_bytes(input_bytes):
        return "BLOCK:INPUT_DIGEST_MISMATCH"
    if receipt["output_digest_sha256"] != sha256_bytes(output_bytes):
        return "BLOCK:OUTPUT_DIGEST_MISMATCH"
    if not isinstance(receipt["stage_source_receipt_refs"], list):
        return "BLOCK:SOURCE_RECEIPT_REFS_TYPE"
    return "PASS_RECEIPT_SHAPE_MECHANICS"


def test_vector(spec: Spec, input_bytes: bytes, output_bytes: bytes) -> dict:
    """Synthetic vector for mechanics tests only; attest() rejects it unless allowed."""
    return {"_test_vector": True, "subject_ref": spec.subject, "stage_output_selector": spec.unit,
            "governed_execution_id": "gx-test-0001", "router_dispatch_receipt_id": "rd-test-0001",
            "producer_execution_id": "px-test-0001",
            "provider_response_id_attested_by_transport": {
                "id": "resp-test-0001", "attested_by": "TRANSPORT", "attestation_ref": "att-test-0001"},
            "exact_profile_version": "test-profile@0",
            "input_digest_sha256": sha256_bytes(input_bytes),
            "output_digest_sha256": sha256_bytes(output_bytes),
            "stage_output_ref": f"test://{spec.unit}/output",
            "stage_source_receipt_refs": ["test://source-receipt"],
            "evidence_ledger_verified_ref": "ledger-test-0001"}


def catalog_binding(spec: Spec) -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    unit = next(u for u in catalog["units"] if u["unit_code"] == spec.unit)
    contract = unit["checkpoints"][1]["validator_contract"]
    assert contract["checkpoint_code"] == f"{spec.unit}Q_C2"
    assert contract["subject_ref"] == spec.subject, contract["subject_ref"]
    assert contract["owner"] == "EXISTING_PROFILE_RUNTIME"
    assert contract["stage_output_selector"] == spec.unit
    assert tuple(contract["acceptance_evidence_fields"]) == FIELDS


def selftest(spec: Spec) -> str:
    catalog_binding(spec)
    inp, out = b"stage-input-bytes", b"stage-output-bytes"
    good = test_vector(spec, inp, out)
    assert attest(spec, good, out, inp, allow_test_vector=True) == "PASS_RECEIPT_SHAPE_MECHANICS"
    other = spec.subject.replace("Q_C2", "Q_C3")

    def mut(**kw):
        return dict(good, **kw)

    negatives = {
        "missing_receipt": ("MISSING_RECEIPT", attest(spec, None, out, inp, True)),
        "test_vector_not_admissible": ("TEST_VECTOR_NOT_ADMISSIBLE", attest(spec, good, out, inp)),
        "different_subject": ("CROSS_SUBJECT", attest(spec, mut(subject_ref=other), out, inp, True)),
        "different_stage": ("CROSS_STAGE", attest(spec, mut(stage_output_selector="A0"), out, inp, True)),
        "missing_field": ("SYNTHETIC_OR_INCOMPLETE", attest(spec, mut(router_dispatch_receipt_id=""), out, inp, True)),
        "self_declared_provider_id": ("SELF_DECLARED_PROVIDER_ID", attest(
            spec, mut(provider_response_id_attested_by_transport={
                "id": "resp-1", "attested_by": "MODEL_TEXT", "attestation_ref": "x"}), out, inp, True)),
        "replay_or_fixture": ("REPLAY_OR_FIXTURE", attest(
            spec, mut(governed_execution_id="REPLAY-0001"), out, inp, True)),
        "output_drift": ("OUTPUT_DIGEST_MISMATCH", attest(spec, good, out + b"x", inp, True)),
        "input_drift": ("INPUT_DIGEST_MISMATCH", attest(spec, good, out, inp + b"x", True)),
    }
    for name, (code, verdict) in negatives.items():
        assert verdict.startswith("BLOCK:" + code), (name, code, verdict)
    return ("PASS_%sQ_C2_RECEIPT_MECHANICS_ONLY positives=1 negatives=%d catalog_bound=true "
            "runtime_validate_invoked=false governed_receipts=0 checkpoint_transition=false"
            % (spec.unit, len(negatives)))


def main(spec: Spec) -> None:
    print(selftest(spec))
