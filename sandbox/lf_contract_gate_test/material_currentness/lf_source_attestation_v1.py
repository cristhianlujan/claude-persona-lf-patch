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
ISSUER = "LF_GOVERNED_GIT_BROKER_OR_ATTESTOR"
ATTESTOR_VERSION = "1.0.0-candidate"


def _git(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if cp.returncode != 0:
        raise RuntimeError(f"GIT_FAILED:{' '.join(args)}:{cp.stderr.strip()}")
    return cp.stdout.strip()


def _resolved_binding_context(binding: dict[str, Any], resolved_revision: str) -> dict[str, Any]:
    hydrated = json.loads(json.dumps(binding))
    hydrated.setdefault("authority", {})["current_revision"] = resolved_revision
    return hydrated


def _git_material_specs(binding: dict[str, Any]) -> list[dict[str, Any]]:
    specs: list[dict[str, Any]] = []
    for spec in binding.get("materials") or []:
        if not isinstance(spec, dict) or spec.get("kind") != "GIT_TREE":
            continue
        mid = spec.get("material_id")
        selectors = spec.get("selectors") or {}
        if not isinstance(mid, str) or not mid:
            raise ValueError("ATTESTATION_MATERIAL_ID_INVALID")
        specs.append({"material_id": mid, "kind": "GIT_TREE", "selectors": selectors, "required": bool(spec.get("required", True))})
    return sorted(specs, key=lambda row: row["material_id"])


def create_attestation(*, repo: Path, repo_identity: str, authority_ref: str, resolved_revision: str, binding: dict[str, Any]) -> dict[str, Any]:
    if not repo_identity or not authority_ref or not HEX40.fullmatch(resolved_revision or ""):
        raise ValueError("ATTESTATION_IDENTITY_OR_REVISION_INVALID")
    tree_sha = _git(repo, "show", "-s", "--format=%T", resolved_revision)
    if not HEX40.fullmatch(tree_sha):
        raise RuntimeError("ATTESTATION_TREE_SHA_INVALID")
    hydrated_binding = _resolved_binding_context(binding, resolved_revision)
    material_specs = _git_material_specs(hydrated_binding)
    material_blobs: dict[str, list[dict[str, str]]] = {}
    material_fingerprints: dict[str, str] = {}
    for spec in material_specs:
        mid = spec["material_id"]
        fp, entries = git_tree_material(repo, resolved_revision, spec["selectors"], bool(spec["required"]))
        material_fingerprints[mid] = fp
        material_blobs[mid] = entries
    receipt = {
        "schema_version": "LF_SOURCE_ATTESTATION_RECEIPT_V1",
        "issuer": ISSUER,
        "attestor_version": ATTESTOR_VERSION,
        "authority_level": "CANDIDATE_LOCAL_INTEGRITY",
        "durable_evidence_anchor_required": True,
        "repo_identity": repo_identity,
        "authority_ref": authority_ref,
        "resolved_revision": resolved_revision,
        "commit_sha": resolved_revision,
        "tree_sha": tree_sha,
        "binding_sha256": canonical_sha256(hydrated_binding),
        "material_specs": material_specs,
        "material_fingerprints": material_fingerprints,
        "material_blobs": material_blobs,
        "network_required_for_verification": False,
    }
    receipt["receipt_sha256"] = canonical_sha256(receipt)
    return receipt


def verify_attestation(*, repo: Path, receipt: dict[str, Any], expected_repo_identity: str, expected_authority_ref: str, expected_binding: dict[str, Any], expected_issuer: str = ISSUER) -> dict[str, Any]:
    supplied = receipt.get("receipt_sha256")
    unsigned = dict(receipt)
    unsigned.pop("receipt_sha256", None)
    if not isinstance(supplied, str) or not HEX64.fullmatch(supplied) or canonical_sha256(unsigned) != supplied:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TAMPERED"}
    if receipt.get("issuer") != expected_issuer:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_ISSUER_MISMATCH"}
    if receipt.get("repo_identity") != expected_repo_identity:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_REPO_IDENTITY_MISMATCH"}
    if receipt.get("authority_ref") != expected_authority_ref:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_AUTHORITY_REF_MISMATCH"}
    if receipt.get("authority_level") != "CANDIDATE_LOCAL_INTEGRITY" or receipt.get("durable_evidence_anchor_required") is not True:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_AUTHORITY_LEVEL_INVALID"}
    commit_sha = receipt.get("commit_sha")
    resolved_revision = receipt.get("resolved_revision")
    tree_sha = receipt.get("tree_sha")
    if not isinstance(commit_sha, str) or not HEX40.fullmatch(commit_sha) or resolved_revision != commit_sha or not isinstance(tree_sha, str) or not HEX40.fullmatch(tree_sha):
        return {"ready": False, "decision": "BLOCK_ATTESTATION_FORMAT_INVALID"}
    hydrated_binding = _resolved_binding_context(expected_binding, commit_sha)
    expected_binding_sha = canonical_sha256(hydrated_binding)
    if receipt.get("binding_sha256") != expected_binding_sha:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_BINDING_MISMATCH"}
    try:
        expected_specs = _git_material_specs(hydrated_binding)
    except ValueError:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_BINDING_MATERIAL_INVALID"}
    if receipt.get("material_specs") != expected_specs:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_BINDING_MATERIAL_SPEC_MISMATCH"}
    try:
        observed_tree = _git(repo, "show", "-s", "--format=%T", commit_sha)
    except RuntimeError:
        return {"ready": False, "decision": "BLOCK_ATTESTED_REVISION_UNAVAILABLE_OFFLINE"}
    if observed_tree != tree_sha:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_TREE_MISMATCH", "expected": tree_sha, "observed": observed_tree}
    supplied_fingerprints = receipt.get("material_fingerprints") or {}
    supplied_blobs = receipt.get("material_blobs") or {}
    for spec in expected_specs:
        mid = spec["material_id"]
        try:
            observed_fp, observed_entries = git_tree_material(repo, commit_sha, spec["selectors"], bool(spec["required"]))
        except Exception:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_RECOMPUTE_FAILED", "material_id": mid}
        if supplied_fingerprints.get(mid) != observed_fp:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_FINGERPRINT_MISMATCH", "material_id": mid}
        if supplied_blobs.get(mid) != observed_entries:
            return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_BLOB_SET_MISMATCH", "material_id": mid}
    expected_ids = {spec["material_id"] for spec in expected_specs}
    if set(supplied_fingerprints) != expected_ids:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_MATERIAL_SET_MISMATCH"}
    if set(supplied_blobs) != expected_ids:
        return {"ready": False, "decision": "BLOCK_ATTESTATION_BLOB_SET_MISMATCH"}
    return {
        "ready": True,
        "decision": "ATTESTATION_VERIFIED_OFFLINE",
        "authority_level": "CANDIDATE_LOCAL_INTEGRITY",
        "durable_evidence_anchor_required": True,
        "repo_identity": receipt.get("repo_identity"),
        "authority_ref": receipt.get("authority_ref"),
        "commit_sha": commit_sha,
        "tree_sha": tree_sha,
        "binding_sha256": expected_binding_sha,
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
    verify.add_argument("--expected-repo-identity", required=True)
    verify.add_argument("--expected-authority-ref", required=True)
    verify.add_argument("--binding", type=Path, required=True)
    ns = ap.parse_args()
    if ns.command == "create":
        binding = json.loads(ns.binding.read_text(encoding="utf-8"))
        result = create_attestation(repo=ns.repo, repo_identity=ns.repo_identity, authority_ref=ns.authority_ref, resolved_revision=ns.resolved_revision, binding=binding)
        ns.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0
    receipt = json.loads(ns.receipt.read_text(encoding="utf-8"))
    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    result = verify_attestation(repo=ns.repo, receipt=receipt, expected_repo_identity=ns.expected_repo_identity, expected_authority_ref=ns.expected_authority_ref, expected_binding=binding)
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
