#!/usr/bin/env python3
"""RW1-06 C1: fail-closed public commitment/Git ordering, advisory V2.

Validates actual immutable Git objects. Does not read secret case bodies,
prove independent custody, attest a provider, or close any checkpoint.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

REPO = "cristhianlujan/claude-persona-lf-patch"
SOURCE = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
POLICY = "138efc3285ee5226c107827c66f84ced6be4afcb"
SHA40 = re.compile(r"^[a-f0-9]{40}$")
SHA64 = re.compile(r"^[a-f0-9]{64}$")
ATTEMPT_PATH = "docs/programming-agent/router_wave/RW1_06_C1_CAPTURE_ATTEMPT_V2_001.json"
PREFIX = "docs/programming-agent/router_wave/"


class PrecommitGap(ValueError):
    pass


def check(ok, code):
    if not ok:
        raise PrecommitGap(code)


def git(root, *args, allowed=(0,)):
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True, check=False, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PrecommitGap("GIT_READBACK_UNAVAILABLE") from exc
    check(proc.returncode in allowed, "GIT_READBACK_UNAVAILABLE")
    return proc.stdout


def read_git_json(root, commit, path):
    check(SHA40.fullmatch(commit or "") is not None, "COMMIT_ID_INVALID")
    check(path.startswith(PREFIX) and path.endswith(".json")
          and all(part not in ("", ".", "..") for part in path.split("/")),
          "PUBLIC_COMMIT_PATH_INVALID")
    raw = git(root, "show", commit + ":" + path)
    try:
        result = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise PrecommitGap("PUBLIC_COMMIT_JSON_INVALID") from exc
    check(isinstance(result, dict), "PUBLIC_COMMIT_NOT_OBJECT")
    return result


def secret_key_in_public(obj):
    forbidden = {
        "cases", "case_bodies", "input_literal", "oracles", "private_nonce",
        "nonce", "seed", "private_key", "secret_key", "passphrase", "secret_cases"
    }
    if isinstance(obj, dict):
        return any(k in forbidden or secret_key_in_public(v) for k, v in obj.items())
    if isinstance(obj, list):
        return any(secret_key_in_public(v) for v in obj)
    return False


def validate_commitment(obj):
    check(obj.get("schema_version") ==
          "RW106_C1_ENCRYPTED_COMMITMENT_CANDIDATE_V2",
          "COMMITMENT_SCHEMA_INVALID")
    check(obj.get("checkpoint") == "RW1-06_C1", "CHECKPOINT_MISMATCH")
    check(obj.get("status") == "ENCRYPTED_LOCALLY_NOT_ADMITTED",
          "PREMATURE_COMMITMENT_ADMISSION")
    check(obj.get("source_snapshot_commit") == SOURCE and
          obj.get("source_policy_git_blob") == POLICY,
          "SOURCE_POLICY_MISMATCH")
    check(not secret_key_in_public(obj), "SECRET_MATERIAL_IN_PUBLIC_GIT")
    # Explicit allowlist: unknown top-level fields could contain undisclosed
    # private material under aliases that a denylist alone cannot recognize.
    public_fields = {
        "schema_version", "checkpoint", "status", "attempt_ref",
        "source_snapshot_commit", "source_policy_git_blob", "holdout_counts",
        "holdout_content_sha256", "holdout_manifest_sha256",
        "corpus_ciphertext_sha256", "manifest_ciphertext_sha256",
        "recipient_fingerprint", "recipient_public_key_sha256",
        "external_precommit_persisted",
        "custodian_independent_readback_verified",
        "separate_reviewer_evidence_verified",
        "provider_attested", "independent_review", "producer_raw_observed",
        "checkpoint_done",
    }
    check(set(obj) == public_fields, "PUBLIC_COMMITMENT_FIELDS_NOT_ALLOWLISTED")
    counts = obj.get("holdout_counts")
    check(isinstance(counts, dict), "COUNT_CONTRACT_MISSING")
    for field, minimum in (("valid", 12), ("invalid", 24),
                           ("novel_falsifiers", 2)):
        check(type(counts.get(field)) is int and counts[field] >= minimum,
              "HOLDOUT_MINIMUM_NOT_MET")
    for field in ("holdout_content_sha256", "holdout_manifest_sha256",
                  "corpus_ciphertext_sha256", "manifest_ciphertext_sha256",
                  "recipient_public_key_sha256"):
        check(isinstance(obj.get(field), str) and
              SHA64.fullmatch(obj[field]) is not None,
              "COMMITMENT_HASH_MISSING_OR_INVALID")
    fp = obj.get("recipient_fingerprint")
    check(isinstance(fp, str) and re.fullmatch(r"[0-9A-F]{40}", fp) is not None,
          "RECIPIENT_FINGERPRINT_INVALID")
    for field in ("external_precommit_persisted",
                  "custodian_independent_readback_verified",
                  "separate_reviewer_evidence_verified",
                  "provider_attested", "independent_review",
                  "producer_raw_observed", "checkpoint_done"):
        check(obj.get(field) is False, "SELF_ATTESTED_COMPLETION_FORBIDDEN")


def verify(root, commitment_commit, path, raw_commit=None):
    obj = read_git_json(root, commitment_commit, path)
    validate_commitment(obj)
    m = re.fullmatch(
        r"github://([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([a-f0-9]{40})/(.+)",
        obj.get("attempt_ref", ""),
    )
    check(m is not None and m.group(1) == REPO
          and m.group(3) == ATTEMPT_PATH, "ATTEMPT_REF_INVALID")
    attempt_commit = m.group(2)
    attempt = read_git_json(root, attempt_commit, ATTEMPT_PATH)
    check(attempt.get("schema_version") == "RW106_C1_CAPTURE_ATTEMPT_V2"
          and attempt.get("checkpoint") == "RW1-06_C1"
          and attempt.get("source_snapshot_commit") == SOURCE
          and attempt.get("source_policy_git_blob") == POLICY
          and attempt.get("status") == "PREPARATION_ONLY"
          and attempt.get("holdout_generated") is False
          and attempt.get("checkpoint_done") is False,
          "ATTEMPT_SOURCE_OR_STAGE_INVALID")
    check(attempt_commit != commitment_commit, "COMMITMENT_NOT_AFTER_ATTEMPT")
    check(subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor",
         attempt_commit, commitment_commit], capture_output=True, timeout=10,
    ).returncode == 0, "ATTEMPT_NOT_ANCESTOR_OF_COMMITMENT")
    chronology = "PENDING_NO_PRODUCER_RAW"
    if raw_commit is not None:
        check(SHA40.fullmatch(raw_commit) is not None, "PRODUCER_RAW_COMMIT_INVALID")
        check(raw_commit != commitment_commit, "RAW_EQUALS_COMMITMENT")
        check(subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor",
             commitment_commit, raw_commit], capture_output=True, timeout=10,
        ).returncode == 0, "PRECOMMIT_NOT_BEFORE_PRODUCER_RAW")
        chronology = "GIT_COMMIT_ANCESTRY_PASS"
    return {
        "schema_version": "RW106_C1_PRECOMMIT_GIT_READBACK_VERDICT_V2",
        "checkpoint": "RW1-06_C1",
        "structural_git_readback": "PASS_LOCAL_GIT_ONLY",
        "precommit_to_raw_order": chronology,
        "verified_digest_fields": 5,
        "secret_case_bodies_read": False,
        "holdout_content_sha256_verified": False,
        "custodian_integrity_verified": False,
        "reviewer_separation_verified": False,
        "provider_attested": False,
        "independent_review": False,
        "checkpoint_done": False,
        "material_admission": "GAP",
    }


def selftest():
    with tempfile.TemporaryDirectory(prefix="rw106_public_gate_") as tmp:
        root = Path(tmp)
        def run(*args):
            return git(root, *args).decode("utf-8").strip()
        run("init", "-q")
        run("config", "user.name", "RW106 CI")
        run("config", "user.email", "ci@example.invalid")
        def commit_json(path, obj, message):
            p = root / path
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(obj, sort_keys=True) + "\n", encoding="utf-8")
            run("add", path)
            run("commit", "-qm", message)
            return run("rev-parse", "HEAD")
        attempt = {
            "schema_version": "RW106_C1_CAPTURE_ATTEMPT_V2",
            "checkpoint": "RW1-06_C1", "status": "PREPARATION_ONLY",
            "source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
            "holdout_generated": False, "checkpoint_done": False,
        }
        base = commit_json(ATTEMPT_PATH, attempt, "attempt")
        pubpath = PREFIX + "RW1_06_C1_PUBLIC_COMMITMENT_FIXTURE.json"
        receipt = {
            "schema_version": "RW106_C1_ENCRYPTED_COMMITMENT_CANDIDATE_V2",
            "checkpoint": "RW1-06_C1", "status": "ENCRYPTED_LOCALLY_NOT_ADMITTED",
            "source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
            "attempt_ref": "github://" + REPO + "@" + base + "/" + ATTEMPT_PATH,
            "holdout_counts": {"valid": 13, "invalid": 26, "novel_falsifiers": 2},
            "recipient_fingerprint": "A" * 40,
        }
        for field in ("holdout_content_sha256", "holdout_manifest_sha256",
                      "corpus_ciphertext_sha256", "manifest_ciphertext_sha256",
                      "recipient_public_key_sha256"):
            receipt[field] = hashlib.sha256(field.encode()).hexdigest()
        for field in ("external_precommit_persisted",
                      "custodian_independent_readback_verified",
                      "separate_reviewer_evidence_verified",
                      "provider_attested", "independent_review",
                      "producer_raw_observed", "checkpoint_done"):
            receipt[field] = False
        precommit = commit_json(pubpath, receipt, "public precommit")
        raw = commit_json(PREFIX + "RW1_06_C2_RAW_FIXTURE.json",
                          {"fixture": True}, "producer raw")
        check(verify(root, precommit, pubpath)["precommit_to_raw_order"] ==
              "PENDING_NO_PRODUCER_RAW", "PRECOMMIT_POSITIVE_FAILED")
        check(verify(root, precommit, pubpath, raw)["precommit_to_raw_order"] ==
              "GIT_COMMIT_ANCESTRY_PASS", "RAW_ANCESTRY_POSITIVE_FAILED")
        negatives = {}
        mutations = {
            "insufficient_count": {"holdout_counts": {
                "valid": 11, "invalid": 26, "novel_falsifiers": 2}},
            "missing_hash": {"holdout_manifest_sha256": None},
            "secret_in_public": {"cases": [{"input": "secret"}]},
            "secret_alias_in_public": {"secret_bundle": "leaked-private-content"},
            "false_provider_attestation": {"provider_attested": True},
            "premature_done": {"checkpoint_done": True},
            "wrong_attempt_identity": {"attempt_ref": "github://" + REPO +
                                      "@" + "0"*40 + "/" + ATTEMPT_PATH},
        }
        for name, change in mutations.items():
            modified = copy.deepcopy(receipt)
            modified.update(change)
            testsha = commit_json(pubpath, modified, name)
            try:
                verify(root, testsha, pubpath)
            except PrecommitGap as exc:
                negatives[name] = str(exc)
            else:
                raise AssertionError("FALSE_ACCEPT:" + name)
        for name, commit, rawsha in (
            ("raw_equal_commitment", precommit, precommit),
            ("raw_before_commitment", precommit, base),
        ):
            try:
                verify(root, commit, pubpath, rawsha)
            except PrecommitGap as exc:
                negatives[name] = str(exc)
            else:
                raise AssertionError("FALSE_ACCEPT:" + name)
        check(len(negatives) == 9, "NEGATIVES_INCOMPLETE")
        return {
            "selftest": "PASS_SYNTHETIC_ONLY",
            "negative_count": len(negatives),
            "negatives": negatives,
            "real_public_commitment_observed": False,
            "real_holdout_verified": False,
            "checkpoint_done": False,
        }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--git-root", type=Path)
    p.add_argument("--public-commit", type=str)
    p.add_argument("--public-path", type=str)
    p.add_argument("--producer-raw-commit", type=str)
    args = p.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return
    if not args.git_root or not args.public_commit or not args.public_path:
        p.error("--git-root --public-commit --public-path required")
    print(json.dumps(verify(args.git_root, args.public_commit,
                            args.public_path, args.producer_raw_commit),
                     sort_keys=True))


if __name__ == "__main__":
    main()
