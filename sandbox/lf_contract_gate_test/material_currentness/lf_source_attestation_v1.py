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
ATTESTOR_SCHEMA = "LF_SOURCE_ATTESTOR_V1"
DEFAULT_ISSUER = "LF_GIT_BROKER_ATTESTOR"


def _git(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if cp.returncode != 0:
        raise RuntimeError(f"GIT_FAILED:{' '.join(args)}:{cp.stderr.strip()}")
    return cp.stdout.strip()


def _material_specs(binding: dict[str, Any]) -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    for spec in binding.get("materials") or []:
        if spec.get("kind") != "GIT_TREE":
            continue
        specs.append({
            "material_id": spec.get("material_id"),
            "kind": "GIT_TREE",
            "selectors": spec.get("selectors") or {},
            "required": bool(spec.get("required", True)),
        })
    return sorted(specs, key=lambda row: str(row.get("material_id")))


def create_attestation(*, repo: Path, repo_identity: str, authority_ref: str, resolved_revision: str,
                       binding: dict[str, Any], issuer: str = DEFAULT_ISSUER) -> dict[str, Any]:
    if not repo_identity or not authority_ref or not HEX40.fullmatch(resolved_revision or ""):
        raise ValueError("ATTESTATION_IDENTITY_OR_REVISION_INVALID")
    if not issuer:
        raise ValueError("ATTESTATION_ISSUER_MISSING")
    tree_sha = _git(repo, "show", "-s", "--format=%T", resolved_revision)
    if not HEX40.fullmatch(tree_sha):
        raise RuntimeError("ATTESTATION_TREE_SHA_INVALID")

    material_specs = _material_specs(binding)
    material_blobs: dict[str, list[dict[str, str]]] = {}
    material_fingerprints: dict[str, str] = {}
    for spec in material_specs:
        mid = spec["material_id"]
        fp, entries = git_tree_material(repo, resolved_revision, spec["selectors"], spec["required"])
        material_fingerprints[mid] = fp
        material_blobs[mid] = entries

    receipt = {
        "schema_version": "LF_SOURCE_ATTESTATION_RECEIPT_V1",
        "attestor": {"schema_version": ATTESTOR_SCHEMA, "issuer": issuer},
        "repo_identity": repo_identity,
        "authority_ref": authority_ref,
        "resolved_revision": resolved_revision,
        "commit_sha": resolved_revision,
        "tree_sha": tree_sha,
        "binding_sha256": canonical_sha256(binding),
        "material_specs": material_specs,
        "material_specs_sha256": canonical_sha256(material_specs),
        "material_fingerprints": material_fingerprints,
        "material_blobs": material_blobs,
        "network_required_for_verification": False,
        "durable_trust_anchor_required_for_reuse": True,
    }
    receipt["receipt_sha256"] = canonical_sha256(receipt)
    return receipt


def verify_attestation(*, repo: Path, receipt: dict[str, Any], expected_repo_identity: str,
                       expected_issuer: str, expected_receipt_sha256: str) -> dict[str, Any]:
    supplied = receipt.get("receipt_sha256")
    if not isinstance(expected_receipt_sha256, str) or not HEX64.fullmatch(expected_receipt_sha256):
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TRUST_ANCHOR_MISSING"}
    if supplied != expected_receipt_sha256:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TRUST_ANCHOR_MISMATCH"}

    unsigned = dict(receipt)
    unsigned.pop("receipt_sha256", None)
    if not isinstance(supplied, str) or not HEX64.fullmatch(supplied) or canonical_sha256(unsigned) != supplied:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TAMPERED"}

    attestor = receipt.get("attestor") or {}
    if attestor.get("schema_version") != ATTESTOR_SCHEMA or attestor.get("issuer") != expected_issuer:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_ISSUER_UNTRUSTED"}
    if receipt.get("repo_identity") != expected_repo_identity:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_REPO_IDENTITY_MISMATCH"}

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

    specs = receipt.get("material_specs")
    if not isinstance(specs, list) or canonical_sha256(specs) != receipt.get("material_specs_sha256"):
        return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_SPEC_TAMPERED"}

    expected_fps = receipt.get("material_fingerprints") or {}
    expected_blobs = receipt.get("material_blobs") or {}
    observed_fps: dict[str, str] = {}
    for spec in specs:
        if not isinstance(spec, dict) or spec.get("kind") != "GIT_TREE" or not spec.get("material_id"):
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_SPEC_INVALID"}
        mid = spec["material_id"]
        try:
            fp, entries = git_tree_material(repo, commit_sha, spec.get("selectors") or {}, bool(spec.get("required", True)))
        except Exception as exc:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_REDERIVATION_FAILED", "material_id": mid, "reason": str(exc)}
        observed_fps[mid] = fp
        if expected_fps.get(mid) != fp:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_FINGERPRINT_MISMATCH", "material_id": mid}
        if expected_blobs.get(mid) != entries:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_TREE_MEMBERSHIP_MISMATCH", "material_id": mid}

    if set(expected_fps) != set(observed_fps) or set(expected_blobs) != set(observed_fps):
        return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_SET_MISMATCH"}

    return {
        "ready": True,
        "decision": "ATTESTATION_VERIFIED_OFFLINE",
        "repo_identity": receipt.get("repo_identity"),
        "issuer": expected_issuer,
        "commit_sha": commit_sha,
        "tree_sha": tree_sha,
        "receipt_sha256": supplied,
        "trust_anchor_verified": True,
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
    make.add_argument("--issuer", default=DEFAULT_ISSUER)
    make.add_argument("--output", type=Path, required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--repo", type=Path, default=Path("."))
    verify.add_argument("--receipt", type=Path, required=True)
    verify.add_argument("--expected-repo-identity", required=True)
    verify.add_argument("--expected-issuer", default=DEFAULT_ISSUER)
    verify.add_argument("--expected-receipt-sha256", required=True)
    ns = ap.parse_args()

    if ns.command == "create":
        binding = json.loads(ns.binding.read_text(encoding="utf-8"))
        result = create_attestation(repo=ns.repo, repo_identity=ns.repo_identity, authority_ref=ns.authority_ref,
                                    resolved_revision=ns.resolved_revision, binding=binding, issuer=ns.issuer)
        ns.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0

    receipt = json.loads(ns.receipt.read_text(encoding="utf-8"))
    result = verify_attestation(repo=ns.repo, receipt=receipt,
                                expected_repo_identity=ns.expected_repo_identity,
                                expected_issuer=ns.expected_issuer,
                                expected_receipt_sha256=ns.expected_receipt_sha256)
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
