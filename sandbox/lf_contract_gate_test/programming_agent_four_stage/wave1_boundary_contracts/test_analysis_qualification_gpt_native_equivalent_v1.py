#!/usr/bin/env python3
"""Positive/negative tests for the owner-approved GPT Native equivalent tier. No network, no API."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_c2_runtime_receipt_common_v1 as real  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

INP, OUT, PKT = b"frozen-input-bytes", b"gpt-native-raw-output", b"blinded-review-packet"
H = lambda c: c * 64  # noqa: E731


def producer(**kw):
    rec = {"schema": eq.CAPTURE_SCHEMA, "subject_ref": eq.subject("A1", "C2"), "stage_output_selector": "A1",
           "evidence_tier": eq.TIER, "producer_mode": "GPT_NATIVE", "runtime_provider_attested": False,
           "transcript_is_provider_evidence": False, "run_id": "run-a1-0001",
           "owner_approval_ref": eq.APPROVAL_DOC + "@" + H("a"), "owner_approval_doc_sha256": H("a"),
           "chat_transcript_ref": "chat://producer/1", "chat_transcript_sha256": H("b"),
           "input_sha256": eq.sha256_bytes(INP), "request_sha256": H("c"),
           "raw_output_sha256": eq.sha256_bytes(OUT)}
    rec.update(kw)
    return rec


def review(prod, **kw):
    rec = {"schema": eq.REVIEW_SCHEMA, "subject_ref": eq.subject("A1", "C3"), "evidence_tier": eq.TIER,
           "producer_mode": "GPT_NATIVE", "runtime_provider_attested": False,
           "transcript_is_provider_evidence": False, "owner_approval_ref": eq.APPROVAL_DOC + "@" + H("a"),
           "owner_approval_doc_sha256": H("a"), "chat_transcript_ref": "chat://reviewer/2",
           "chat_transcript_sha256": H("d"), "input_sha256": eq.sha256_bytes(PKT),
           "reviewed_raw_output_sha256": prod["raw_output_sha256"], "blinded_packet": True,
           "reviewer_execution_id": "rev-a1-0002", "verdict": "PASS",
           "evidence_refs": ["packet://a1/case1"], "rationale_summary": "checked against frozen oracle"}
    rec.update(kw)
    return rec


def test_positive_c2():
    assert eq.attest_c2(producer(), "A1", INP, OUT) == eq.PASS_C2


def test_positive_c3():
    p = producer()
    assert eq.attest_c3(review(p), p, "A1", PKT) == eq.PASS_C3


def test_never_equals_real_receipt_verdict():
    assert eq.PASS_C2 != real.PASS_RECEIPT_SHAPE_MECHANICS if hasattr(real, "PASS_RECEIPT_SHAPE_MECHANICS") \
        else eq.PASS_C2 != "PASS_RECEIPT_SHAPE_MECHANICS"
    assert eq.limits()["real_execution_receipt"] is False and eq.limits()["provider_attested"] is False


def test_real_receipt_adapter_still_rejects_in_chat_capture():
    verdict = real.attest(real.Spec(unit="A1"), producer(), OUT, INP)
    assert verdict.startswith("BLOCK:"), verdict


C2_NEG = {
    "MISSING_RECORD": lambda: (None, INP, OUT),
    "CROSS_SUBJECT": lambda: (producer(subject_ref=eq.subject("A2", "C2")), INP, OUT),
    "TIER_NOT_APPROVED_EQUIVALENT": lambda: (producer(evidence_tier="REAL_EXECUTION_RECEIPT"), INP, OUT),
    "FORGED_GOVERNED_FIELD": lambda: (producer(governed_execution_id="gx-1"), INP, OUT),
    "FORGED_GOVERNED_FIELD ": lambda: (producer(provider_response_id_attested_by_transport={"id": "r"}), INP, OUT),
    "PROVIDER_ATTESTATION_CLAIMED": lambda: (producer(runtime_provider_attested=True), INP, OUT),
    "TRANSCRIPT_PRESENTED_AS_PROVIDER_EVIDENCE": lambda: (producer(transcript_is_provider_evidence=True), INP, OUT),
    "NON_GPT_NATIVE_PRODUCER": lambda: (producer(producer_mode="CLAUDE_NATIVE"), INP, OUT),
    "OWNER_APPROVAL_REF_MISSING": lambda: (producer(owner_approval_ref=""), INP, OUT),
    "OWNER_APPROVAL_DIGEST_FORMAT": lambda: (producer(owner_approval_doc_sha256="xyz"), INP, OUT),
    "CHAT_TRANSCRIPT_REF_MISSING": lambda: (producer(chat_transcript_ref=""), INP, OUT),
    "CHAT_TRANSCRIPT_DIGEST_FORMAT": lambda: (producer(chat_transcript_sha256="1"), INP, OUT),
    "INPUT_DIGEST_MISMATCH": lambda: (producer(), INP + b"x", OUT),
    "OUTPUT_DIGEST_MISMATCH": lambda: (producer(), INP, OUT + b"x"),
    "CROSS_STAGE": lambda: (producer(stage_output_selector="A0"), INP, OUT),
    "CAPTURE_SCHEMA_INVALID": lambda: (producer(schema="OTHER"), INP, OUT),
    "DIGEST_FORMAT:request_sha256": lambda: (producer(request_sha256="short"), INP, OUT),
    "REPLAY_OR_FIXTURE": lambda: (producer(run_id="REPLAY-1"), INP, OUT),
}


def test_c2_negatives():
    for code, build in C2_NEG.items():
        rec, inp, out = build()
        verdict = eq.attest_c2(rec, "A1", inp, out)
        assert verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_c3_negatives():
    p = producer()
    cases = {
        "REVIEW_SCHEMA_INVALID": review(p, schema="X"),
        "PRODUCER_RECORD_MISSING": None,
        "REVIEW_NOT_BOUND_TO_PRODUCER_OUTPUT": review(p, reviewed_raw_output_sha256=H("e")),
        "PACKET_NOT_BLINDED": review(p, blinded_packet=False),
        "SAME_CHAT_AS_PRODUCER": review(p, chat_transcript_ref=p["chat_transcript_ref"]),
        "SELF_REVIEW": review(p, reviewer_execution_id=p["run_id"]),
        "VERDICT_INVALID": review(p, verdict="MAYBE"),
        "EVIDENCE_MISSING": review(p, evidence_refs=[]),
        "RATIONALE_MISSING": review(p, rationale_summary=" "),
        "REVIEW_VERDICT_FAIL": review(p, verdict="FAIL"),
        "FORGED_GOVERNED_FIELD": review(p, independent_semantic_review_receipt={"id": "x"}),
        "PROVIDER_ATTESTATION_CLAIMED": review(p, runtime_provider_attested=True),
        "INPUT_DIGEST_MISMATCH": review(p, input_sha256=H("f")),
    }
    for code, rev in cases.items():
        prod = None if code == "PRODUCER_RECORD_MISSING" else p
        rev = review(p) if rev is None else rev
        assert eq.attest_c3(rev, prod, "A1", PKT) == "BLOCK:" + code, code


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS_GPT_NATIVE_EQUIVALENT_TIER_SHAPE_ONLY positives=2 c2_negatives=%d c3_negatives=13 "
          "provider_attested=false real_receipt=false db_write=false api_calls=0" % len(C2_NEG))


if __name__ == "__main__":
    main()
