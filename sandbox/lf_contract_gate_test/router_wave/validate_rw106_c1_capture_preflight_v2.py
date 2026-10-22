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
import subprocess
import tempfile
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



def verify_attempt_git(repo_root: Path, attempt_ref: str, expected_repo: str) -> dict:
    """Inspect a real local Git object. This is not reviewer-isolation proof."""
    m = re.fullmatch(
        r"github://([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{40})/"
        r"(docs/programming-agent/router_wave/[A-Za-z0-9_/-]+\\.json)",
        attempt_ref,
    )
    check(m is not None, "GIT_ATTEMPT_URI_MALFORMED")
    check(m.group(1) == expected_repo, "GIT_ATTEMPT_REPO_MISMATCH")
    check(".." not in m.group(3), "GIT_ATTEMPT_PATH_INVALID")
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "show", m.group(2) + ":" + m.group(3)],
            check=False, capture_output=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise PreflightError("GIT_READBACK_UNAVAILABLE") from e
    check(result.returncode == 0, "GIT_OBJECT_MISSING")
    try:
        item = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise PreflightError("GIT_ATTEMPT_INVALID_JSON") from e
    check(isinstance(item, dict) and item.get("schema_version") ==
          "RW106_C1_CAPTURE_ATTEMPT_V2", "GIT_ATTEMPT_SCHEMA_MISMATCH")
    check(item.get("checkpoint") == "RW1-06_C1"
          and item.get("source_snapshot_commit") == SOURCE
          and item.get("source_policy_git_blob") == POLICY, "GIT_ATTEMPT_SOURCE_MISMATCH")
    check(item.get("status") == "PREPARATION_ONLY"
          and item.get("holdout_generated") is False
          and item.get("checkpoint_done") is False, "GIT_ATTEMPT_FALSE_COMPLETION")
    return {"git_readback": "PASS_LOCAL_GIT_OBJECT_ONLY",
            "independence_proven": False, "custody_proven": False}


def git_selftest() -> dict:
    """One actual temporary Git commit and four fail-closed mutations."""
    with tempfile.TemporaryDirectory(prefix="rw106_git_fixture_") as directory:
        root = Path(directory)
        def run(*arguments: str) -> str:
            p = subprocess.run(["git", "-C", str(root), *arguments],
                               capture_output=True, check=True, text=True, timeout=10)
            return p.stdout.strip()
        run("init", "-q")
        path = "docs/programming-agent/router_wave/RW1_06_C1_CAPTURE_ATTEMPT_FIXTURE.json"
        target = root / path
        target.parent.mkdir(parents=True)
        template = {"schema_version":"RW106_C1_CAPTURE_ATTEMPT_V2",
                    "checkpoint":"RW1-06_C1",
                    "source_snapshot_commit":SOURCE,"source_policy_git_blob":POLICY,
                    "status":"PREPARATION_ONLY","holdout_generated":False,
                    "checkpoint_done":False}
        target.write_text(json.dumps(template)+"\\n", encoding="utf-8")
        run("add", path)
        run("-c", "user.name=RW106-CI", "-c", "user.email=ci@example.invalid",
            "commit", "-qm", "attempt-test")
        commit = run("rev-parse", "HEAD")
        uri = "github://example/repo@" + commit + "/" + path
        check(verify_attempt_git(root, uri, "example/repo")["git_readback"] ==
              "PASS_LOCAL_GIT_OBJECT_ONLY", "GIT_POSITIVE_FIXTURE_FAILED")
        mutations = {
            "wrong_repo": (uri, "wrong/repo"),
            "unknown_commit": ("github://example/repo@" + "0" * 40 + "/" + path, "example/repo"),
            "path_traversal": ("github://example/repo@" + commit + "/docs/programming-agent/router_wave/../wrong.json", "example/repo"),
            "wrong_path": ("github://example/repo@" + commit + "/docs/programming-agent/router_wave/missing.json", "example/repo")
        }
        caught={}
        for name,(value,expected) in mutations.items():
            try:
                verify_attempt_git(root,value,expected)
            except PreflightError as e:
                caught[name] = str(e)
            else:
                raise AssertionError("GIT_FALSE_ACCEPT:" + name)
        return {"git_selftest":"PASS_SYNTHETIC_ONLY","git_negatives_rejected":caught}


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
        **git_selftest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("record", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--git-root", type=Path)
    parser.add_argument("--repo-full-name")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
    else:
        if args.record is None:
            parser.error("record path is required without --self-test")
        if args.git_root is None or args.repo_full_name is None:
            parser.error("--git-root and --repo-full-name required for non-synthetic run")
        obj = json.loads(args.record.read_text(encoding="utf-8"))
        output = validate(obj)
        output["git_object_evidence"] = verify_attempt_git(
            args.git_root, obj["attempt"]["issued_ref"], args.repo_full_name)
        print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
