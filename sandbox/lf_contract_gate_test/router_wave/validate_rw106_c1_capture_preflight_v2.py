#!/usr/bin/env python3
"""Advisory-only P0 preflight for RW1-06 C1 capture V2.

Structural checks never prove separate-provider context, owner identity, storage ACL,
durability or Git readback. No holdout generation or checkpoint transitions.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
from pathlib import Path

SOURCE = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
POLICY = "138efc3285ee5226c107827c66f84ced6be4afcb"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class PreflightError(ValueError):
    pass


def check(ok: bool, code: str) -> None:
    if not ok:
        raise PreflightError(code)


def ref(value: object) -> bool:
    return isinstance(value, str) and len(value) >= 24 and (
        value.startswith("github://") or value.startswith("vault-evidence://")
        or value.startswith("owner-private-evidence://")
    )


def validate(data: object) -> dict:
    check(isinstance(data, dict), "INPUT_NOT_OBJECT")
    check(data.get("schema_version") == "RW106_C1_REVIEW_PREFLIGHT_V2", "SCHEMA_MISMATCH")
    check(data.get("checkpoint") == "RW1-06_C1", "CHECKPOINT_MISMATCH")
    check(data.get("source_snapshot_commit") == SOURCE, "SOURCE_SNAPSHOT_MISMATCH")
    check(data.get("source_policy_git_blob") == POLICY, "POLICY_BLOB_MISMATCH")
    check(data.get("stage") == "PRE_GENERATION", "WRONG_STAGE")
    attempt = data.get("attempt")
    check(isinstance(attempt, dict), "ATTEMPT_REQUIRED")
    check(ref(attempt.get("issued_ref")), "ATTEMPT_GIT_ID_MISSING")
    check(attempt.get("issued_ref").startswith("github://"), "ATTEMPT_NOT_GIT_ISSUED")
    check(type(attempt.get("git_readback_verified")) is bool
          and attempt["git_readback_verified"], "ATTEMPT_READBACK_REQUIRED")
    reviewer = data.get("reviewer_channel")
    check(isinstance(reviewer, dict), "REVIEWER_CHANNEL_REQUIRED")
    check(reviewer.get("mode") == "GPT_NATIVE_OUTSIDE_LF_PROJECT", "REVIEWER_CONTEXT_UNSUPPORTED")
    check(reviewer.get("memory_personalization_disabled") is True,
          "PERSONALIZATION_EXPOSURE_GAP")
    check(reviewer.get("shared_project_context_access") is False
          and reviewer.get("producer_context_access") is False, "REVIEWER_CONTEXT_CONTAMINATION")
    check(ref(reviewer.get("owner_attestation_ref")), "OWNER_WITNESS_MISSING")
    check(reviewer.get("provider_attested") is False, "FALSE_PROVIDER_ATTESTATION")
    custody = data.get("custody")
    check(isinstance(custody, dict), "CUSTODY_REQUIRED")
    check(custody.get("store_type") in
          {"ACCESS_CONTROLLED_PRIVATE_STORE", "ENCRYPTED_DURABLE_VAULT"}, "STORE_NOT_DURABLE")
    check(custody.get("ephemeral_storage_only") is False, "SESSION_LOCAL_CUSTODY_FORBIDDEN")
    check(ref(custody.get("test_upload_retrieve_evidence_ref")), "RETRIEVAL_EVIDENCE_MISSING")
    check(ref(custody.get("producer_acl_denial_evidence_ref")), "ACL_EVIDENCE_MISSING")
    check(custody.get("durable_readback_verified") is True, "DURABLE_READBACK_GAP")
    check(isinstance(custody.get("private_locator_digest"), str) and
          SHA256.fullmatch(custody["private_locator_digest"]) is not None,
          "PRIVATE_LOCATOR_DIGEST_MISSING")
    check(data.get("old_holdout_reused") is False, "OLD_HOLDOUT_REUSED")
    check(data.get("holdout_generated") is False, "PREFLIGHT_MUST_PRECEDE_GENERATION")
    check(data.get("producer_raw_observed") is False, "PRODUCER_RAW_ALREADY_OBSERVED")
    check(data.get("checkpoint_done") is False, "FALSE_C1_CLOSURE")
    check(not any(k in data for k in
                  ("seed", "nonce", "cases", "case_bodies", "oracles", "private_corpus")),
          "SECRET_EXPOSED_IN_PREFLIGHT")
    return {
        "validation": "STRUCTURAL_PASS_EXTERNAL_PROOFS_UNVERIFIED",
        "stage": "PRE_GENERATION",
        "replay_safe": False,
        "holdout_generated": False,
        "provider_attested": False,
        "checkpoint_done": False,
        "material_admission": "GAP_UNTIL_PROOF_READBACK_AND_GOVERNANCE",
        "notes": [
            "Attempt Git URI does not demonstrate independent review",
            "Owner witness reference does not prove provider isolation",
            "Custody claims require separate trusted access and readback",
            "V2 identity replacement requires explicit governed spec and validator change",
        ],
    }


def selftest() -> dict:
    sample = {
        "schema_version": "RW106_C1_REVIEW_PREFLIGHT_V2",
        "checkpoint": "RW1-06_C1",
        "source_snapshot_commit": SOURCE,
        "source_policy_git_blob": POLICY,
        "stage": "PRE_GENERATION",
        "attempt": {
            "issued_ref": "github://org/repo/blob/0123456789abcdef0123456789abcdef01234567",
            "git_readback_verified": True,
        },
        "reviewer_channel": {
            "mode": "GPT_NATIVE_OUTSIDE_LF_PROJECT",
            "memory_personalization_disabled": True,
            "shared_project_context_access": False,
            "producer_context_access": False,
            "owner_attestation_ref": "owner-private-evidence://mock-reviewer-witness-fixture",
            "provider_attested": False,
        },
        "custody": {
            "store_type": "ENCRYPTED_DURABLE_VAULT",
            "ephemeral_storage_only": False,
            "test_upload_retrieve_evidence_ref": "vault-evidence://mock-upload-retrieve-fixture",
            "producer_acl_denial_evidence_ref": "vault-evidence://mock-producer-denial-fixture",
            "durable_readback_verified": True,
            "private_locator_digest": "a" * 64,
        },
        "old_holdout_reused": False,
        "holdout_generated": False,
        "producer_raw_observed": False,
        "checkpoint_done": False,
    }
    check(validate(sample)["validation"] == "STRUCTURAL_PASS_EXTERNAL_PROOFS_UNVERIFIED",
          "SYNTHETIC_FIXTURE_FAILED")
    negatives = {
        "wrong_source": ("source_snapshot_commit", "0" * 40),
        "wrong_policy": ("source_policy_git_blob", "0" * 40),
        "wrong_scope": ("checkpoint", "RW1-05_C1"),
        "old_holdout": ("old_holdout_reused", True),
        "premature_generation": ("holdout_generated", True),
        "producer_raw_seen": ("producer_raw_observed", True),
        "fake_done": ("checkpoint_done", True),
        "secret_leak": ("seed", "SECRET_PLACEHOLDER"),
    }
    mutations = {
        **negatives,
        "missing_attempt_ref": ("attempt", {"issued_ref": None, "git_readback_verified": True}),
        "shared_project_context": ("reviewer_channel", {
            **sample["reviewer_channel"], "shared_project_context_access": True,
        }),
        "false_provider_attested": ("reviewer_channel", {
            **sample["reviewer_channel"], "provider_attested": True,
        }),
        "missing_owner_witness": ("reviewer_channel", {
            **sample["reviewer_channel"], "owner_attestation_ref": None,
        }),
        "session_local_storage": ("custody", {
            **sample["custody"], "ephemeral_storage_only": True,
        }),
        "missing_acl_proof": ("custody", {
            **sample["custody"], "producer_acl_denial_evidence_ref": None,
        }),
        "missing_retrieval": ("custody", {
            **sample["custody"], "durable_readback_verified": False,
        }),
    }
    rejected = {}
    for name, (key, value) in mutations.items():
        test = copy.deepcopy(sample)
        test[key] = value
        try:
            validate(test)
        except PreflightError as exc:
            rejected[name] = str(exc)
        else:
            raise AssertionError("FALSE_ACCEPT:" + name)
    check(len(rejected) == len(mutations), "NEGATIVES_INCOMPLETE")
    return {
        "selftest": "PASS_SYNTHETIC_ONLY",
        "negatives_rejected": rejected,
        "external_storage_verified": False,
        "independent_review_verified": False,
        "checkpoint_done": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("record", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
    else:
        if args.record is None:
            parser.error("record path is required without --self-test")
        print(json.dumps(validate(json.loads(args.record.read_text(encoding="utf-8"))),
                         sort_keys=True))


if __name__ == "__main__":
    main()
