#!/usr/bin/env python3
"""Prepare A1-A9 checkpoint data for the EXISTING canonical operation RUN.

Source-only candidate. This function DOES NOT write to Supabase, authenticate
a producer, prove model inference, verify authority, or emit PASS.
Caller must independently bind the Router handoff and current stage sources,
then persist with public.fn_lf_operation_checkpoint_v1 under an active lease.
"""
from __future__ import annotations
import copy
import re

STAGES = tuple(f"A{i}" for i in range(1, 10))
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
KEY = "analysis_stage_progress_v1"


class StageCheckpointError(ValueError):
    pass


def _required(ok, code):
    if not ok:
        raise StageCheckpointError(code)


def _sha(v, n=64):
    return isinstance(v, str) and bool((HEX64 if n == 64 else HEX40).fullmatch(v))


def prepare(run, source_binding, stage, evidence):
    """Return (next_seq, cumulative_payload), no writes.

    Inputs:
      run: readback from public.lf_operation_execution (IN_PROGRESS), including
           checkpoint_seq, checkpoint_payload, business, request_sha256.
      source_binding: current Analysis candidate source pin manifest; checked
           structurally only, never independently currentness-attested here.
      stage: canonical stage A1..A9; evidence: externally sourced receipt data.
    """
    _required(isinstance(run, dict) and isinstance(source_binding, dict)
              and isinstance(evidence, dict), "INPUT_INVALID")
    eid, sha, business = run.get("execution_id"), run.get("request_sha256"), run.get("business")
    _required(isinstance(eid, str) and eid.strip(), "RUN_ID_MISSING")
    _required(run.get("operation_code") == "EJECUCION_PERFIL_LF", "OPERATION_MISMATCH")
    _required(run.get("profile_code") == "PERFIL-PROGRAMMING-ANALYSIS-LF", "PROFILE_MISMATCH")
    _required(run.get("status") == "IN_PROGRESS", "RUN_NOT_IN_PROGRESS")
    _required(_sha(sha), "INPUT_SHA_INVALID")
    _required(business == "LF" and source_binding.get("business") == business,
              "BUSINESS_BINDING_INVALID")
    _required(source_binding.get("business_source_namespace") == "lf_ops",
              "SOURCE_NAMESPACE_INVALID")
    _required(stage in STAGES, "STAGE_UNKNOWN")
    seq = run.get("checkpoint_seq")
    _required(type(seq) is int and seq >= 0, "CHECKPOINT_SEQ_INVALID")
    old = run.get("checkpoint_payload")
    _required(isinstance(old, dict), "PRIOR_CHECKPOINT_INVALID")

    progress = old.get(KEY)
    if progress is None:
        _required(stage == "A1", "FIRST_STAGE_MUST_BE_A1")
        receipts = []
    else:
        _required(isinstance(progress, dict), "PROGRESS_INVALID")
        _required(progress.get("execution_id") == eid
                  and progress.get("business") == business
                  and progress.get("request_sha256") == sha,
                  "PROGRESS_IDENTITY_DRIFT")
        receipts = progress.get("stage_receipts")
        _required(isinstance(receipts, list) and len(receipts) < 9,
                  "PROGRESS_COMPLETED_OR_INVALID")
        _required([r.get("stage") for r in receipts if isinstance(r, dict)]
                  == list(STAGES[:len(receipts)]), "PROGRESS_STAGE_ORDER_INVALID")
        _required(len(receipts) > 0, "PROGRESS_EMPTY")
        _required(len(receipts) < len(STAGES)
                  and stage == STAGES[len(receipts)], "STAGE_ORDER_OR_REPLAY_INVALID")
    pins = source_binding.get("source_readback", {}).get("stage_git_blobs", {})
    source = source_binding.get("required_stage_sources", {}).get(stage)
    _required(isinstance(source, str) and source.strip(), "SOURCE_REF_MISSING")
    _required(_sha(pins.get(stage), 40), "SOURCE_PIN_INVALID")
    _required(evidence.get("execution_id") == eid
              and evidence.get("request_sha256") == sha
              and evidence.get("business") == business,
              "EVIDENCE_IDENTITY_MISMATCH")
    _required(evidence.get("source_ref") == source
              and evidence.get("source_git_blob") == pins[stage],
              "SOURCE_EVIDENCE_MISMATCH")
    _required(isinstance(evidence.get("evidence_ref"), str)
              and evidence["evidence_ref"].strip(), "EVIDENCE_REF_MISSING")
    _required(_sha(evidence.get("raw_output_sha256")), "STAGE_RAW_SHA_INVALID")
    # Absence of receipt provenance is intentional: the qualified recorder
    # must verify the remote evidence reference before accepting this proposal.
    entry = {k: evidence[k] for k in (
        "execution_id", "request_sha256", "business", "source_ref",
        "source_git_blob", "evidence_ref", "raw_output_sha256"
    )}
    entry.update(stage=stage, review_state="UNVERIFIED_SOURCE_CANDIDATE")
    new_payload = copy.deepcopy(old)
    new_payload[KEY] = {
        "schema_version": "ANALYSIS_STAGE_PROGRESS_V1",
        "execution_id": eid,
        "business": business,
        "request_sha256": sha,
        "stage_receipts": copy.deepcopy(receipts) + [entry],
        "last_stage": stage,
        "operational_ready": False,
        "independent_verification": "NOT_EXECUTED",
    }
    return {"checkpoint_seq": seq + 1, "checkpoint_payload": new_payload,
            "persisted": False, "operational_ready": False,
            "next_action": "PERSIST_WITH_CANONICAL_LEASE_FENCED_CHECKPOINT_AND_READBACK"}
