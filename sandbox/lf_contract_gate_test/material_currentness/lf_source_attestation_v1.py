#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from lf_material_currentness_v1 import canonical_sha256, git_tree_material

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def _git(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if cp.returncode != 0:
        raise RuntimeError(f"GIT_FAILED:{' '.join(args)}:{cp.stderr.strip()}")
    return cp.stdout.strip()


def create_attestation(*, repo: Path, repo_identity: str, authority_ref: str, resolved_revision: str, binding: dict[str, Any]) -> dict[str, Any]:
    if not repo_identity or not authority_ref or not HEX40.fullmatch(resolved_revision or ""):
        raise ValueError("ATTESTATION_IDENTITY_OR_REVISION_INVALID")
    tree_sha = _git(repo, "show", "-s", "--format=%T", resolved_revision)
    if not HEX40.fullmatch(tree_sha):
        raise RuntimeError("ATTESTATION_TREE_SHA_INVALID")

    material_blobs: dict[str, list[dict[str, str]]] = {}
    material_fingerprints: dict[str, str] = {}
    for spec in binding.get("materials") or []:
        if spec.get("kind") != "GIT_TREE":
            continue
        mid = spec.get("material_id")
        fp, entries = git_tree_material(repo, resolved_revision, spec.get("selectors") or {}, bool(spec.get("required", True)))
        material_fingerprints[mid] = fp
        material_blobs[mid] = entries

    receipt = {
        "schema_version": "LF_SOURCE_ATTESTATION_RECEIPT_V1",
        "repo_identity": repo_identity,
        "authority_ref": authority_ref,
        "resolved_revision": resolved_revision,
        "commit_sha": resolved_revision,
        "tree_sha": tree_sha,
        "material_fingerprints": material_fingerprints,
        "material_blobs": material_blobs,
        "network_required_for_verification": False,
    }
    receipt["receipt_sha256"] = canonical_sha256(receipt)
    return receipt


def verify_attestation(*, repo: Path, receipt: dict[str, Any]) -> dict[str, Any]:
    supplied = receipt.get("receipt_sha256")
    unsigned = dict(receipt)
    unsigned.pop("receipt_sha256", None)
    if not isinstance(supplied, str) or not HEX64.fullmatch(supplied) or canonical_sha256(unsigned) != supplied:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TAMPERED"}
    commit_sha = receipt.get("commit_sha")
    tree_sha = receipt.get("tree_sha")
    if not isinstance(commit_sha, str) or not HEX40.fullmatch(commit_sha) or not isinstance(tree_sha, str) or not HEX40.fullmatch(tree_sha):
        return {"ready": False, "decision": "BLOCK_ATTESTATION_FORMAT_INVALID"}
    try:
        observed_tree = _git(repo, "show", "-s", "--format=%T", commit_sha)
    except RuntimeError:
        return {"ready": False, "decision": "BLOCK_ATTESTED_REVISION_UNAVAILABLE_OFFLINE"}
    if observed_tree != tree_sha:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TREE_MISMATCH", "expected": tree_sha, "observed": observed_tree}

    for entries in (receipt.get("material_blobs") or {}).values():
        for entry in entries:
            sha = entry.get("blob_sha1")
            if not isinstance(sha, str) or not HEX40.fullmatch(sha):
                return {"ready": False, "decision": "BLOCK_ATTESTATION_BLOB_FORMAT_INVALID"}
            cp = subprocess.run(["git", "-C", str(repo), "cat-file", "-e", sha], capture_output=True)
            if cp.returncode != 0:
                return {"ready": False, "decision": "BLOCK_ATTESTED_BLOB_UNAVAILABLE_OFFLINE", "blob_sha1": sha}
    return {
        "ready": True,
        "decision": "ATTESTATION_VERIFIED_OFFLINE",
        "repo_identity": receipt.get("repo_identity"),
        "commit_sha": commit_sha,
        "tree_sha": tree_sha,
        "receipt_sha256": supplied,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Create or verify reusable LF source attestation receipts without GitHub REST during verification.")
    sub = ap.add_subparsers(dest="command", required=True)
    make = sub.add_parser("create")
    make.add_argument("--repo", type=Path, default=Path("."))
    make.add_argument("--repo-identity", required=True)
    make.add_argument("--authority-ref", required=True)
    make.add_argument("--resolved-revision", required=True)
    make.add_argument("--binding", type=Path, required=True)
    make.add_argument("--output", type=Path, required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--repo", type=Path, default=Path("."))
    verify.add_argument("--receipt", type=Path, required=True)
    ns = ap.parse_args()

    if ns.command == "create":
        binding = json.loads(ns.binding.read_text(encoding="utf-8"))
        result = create_attestation(repo=ns.repo, repo_identity=ns.repo_identity, authority_ref=ns.authority_ref, resolved_revision=ns.resolved_revision, binding=binding)
        ns.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0

    receipt = json.loads(ns.receipt.read_text(encoding="utf-8"))
    result = verify_attestation(repo=ns.repo, receipt=receipt)
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
