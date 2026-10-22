#!/usr/bin/env python3
"""Offline RW1-06 C1 GnuPG ciphertext carrier. No secret keys or external writes.

Actual use MUST run under a separate reviewer/custodian, not the producer context.
Public output is a digest candidate only, not provider attestation or C1 closure.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

SOURCE = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
POLICY = "138efc3285ee5226c107827c66f84ced6be4afcb"
FAMILIES = {f"F{i:02d}" for i in range(1, 14)}
FPR = re.compile(r"[0-9A-F]{40}")
ATTEMPT = re.compile(
    r"github://cristhianlujan/claude-persona-lf-patch@[a-f0-9]{40}/"
    r"docs/programming-agent/router_wave/[A-Za-z0-9_/-]+\.json"
)


class SealError(ValueError):
    pass


def require(ok, code):
    if not ok:
        raise SealError(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def gpg(home, *args, input_bytes=None):
    try:
        result = subprocess.run(
            ["gpg", "--homedir", str(home), "--batch", "--no-tty", "--yes", *args],
            input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=45, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SealError("GPG_UNAVAILABLE") from exc
    require(result.returncode == 0, "GPG_OPERATION_FAILED")
    return result.stdout


def private_doc(data, schema, attempt):
    try:
        obj = json.loads(data.decode("utf-8"))
    except (UnicodeError, ValueError) as exc:
        raise SealError("PRIVATE_JSON_INVALID") from exc
    require(isinstance(obj, dict), "PRIVATE_DOCUMENT_INVALID")
    require(obj.get("schema_version") == schema, "PRIVATE_SCHEMA_MISMATCH")
    require(obj.get("source_snapshot_commit") == SOURCE
            and obj.get("source_policy_git_blob") == POLICY, "SOURCE_POLICY_MISMATCH")
    require(obj.get("attempt_ref") == attempt, "ATTEMPT_REF_MISMATCH")
    return obj


def inspect(corpus_bytes, manifest_bytes, attempt):
    require(ATTEMPT.fullmatch(attempt or "") is not None, "ATTEMPT_INVALID")
    c = private_doc(corpus_bytes, "RW106_C1_CORPUS_PRIVATE_V2", attempt)
    m = private_doc(manifest_bytes, "RW106_C1_MANIFEST_PRIVATE_V2", attempt)
    cases, oracles = c.get("cases"), m.get("oracles")
    require(isinstance(cases, list) and isinstance(oracles, list), "MISSING_CASE_ORACLE_LIST")
    require(isinstance(m.get("private_nonce"), str)
            and len(m["private_nonce"]) >= 16, "PRIVATE_NONCE_MISSING")
    require(m.get("oracles_declared_before_producer_raw") is True
            and m.get("producer_raw_observed") is False, "ORACLE_TIMING_GAP")
    ids, families = set(), set()
    counts = {"VALID": 0, "INVALID": 0, "FALSIFIER": 0}
    for item in cases:
        require(isinstance(item, dict), "CASE_INVALID")
        name = item.get("case_id")
        require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]{3,80}", name)
                and name not in ids, "CASE_DUPLICATE_OR_INVALID")
        ids.add(name)
        require(item.get("family_id") in FAMILIES, "CASE_FAMILY_UNKNOWN")
        families.add(item["family_id"])
        require(item.get("kind") in counts, "CASE_KIND_UNKNOWN")
        counts[item["kind"]] += 1
        require(isinstance(item.get("input"), str) and item["input"].strip(),
                "CASE_INPUT_MISSING")
    require(counts["VALID"] >= 12 and counts["INVALID"] >= 24
            and counts["FALSIFIER"] >= 2, "CASE_MINIMUM_GAP")
    require(families == FAMILIES, "FAMILY_COVERAGE_GAP")
    require(len(oracles) == len(ids), "ORACLE_CARDINALITY_GAP")
    seen = set()
    for oracle in oracles:
        require(isinstance(oracle, dict), "ORACLE_INVALID")
        ref = oracle.get("case_id")
        require(ref in ids and ref not in seen, "ORACLE_DUPLICATE_OR_MISSING")
        seen.add(ref)
        require(isinstance(oracle.get("expected_action"), str)
                and len(oracle["expected_action"].strip()) >= 3, "ORACLE_ACTION_MISSING")
        require(oracle.get("severity") in {"LOW", "MEDIUM", "HIGH", "CRITICAL"},
                "ORACLE_SEVERITY_MISSING")
    return {"valid": counts["VALID"], "invalid": counts["INVALID"],
            "novel_falsifiers": counts["FALSIFIER"]}


def load_recipient(home, public_key, fingerprint):
    require(FPR.fullmatch(fingerprint or "") is not None, "FINGERPRINT_INVALID")
    require(0 < len(public_key) < 256000, "PUBLIC_KEY_INVALID")
    gpg(home, "--import", input_bytes=public_key)
    listed = gpg(home, "--with-colons", "--fingerprint", "--list-keys").decode()
    present = {x.split(":")[9].upper() for x in listed.splitlines()
               if x.startswith("fpr:")}
    require(fingerprint in present, "RECIPIENT_FINGERPRINT_MISMATCH")
    secret = gpg(home, "--with-colons", "--list-secret-keys").decode()
    require(not any(x.startswith(("sec:", "ssb:")) for x in secret.splitlines()),
            "PRIVATE_KEY_FOUND_IN_ENCRYPTOR")


def seal(corpus_path, manifest_path, public_key_path, output_dir, fingerprint, attempt):
    inputs = (corpus_path, manifest_path, public_key_path)
    require(all(p.is_file() and not p.is_symlink() for p in inputs), "INPUT_MISSING_OR_LINK")
    require(len({p.resolve() for p in inputs}) == 3, "INPUT_PATH_ALIAS")
    require(output_dir.is_dir() and not output_dir.is_symlink(), "OUTPUT_DIRECTORY_MISSING")
    targets = [output_dir / name for name in
               ("corpus.gpg", "manifest.gpg", "commitment_candidate.json")]
    require(all(not t.exists() for t in targets), "OUTPUT_ALREADY_EXISTS")
    corpus, manifest, pubkey = (p.read_bytes() for p in inputs)
    counts = inspect(corpus, manifest, attempt)
    try:
        with tempfile.TemporaryDirectory(prefix="rw106_gpg_public_only_") as temporary:
            home = Path(temporary)
            os.chmod(home, 0o700)
            load_recipient(home, pubkey, fingerprint)
            for source, target in zip(inputs[:2], targets[:2]):
                gpg(home, "--trust-model", "always", "--no-encrypt-to",
                    "--recipient", fingerprint, "--output", str(target),
                    "--encrypt", str(source))
                require(target.is_file() and target.stat().st_size > 32,
                        "CIPHERTEXT_EMPTY")
                os.chmod(target, 0o600)
    except Exception:
        for target in targets:
            target.unlink(missing_ok=True)
        raise
    candidate = {
        "schema_version": "RW106_C1_ENCRYPTED_COMMITMENT_CANDIDATE_V2",
        "checkpoint": "RW1-06_C1", "status": "ENCRYPTED_LOCALLY_NOT_ADMITTED",
        "attempt_ref": attempt, "source_snapshot_commit": SOURCE,
        "source_policy_git_blob": POLICY, "holdout_counts": counts,
        "holdout_content_sha256": digest(corpus),
        "holdout_manifest_sha256": digest(manifest),
        "corpus_ciphertext_sha256": digest(targets[0].read_bytes()),
        "manifest_ciphertext_sha256": digest(targets[1].read_bytes()),
        "recipient_fingerprint": fingerprint,
        "recipient_public_key_sha256": digest(pubkey),
        "external_precommit_persisted": False,
        "custodian_independent_readback_verified": False,
        "separate_reviewer_evidence_verified": False,
        "provider_attested": False, "independent_review": False,
        "producer_raw_observed": False, "checkpoint_done": False,
    }
    targets[2].write_text(json.dumps(candidate, sort_keys=True, indent=2) + "\n",
                          encoding="utf-8")
    return candidate



def verify_custodian(ciphertext_dir, custodian_home):
    """Run ONLY under the isolated custodian keyring; never in producer context.

    Compares stored ciphertext and decrypted plaintext bytes against an existing
    commitment candidate. Returns non-secret status, not the cases or answers.
    """
    require(ciphertext_dir.is_dir() and not ciphertext_dir.is_symlink(),
            "CIPHERTEXT_DIRECTORY_INVALID")
    require(custodian_home.is_dir() and not custodian_home.is_symlink(),
            "CUSTODIAN_KEYRING_INVALID")
    receipt_path = ciphertext_dir / "commitment_candidate.json"
    require(receipt_path.is_file(), "COMMITMENT_CANDIDATE_MISSING")
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as exc:
        raise SealError("PUBLIC_RECEIPT_INVALID") from exc
    require(isinstance(receipt, dict)
            and receipt.get("schema_version") ==
            "RW106_C1_ENCRYPTED_COMMITMENT_CANDIDATE_V2",
            "PUBLIC_RECEIPT_SCHEMA_INVALID")
    require(receipt.get("source_snapshot_commit") == SOURCE
            and receipt.get("source_policy_git_blob") == POLICY,
            "PUBLIC_RECEIPT_SOURCE_MISMATCH")
    fingerprint = receipt.get("recipient_fingerprint")
    require(isinstance(fingerprint, str)
            and FPR.fullmatch(fingerprint) is not None,
            "PUBLIC_RECIPIENT_FINGERPRINT_INVALID")
    secrets = gpg(custodian_home, "--with-colons", "--fingerprint",
                  "--list-secret-keys").decode()
    secret_fprs = {x.split(":")[9].upper() for x in secrets.splitlines()
                   if x.startswith("fpr:")}
    require(fingerprint in secret_fprs, "CUSTODIAN_RECIPIENT_KEY_UNAVAILABLE")
    checks = (
        ("corpus.gpg", "corpus_ciphertext_sha256", "holdout_content_sha256"),
        ("manifest.gpg", "manifest_ciphertext_sha256", "holdout_manifest_sha256"),
    )
    for name, ciphertext_field, plaintext_field in checks:
        path = ciphertext_dir / name
        require(path.is_file() and not path.is_symlink(),
                "CIPHERTEXT_FILE_MISSING")
        require(isinstance(receipt.get(ciphertext_field), str)
                and digest(path.read_bytes()) == receipt[ciphertext_field],
                "CIPHERTEXT_DIGEST_MISMATCH")
        recovered = gpg(custodian_home, "--decrypt", str(path))
        require(isinstance(receipt.get(plaintext_field), str)
                and digest(recovered) == receipt[plaintext_field],
                "PLAINTEXT_DIGEST_MISMATCH")
    return {
        "validation": "CUSTODIAN_CIPHERTEXT_AND_PLAINTEXT_HASH_READBACK",
        "checkpoint": "RW1-06_C1",
        "cryptographic_integrity": "PASS_LOCAL",
        "producer_plaintext_access_denied_evidence": "NOT_PROVEN",
        "custodian_independence_evidence": "NOT_PROVEN",
        "external_precommit_persisted": False,
        "provider_attested": False,
        "checkpoint_done": False,
    }


def selftest():
    with tempfile.TemporaryDirectory(prefix="rw106_gpg_fixture_") as temp:
        root = Path(temp)
        custodian, output = root / "custodian", root / "output"
        custodian.mkdir(mode=0o700)
        output.mkdir()
        # Synthetic key only; never claim a provider-bound real independent custodian.
        gpg(custodian, "--pinentry-mode", "loopback", "--passphrase", "",
            "--quick-generate-key", "RW106 CI Fixture <ci@example.invalid>",
            "default", "default", "0")
        listing = gpg(custodian, "--with-colons", "--fingerprint", "--list-keys").decode()
        fingerprint = next(x.split(":")[9] for x in listing.splitlines()
                           if x.startswith("fpr:")).upper()
        pub = root / "recipient.asc"
        pub.write_bytes(gpg(custodian, "--armor", "--export", fingerprint))
        attempt = ("github://cristhianlujan/claude-persona-lf-patch@"
                   + "a" * 40 + "/docs/programming-agent/router_wave/attempt.json")
        base = {"source_snapshot_commit": SOURCE,
                "source_policy_git_blob": POLICY, "attempt_ref": attempt}
        cases = [{"case_id": f"CASE_{i:03}", "family_id": f"F{(i%13)+1:02d}",
                  "kind": "VALID" if i < 13 else "INVALID" if i < 39 else "FALSIFIER",
                  "input": f"Private synthetic input {i}"} for i in range(41)]
        c = {**base, "schema_version": "RW106_C1_CORPUS_PRIVATE_V2", "cases": cases}
        m = {**base, "schema_version": "RW106_C1_MANIFEST_PRIVATE_V2",
             "private_nonce": "SYNTHETIC_NONCE_NO_REAL_HOLDOUT",
             "oracles_declared_before_producer_raw": True,
             "producer_raw_observed": False,
             "oracles": [{"case_id": x["case_id"], "expected_action": "BLOCK_EFFECT",
                         "severity": "HIGH"} for x in cases]}
        cpath, mpath = root / "corpus.private.json", root / "manifest.private.json"
        cpath.write_text(json.dumps(c), encoding="utf-8")
        mpath.write_text(json.dumps(m), encoding="utf-8")
        receipt = seal(cpath, mpath, pub, output, fingerprint, attempt)
        verify = verify_custodian(output, custodian)
        require(verify["cryptographic_integrity"] == "PASS_LOCAL",
                "CUSTODIAN_DECRYPT_READBACK_MISMATCH")
        encrypted_path = output / "corpus.gpg"
        encrypted_original = encrypted_path.read_bytes()
        encrypted_path.write_bytes(encrypted_original + b"X")
        try:
            verify_custodian(output, custodian)
        except SealError as exc:
            require(str(exc) == "CIPHERTEXT_DIGEST_MISMATCH",
                    "UNEXPECTED_TAMPER_ERROR")
        else:
            raise AssertionError("FALSE_ACCEPT:TAMPERED_CIPHERTEXT")
        encrypted_path.write_bytes(encrypted_original)
        public = (output / "commitment_candidate.json").read_text()
        require("Private synthetic input" not in public
                and "SYNTHETIC_NONCE_NO_REAL_HOLDOUT" not in public
                and "BLOCK_EFFECT" not in public, "PUBLIC_SECRET_LEAK")
        negatives = {}
        for name, value in {"malformed_fingerprint": "invalid",
                            "wrong_fingerprint": "0" * 40}.items():
            with tempfile.TemporaryDirectory() as other:
                try:
                    load_recipient(Path(other), pub.read_bytes(), value)
                except SealError as exc:
                    negatives[name] = str(exc)
                else:
                    raise AssertionError("FALSE_ACCEPT:" + name)
        m["oracles_declared_before_producer_raw"] = False
        try:
            inspect(cpath.read_bytes(), json.dumps(m).encode(), attempt)
        except SealError as exc:
            negatives["late_oracles"] = str(exc)
        else:
            raise AssertionError("FALSE_ACCEPT:late_oracles")
        require(len(negatives) == 3, "NEGATIVE_COVERAGE_GAP")
        return {
            "selftest": "PASS_SYNTHETIC_ONLY", "negatives_rejected": negatives,
            "two_ciphertexts_decrypted_in_distinct_keyring": True,
            "tampered_ciphertext_rejected": True,
            "public_receipt_contains_no_synthetic_private_cases": True,
            "real_holdout_created": False, "provider_attested": False,
            "checkpoint_done": False,
        }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--custodian-home", type=Path)
    p.add_argument("--corpus", type=Path)
    p.add_argument("--manifest", type=Path)
    p.add_argument("--public-key", type=Path)
    p.add_argument("--output-dir", type=Path)
    p.add_argument("--recipient-fingerprint")
    p.add_argument("--attempt-ref")
    a = p.parse_args()
    if a.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return
    if a.custodian_home is not None:
        if a.output_dir is None:
            p.error("--output-dir required with --custodian-home")
        print(json.dumps(verify_custodian(a.output_dir, a.custodian_home),
                         sort_keys=True))
        return
    if any(x is None for x in (a.corpus, a.manifest, a.public_key,
                               a.output_dir, a.recipient_fingerprint, a.attempt_ref)):
        p.error("requires --corpus --manifest --public-key --output-dir "
                "--recipient-fingerprint --attempt-ref")
    print(json.dumps(seal(a.corpus, a.manifest, a.public_key, a.output_dir,
                          a.recipient_fingerprint.upper(), a.attempt_ref),
                     sort_keys=True))


if __name__ == "__main__":
    main()
