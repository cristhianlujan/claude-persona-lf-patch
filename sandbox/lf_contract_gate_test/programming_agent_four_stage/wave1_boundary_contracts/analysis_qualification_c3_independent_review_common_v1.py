#!/usr/bin/env python3
"""Shared mechanics for the A<N>Q_C3 independent-review-receipt adapters (source-level only).

Checks the SHAPE and BINDINGS of a candidate independent-review receipt: exact subject, all
contract evidence fields, reviewer distinct from producer, frozen subject digest bound to the
actual subject bytes, the exact stage assertion present with PASS, no critical regressions, and
rejection of test-vector receipts. Adds the unit-specific guards named in the catalog (A9 PG-01
consumer receipt, A14 thresholds, A15 14/14 prior qualifiers).

Known limits (not closed here):
* INDEPENDENT_ASSURANCE@2.0.1 declares validator_ref
  sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/
  validate_independent_review_subject_envelope_v3.py, which returns 404 on main. It is NOT
  referenced or imitated here; reconciling that reference is a separate governed task.
* It cannot prove a reviewer was independent or ran. Only the governed ledger can.
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
FIELDS = ("frozen_subject_sha256", "producer_execution_id", "reviewer_execution_id",
          "review_dispatch_receipt_id", "review_verdict_ref", "evidence_ledger_verified_ref",
          "exact_stage_assertion_results", "no_critical_regressions")
A14_THRESHOLDS = {"critical_omissions": 0, "critical_false_ready": 0,
                  "classification_accuracy_min": 0.95,
                  "usable_without_material_reinterpretation_min": 0.95}


@dataclass(frozen=True)
class Spec:
    unit: str

    @property
    def subject(self) -> str:
        return f"{PLAN}/{self.unit}Q/{self.unit}Q_C3"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stage_assertion(spec: Spec) -> str:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    unit = next(u for u in catalog["units"] if u["unit_code"] == spec.unit)
    return unit["checkpoints"][2]["validator_contract"]["stage_specific_assertion"]


def _unit_guard(spec: Spec, receipt) -> str | None:
    if spec.unit == "A9":
        pg01 = receipt.get("pg01_consumer_receipt")
        needed = ("context_id", "context_sha256", "schema_version", "receipt_id")
        if not isinstance(pg01, dict) or any(not pg01.get(k) for k in needed):
            return "BLOCK:A9_PG01_CONSUMER_RECEIPT_MISSING"
        if not HEX64.match(str(pg01["context_sha256"])):
            return "BLOCK:A9_PG01_CONTEXT_DIGEST_FORMAT"
    if spec.unit == "A14":
        m = receipt.get("metrics")
        if not isinstance(m, dict) or receipt.get("score_replay") is not False:
            return "BLOCK:A14_REPLAY_OR_METRICS_MISSING"
        if (m.get("critical_omissions") != 0 or m.get("critical_false_ready") != 0
                or not isinstance(m.get("classification_accuracy"), (int, float))
                or m["classification_accuracy"] < A14_THRESHOLDS["classification_accuracy_min"]
                or not isinstance(m.get("usable_without_material_reinterpretation"), (int, float))
                or m["usable_without_material_reinterpretation"]
                < A14_THRESHOLDS["usable_without_material_reinterpretation_min"]):
            return "BLOCK:A14_THRESHOLDS_NOT_MET"
    if spec.unit == "A15":
        q = receipt.get("qualifier_receipts")
        if (not isinstance(q, list) or len(set(map(str, q))) != 14
                or any(not str(x) for x in q)):
            return "BLOCK:A15_PRIOR_QUALIFIERS_NOT_14_OF_14"
    return None


def attest(spec: Spec, receipt, subject_bytes: bytes, allow_test_vector: bool = False) -> str:
    """Return PASS_REVIEW_SHAPE_MECHANICS or BLOCK:<code>. Fail closed."""
    if not receipt:
        return "BLOCK:MISSING_RECEIPT"
    if receipt.get("subject_ref") != spec.subject:
        return "BLOCK:CROSS_SUBJECT"
    if receipt.get("_test_vector") and not allow_test_vector:
        return "BLOCK:TEST_VECTOR_NOT_ADMISSIBLE"
    for key in FIELDS:
        value = receipt.get(key)
        if key == "no_critical_regressions":
            if value is not True:
                return "BLOCK:CRITICAL_REGRESSIONS_OR_UNVERIFIED"
        elif value in (None, "", [], {}):
            return "BLOCK:SYNTHETIC_OR_INCOMPLETE:" + key
    if receipt["reviewer_execution_id"] == receipt["producer_execution_id"]:
        return "BLOCK:SELF_REVIEW"
    if not HEX64.match(str(receipt["frozen_subject_sha256"])):
        return "BLOCK:DIGEST_FORMAT:frozen_subject_sha256"
    if receipt["frozen_subject_sha256"] != sha256_bytes(subject_bytes):
        return "BLOCK:SUBJECT_DRIFT"
    results = receipt["exact_stage_assertion_results"]
    wanted = stage_assertion(spec)
    if (not isinstance(results, list)
            or not any(isinstance(r, dict) and r.get("assertion") == wanted
                       and r.get("result") == "PASS" for r in results)
            or any(isinstance(r, dict) and r.get("result") != "PASS" for r in results)):
        return "BLOCK:ASSERTION_MISSING_OR_FAILED"
    guard = _unit_guard(spec, receipt)
    if guard:
        return guard
    return "PASS_REVIEW_SHAPE_MECHANICS"


def test_vector(spec: Spec, subject_bytes: bytes) -> dict:
    """Synthetic vector for mechanics tests only; attest() rejects it unless allowed."""
    v = {"_test_vector": True, "subject_ref": spec.subject,
         "frozen_subject_sha256": sha256_bytes(subject_bytes),
         "producer_execution_id": "px-test-0001", "reviewer_execution_id": "rx-test-0002",
         "review_dispatch_receipt_id": "rv-test-0001", "review_verdict_ref": "verdict-test-0001",
         "evidence_ledger_verified_ref": "ledger-test-0001",
         "exact_stage_assertion_results": [{"assertion": stage_assertion(spec), "result": "PASS"}],
         "no_critical_regressions": True}
    if spec.unit == "A9":
        v["pg01_consumer_receipt"] = {"context_id": "ctx-test", "context_sha256": "a" * 64,
                                      "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
                                      "receipt_id": "pg01-test-0001"}
    if spec.unit == "A14":
        v["score_replay"] = False
        v["metrics"] = {"critical_omissions": 0, "critical_false_ready": 0,
                        "classification_accuracy": 0.96,
                        "usable_without_material_reinterpretation": 0.96}
    if spec.unit == "A15":
        v["qualifier_receipts"] = [f"test://A{i}Q" for i in range(1, 15)]
    return v


def catalog_binding(spec: Spec) -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    unit = next(u for u in catalog["units"] if u["unit_code"] == spec.unit)
    contract = unit["checkpoints"][2]["validator_contract"]
    assert contract["checkpoint_code"] == f"{spec.unit}Q_C3"
    assert contract["subject_ref"] == spec.subject, contract["subject_ref"]
    assert contract["owner"] == "INDEPENDENT_ASSURANCE@2.0.1"
    assert tuple(contract["acceptance_evidence_fields"]) == FIELDS
    if spec.unit == "A14":
        thr = contract["required_thresholds"]
        assert thr["critical_omissions"] == 0 and thr["critical_false_ready"] == 0
        assert thr["classification_accuracy_min"] == A14_THRESHOLDS["classification_accuracy_min"]
        assert thr["score_replay_not_admitted"] is True
    if spec.unit == "A9":
        assert contract["additional_consumer_guard"]["fn"] == "programacion.fn_analysis_pg01_exact_receipt_guard_v1"


def selftest(spec: Spec) -> str:
    catalog_binding(spec)
    subject = f"frozen-subject:{spec.subject}".encode()
    good = test_vector(spec, subject)
    assert attest(spec, good, subject, allow_test_vector=True) == "PASS_REVIEW_SHAPE_MECHANICS"
    other = spec.subject.replace("Q_C3", "Q_C2")

    def mut(**kw):
        return dict(good, **kw)

    negatives = {
        "missing_receipt": ("MISSING_RECEIPT", attest(spec, None, subject, True)),
        "test_vector_not_admissible": ("TEST_VECTOR_NOT_ADMISSIBLE", attest(spec, good, subject)),
        "different_subject": ("CROSS_SUBJECT", attest(spec, mut(subject_ref=other), subject, True)),
        "missing_field": ("SYNTHETIC_OR_INCOMPLETE", attest(spec, mut(review_verdict_ref=""), subject, True)),
        "self_review": ("SELF_REVIEW", attest(spec, mut(reviewer_execution_id="px-test-0001"), subject, True)),
        "subject_drift": ("SUBJECT_DRIFT", attest(spec, good, subject + b"x", True)),
        "assertion_failed": ("ASSERTION_MISSING_OR_FAILED", attest(spec, mut(
            exact_stage_assertion_results=[{"assertion": stage_assertion(spec), "result": "FAIL"}]), subject, True)),
        "assertion_missing": ("ASSERTION_MISSING_OR_FAILED", attest(spec, mut(
            exact_stage_assertion_results=[{"assertion": "other", "result": "PASS"}]), subject, True)),
        "critical_regressions": ("CRITICAL_REGRESSIONS_OR_UNVERIFIED", attest(
            spec, mut(no_critical_regressions=False), subject, True)),
    }
    if spec.unit == "A9":
        negatives["a9_no_pg01_receipt"] = ("A9_PG01_CONSUMER_RECEIPT_MISSING", attest(
            spec, {k: v for k, v in good.items() if k != "pg01_consumer_receipt"}, subject, True))
    if spec.unit == "A14":
        negatives["a14_replay"] = ("A14_REPLAY_OR_METRICS_MISSING", attest(
            spec, mut(score_replay=True), subject, True))
        negatives["a14_weak_threshold"] = ("A14_THRESHOLDS_NOT_MET", attest(spec, mut(metrics=dict(
            good["metrics"], classification_accuracy=0.90)), subject, True))
    if spec.unit == "A15":
        negatives["a15_13_of_14"] = ("A15_PRIOR_QUALIFIERS_NOT_14_OF_14", attest(
            spec, mut(qualifier_receipts=good["qualifier_receipts"][:13]), subject, True))
    for name, (code, verdict) in negatives.items():
        assert verdict.startswith("BLOCK:" + code), (name, code, verdict)
    return ("PASS_%sQ_C3_REVIEW_MECHANICS_ONLY positives=1 negatives=%d catalog_bound=true "
            "independent_assurance_validator_ref_404_not_referenced=true governed_receipts=0 "
            "checkpoint_transition=false" % (spec.unit, len(negatives)))


def main(spec: Spec) -> None:
    print(selftest(spec))
