#!/usr/bin/env python3
"""Owner-approved GPT Native in-chat equivalent tier for A<N>Q_C2 / A<N>Q_C3 (shape + bindings only).

This is NOT a real-execution receipt and NOT provider attestation. It never returns the
verdict of analysis_qualification_c2_runtime_receipt_common_v1.attest(). It checks that a
GPT Native in-chat capture (LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1 field names) is exactly bound to
a frozen input and RAW output, that it makes no provider/governed-runtime claim, and that the
owner-approval record and the chat transcript are referenced. A sealed transcript is a copy of
what the chat said; it is not evidence from the provider.

Known limits (not closed here, recorded in the result):
* It cannot prove GPT produced the RAW or that a separate chat was truly blind/independent.
* It does not transition any checkpoint, write to any database or change any action spec.
* Closing a checkpoint under this tier needs its own Train migration that records the tier and
  its limits honestly (provider_attested=false), as the C1 attestations did.
"""
from __future__ import annotations

import hashlib
import re

APPROVAL_DOC = "docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md"
TIER = "OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT"
CAPTURE_SCHEMA = "LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1"
REVIEW_SCHEMA = "ANALYSIS_GPT_NATIVE_BLIND_REVIEW_V1"
PASS_C2 = "PASS_EQUIVALENT_TIER_UNATTESTED_C2"
PASS_C3 = "PASS_EQUIVALENT_TIER_UNATTESTED_C3"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PLAN = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1"
# Fields only a governed runtime/ledger may supply. Presence in an in-chat capture is forgery.
GOVERNED_ONLY = ("provider_response_id_attested_by_transport", "runtime_attestation",
                 "runtime_attestation_verification", "provider_signature",
                 "governed_execution_id", "router_dispatch_receipt_id",
                 "evidence_ledger_verified_ref", "independent_semantic_review_receipt")
LIMITS = {"provider_attested": False, "real_execution_receipt": False,
          "independent_assurance_admitted": False, "transcript_is_provider_evidence": False,
          "checkpoint_transition": False, "db_write": False}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def subject(unit: str, cp: str) -> str:
    return f"{PLAN}/{unit}Q/{unit}Q_{cp}"


def _block(code: str) -> str:
    return "BLOCK:" + code


def _common(record, unit: str, cp: str, input_bytes: bytes):
    if not isinstance(record, dict) or not record:
        return _block("MISSING_RECORD")
    if record.get("subject_ref") != subject(unit, cp):
        return _block("CROSS_SUBJECT")
    if record.get("evidence_tier") != TIER:
        return _block("TIER_NOT_APPROVED_EQUIVALENT")
    if any(k in record for k in GOVERNED_ONLY):
        return _block("FORGED_GOVERNED_FIELD")
    if record.get("runtime_provider_attested") is not False:
        return _block("PROVIDER_ATTESTATION_CLAIMED")
    if record.get("transcript_is_provider_evidence") is not False:
        return _block("TRANSCRIPT_PRESENTED_AS_PROVIDER_EVIDENCE")
    if record.get("producer_mode") != "GPT_NATIVE":
        return _block("NON_GPT_NATIVE_PRODUCER")
    approval = record.get("owner_approval_ref")
    if not isinstance(approval, str) or not approval.startswith(APPROVAL_DOC + "@"):
        return _block("OWNER_APPROVAL_REF_MISSING")
    if not HEX64.match(str(record.get("owner_approval_doc_sha256", ""))):
        return _block("OWNER_APPROVAL_DIGEST_FORMAT")
    chat = record.get("chat_transcript_ref")
    if not isinstance(chat, str) or not chat.strip():
        return _block("CHAT_TRANSCRIPT_REF_MISSING")
    if not HEX64.match(str(record.get("chat_transcript_sha256", ""))):
        return _block("CHAT_TRANSCRIPT_DIGEST_FORMAT")
    if not HEX64.match(str(record.get("input_sha256", ""))):
        return _block("DIGEST_FORMAT:input_sha256")
    if record["input_sha256"] != sha256_bytes(input_bytes):
        return _block("INPUT_DIGEST_MISMATCH")
    return None


def attest_c2(record, unit: str, input_bytes: bytes, output_bytes: bytes) -> str:
    """C2 producer capture. Returns PASS_EQUIVALENT_TIER_UNATTESTED_C2 or BLOCK:<code>."""
    err = _common(record, unit, "C2", input_bytes)
    if err:
        return err
    if record.get("schema") != CAPTURE_SCHEMA:
        return _block("CAPTURE_SCHEMA_INVALID")
    if record.get("stage_output_selector") != unit:
        return _block("CROSS_STAGE")
    if not HEX64.match(str(record.get("request_sha256", ""))):
        return _block("DIGEST_FORMAT:request_sha256")
    if not HEX64.match(str(record.get("raw_output_sha256", ""))):
        return _block("DIGEST_FORMAT:raw_output_sha256")
    if record["raw_output_sha256"] != sha256_bytes(output_bytes):
        return _block("OUTPUT_DIGEST_MISMATCH")
    if not str(record.get("run_id", "")).strip() or str(record["run_id"]).upper().startswith(
            ("FIXTURE", "REPLAY", "DUMMY", "SYNTHETIC")):
        return _block("REPLAY_OR_FIXTURE")
    return PASS_C2


def attest_c3(review, producer_record, unit: str, packet_bytes: bytes) -> str:
    """C3 review captured in a SEPARATE GPT chat over a blinded packet.

    The packet must not contain the producer's verdict or chat. Blindness and true separation
    cannot be proved here; this only rejects what is checkably wrong.
    """
    err = _common(review, unit, "C3", packet_bytes)
    if err:
        return err
    if review.get("schema") != REVIEW_SCHEMA:
        return _block("REVIEW_SCHEMA_INVALID")
    if not isinstance(producer_record, dict) or not producer_record:
        return _block("PRODUCER_RECORD_MISSING")
    if review.get("reviewed_raw_output_sha256") != producer_record.get("raw_output_sha256"):
        return _block("REVIEW_NOT_BOUND_TO_PRODUCER_OUTPUT")
    if review.get("blinded_packet") is not True:
        return _block("PACKET_NOT_BLINDED")
    if review.get("chat_transcript_ref") == producer_record.get("chat_transcript_ref") or \
            review.get("chat_transcript_sha256") == producer_record.get("chat_transcript_sha256"):
        return _block("SAME_CHAT_AS_PRODUCER")
    rid, pid = review.get("reviewer_execution_id"), producer_record.get("run_id")
    if not rid or rid == pid:
        return _block("SELF_REVIEW")
    if review.get("verdict") not in ("PASS", "FAIL"):
        return _block("VERDICT_INVALID")
    refs = review.get("evidence_refs")
    if not (isinstance(refs, list) and refs and all(isinstance(r, str) and r.strip() for r in refs)):
        return _block("EVIDENCE_MISSING")
    if not str(review.get("rationale_summary", "")).strip():
        return _block("RATIONALE_MISSING")
    if review["verdict"] != "PASS":
        return _block("REVIEW_VERDICT_FAIL")
    return PASS_C3


def limits() -> dict:
    return dict(LIMITS)
