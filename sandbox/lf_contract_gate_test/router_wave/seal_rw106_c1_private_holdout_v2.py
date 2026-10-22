#!/usr/bin/env python3
"""RW1-06 C1: local/offline private corpus sealer, without provider or custody claims.

Reads actual private bytes and emits ONLY a public digest commitment candidate.
Does not upload files or create a review; call from the private custodian runner.
GitHub precommit ordering and private durable readback are separate prerequisites.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import tempfile
from pathlib import Path

SOURCE = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
POLICY = "138efc3285ee5226c107827c66f84ced6be4afcb"
FAMILIES = {f"F{i:02d}" for i in range(1, 14)}
KINDS = ("VALID", "INVALID", "FALSIFIER")
SHA40 = re.compile(r"^[0-9a-f]{40}$")


class SealingError(ValueError):
    pass


def require(condition: bool, code: str) -> None:
    if not condition:
        raise SealingError(code)


def parse(actual_bytes: bytes, kind: str) -> dict:
    try:
        obj = json.loads(actual_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise SealingError("PRIVATE_JSON_INVALID") from e
    require(isinstance(obj, dict), "PRIVATE_ROOT_NOT_OBJECT")
    require(obj.get("schema_version") == f"RW106_C1_{kind}_PRIVATE_V2", "PRIVATE_SCHEMA_MISMATCH")
    require(obj.get("source_snapshot_commit") == SOURCE, "SOURCE_MISMATCH")
    require(obj.get("source_policy_git_blob") == POLICY, "POLICY_MISMATCH")
    return obj


def prepare(corpus_bytes: bytes, manifest_bytes: bytes, attempt_ref: str) -> dict:
    require(isinstance(attempt_ref, str)
            and re.fullmatch(r"github://[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+@([0-9a-f]{40})/.+",
                             attempt_ref) is not None, "GIT_ATTEMPT_REF_INVALID")
    corpus = parse(corpus_bytes, "CORPUS")
    manifest = parse(manifest_bytes, "MANIFEST")
    cases = corpus.get("cases")
    oracles = manifest.get("oracles")
    require(isinstance(cases, list) and isinstance(oracles, list), "CASE_ORACLE_LIST_MISSING")
    require(bool(manifest.get("private_nonce"))
            and isinstance(manifest["private_nonce"], str)
            and len(manifest["private_nonce"]) >= 16, "PRIVATE_NONCE_REQUIRED")
    require(corpus.get("attempt_ref") == attempt_ref
            and manifest.get("attempt_ref") == attempt_ref, "ATTEMPT_BINDING_MISMATCH")
    require(manifest.get("oracles_declared_before_producer_raw") is True,
            "ORACLES_NOT_PREREGISTERED")
    require(manifest.get("producer_raw_observed") is False, "RAW_ALREADY_OBSERVED")
    ids = set()
    counts = {k: 0 for k in KINDS}
    families = set()
    for item in cases:
        require(isinstance(item, dict), "CASE_NOT_OBJECT")
        case_id = item.get("case_id")
        require(isinstance(case_id, str) and re.fullmatch(r"[A-Za-z0-9_-]{3,80}", case_id)
                is not None and case_id not in ids, "CASE_ID_INVALID_OR_DUPLICATE")
        ids.add(case_id)
        family = item.get("family_id")
        require(family in FAMILIES, "CASE_UNKNOWN_FAMILY")
        families.add(family)
        kind = item.get("kind")
        require(kind in counts, "CASE_UNKNOWN_KIND")
        counts[kind] += 1
        require(isinstance(item.get("input"), str) and bool(item["input"].strip()),
                "CASE_INPUT_EMPTY")
    require(counts["VALID"] >= 12 and counts["INVALID"] >= 24 and
            counts["FALSIFIER"] >= 2, "HOLDOUT_COUNTS_INSUFFICIENT")
    require(families == FAMILIES, "TEST_FAMILY_COVERAGE_GAP")
    require(len(oracles) == len(cases), "ORACLE_COUNT_MISMATCH")
    seen = set()
    for oracle in oracles:
        require(isinstance(oracle, dict), "ORACLE_NOT_OBJECT")
        case_id = oracle.get("case_id")
        require(case_id in ids and case_id not in seen, "ORACLE_CASE_MISSING_OR_DUPLICATE")
        seen.add(case_id)
        require(isinstance(oracle.get("expected_action"), str)
                and len(oracle["expected_action"].strip()) >= 3, "EXPECTED_ACTION_MISSING")
        require(oracle.get("severity") in ("LOW", "MEDIUM", "HIGH", "CRITICAL"),
                "SEVERITY_UNDECLARED")
    require(seen == ids, "ORACLE_SET_MISMATCH")
    corpus_hash = hashlib.sha256(corpus_bytes).hexdigest()
    manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
    require(corpus_hash != manifest_hash, "DIGESTS_IDENTICAL")
    return {
        "schema_version": "RW106_C1_SEALED_DIGEST_CANDIDATE_V2",
        "checkpoint": "RW1-06_C1",
        "status": "SEALED_LOCALLY_NOT_EXTERNALLY_ADMITTED",
        "attempt_ref": attempt_ref,
        "source_snapshot_commit": SOURCE,
        "source_policy_git_blob": POLICY,
        "holdout_counts": {
            "valid": counts["VALID"],
            "invalid": counts["INVALID"],
            "novel_falsifiers": counts["FALSIFIER"],
        },
        "families_covered": len(families),
        "oracles_preregistered": len(oracles),
        "holdout_manifest_sha256": manifest_hash,
        "holdout_content_sha256": corpus_hash,
        "private_bytes_hash_verified": True,
        "external_precommit_persisted": False,
        "durable_custody_readback_verified": False,
        "separate_reviewer_evidence_verified": False,
        "provider_attested": False,
        "independent_review": False,
        "checkpoint_done": False,
        "producer_raw_observed": False,
    }


def seal(corpus_path: Path, manifest_path: Path, output: Path, attempt_ref: str) -> dict:
    require(corpus_path.is_file() and manifest_path.is_file(), "PRIVATE_FILE_MISSING")
    require(corpus_path.resolve() != manifest_path.resolve(), "SAME_PRIVATE_FILE")
    require(not output.exists(), "PUBLIC_OUTPUT_MUST_BE_NEW")
    require(output.resolve() not in {corpus_path.resolve(), manifest_path.resolve()},
            "OUTPUT_OVERWRITES_PRIVATE_INPUT")
    corpus_bytes = corpus_path.read_bytes()
    manifest_bytes = manifest_path.read_bytes()
    require(corpus_bytes and manifest_bytes, "EMPTY_PRIVATE_FILE")
    candidate = prepare(corpus_bytes, manifest_bytes, attempt_ref)
    require(hashlib.sha256(corpus_path.read_bytes()).hexdigest()
            == candidate["holdout_content_sha256"]
            and hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            == candidate["holdout_manifest_sha256"], "PRIVATE_READBACK_CHANGED")
    output.write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n",
                      encoding="utf-8")
    return candidate


def selftest() -> dict:
    attempt = "github://owner/repo@" + "a" * 40 + "/docs/public-attempt.json"
    cases = [
        {"case_id": f"T{i:03}", "family_id": f"F{(i % 13) + 1:02d}",
         "kind": "VALID" if i < 13 else "INVALID" if i < 39 else "FALSIFIER",
         "input": f"synthetic input {i}"} for i in range(41)
    ]
    base = {"source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
            "attempt_ref": attempt}
    corpus = {**base, "schema_version": "RW106_C1_CORPUS_PRIVATE_V2", "cases": cases}
    manifest = {**base, "schema_version": "RW106_C1_MANIFEST_PRIVATE_V2",
                "private_nonce": "SYNTHETIC_NONCE_ONLY",
                "oracles_declared_before_producer_raw": True,
                "producer_raw_observed": False,
                "oracles": [
                    {"case_id": c["case_id"], "expected_action": "DO_NOT_GRANT_EFFECT",
                     "severity": "HIGH"} for c in cases]}
    def encode(x: dict) -> bytes:
        return json.dumps(x, sort_keys=True).encode("utf-8")
    require(prepare(encode(corpus), encode(manifest), attempt)["status"]
            == "SEALED_LOCALLY_NOT_EXTERNALLY_ADMITTED", "SYNTHETIC_PASS_FAILED")
    mutants = {
        "source_mismatch": ({"source_snapshot_commit": "0" * 40}, {}),
        "policy_mismatch": ({"source_policy_git_blob": "0" * 40}, {}),
        "missing_family": ({"cases": cases[:12] + cases[13:]}, {}),
        "insufficient_cases": ({"cases": cases[:-3]}, {}),
        "duplicate_id": ({"cases": cases + [cases[0]]}, {}),
        "missing_oracles": ({}, {"oracles": manifest["oracles"][:-1]}),
        "wrong_attempt_ref": ({}, {"attempt_ref": "github://other/repo@" + "a"*40 + "/x"}),
        "raw_already_observed": ({}, {"producer_raw_observed": True}),
        "preregistration_false": ({}, {"oracles_declared_before_producer_raw": False}),
        "missing_nonce": ({}, {"private_nonce": ""}),
    }
    rejected = {}
    for name, (cd, md) in mutants.items():
        try:
            prepare(encode({**corpus, **cd}), encode({**manifest, **md}), attempt)
        except SealingError as e:
            rejected[name] = str(e)
        else:
            raise AssertionError("FALSE_ACCEPT:" + name)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        c, m, o = root / "private-corpus.json", root / "private-manifest.json", root / "public.json"
        c.write_bytes(encode(corpus))
        m.write_bytes(encode(manifest))
        sealed = seal(c, m, o, attempt)
        require(json.loads(o.read_text(encoding="utf-8")) == sealed,
                "OUTPUT_READBACK_MISMATCH")
        require(not any(k in o.read_text(encoding="utf-8")
                        for k in ("SYNTHETIC_NONCE_ONLY", "synthetic input", "expected_action")),
                "PUBLIC_SECRETS_LEAK")
    require(len(rejected) == len(mutants), "NEGATIVE_INCOMPLETE")
    return {
        "selftest": "PASS_SYNTHETIC_ONLY",
        "negatives_rejected": rejected,
        "private_corpus_created": False,
        "durable_private_custody_verified": False,
        "checkpoint_done": False,
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--corpus", type=Path)
    p.add_argument("--manifest", type=Path)
    p.add_argument("--output", type=Path)
    p.add_argument("--attempt-ref")
    args = p.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return
    if any(x is None for x in (args.corpus, args.manifest, args.output, args.attempt_ref)):
        p.error("--corpus --manifest --output --attempt-ref are all required")
    print(json.dumps(seal(args.corpus, args.manifest, args.output, args.attempt_ref),
                     sort_keys=True))


if __name__ == "__main__":
    main()
