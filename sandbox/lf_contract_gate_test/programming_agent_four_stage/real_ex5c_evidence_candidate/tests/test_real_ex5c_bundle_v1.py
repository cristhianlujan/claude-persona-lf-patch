"""Offline negative probes for pinned real Ex5C fixture.

No model, network, Supabase or production services. The real-fixture tests
remain explicitly SKIPPED until an independently reviewed bundle SHA is
recorded in this file and the exact sandbox bundle is copied into fixtures.
"""
from __future__ import annotations

import base64
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

import pytest

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "tools"))

from pg07_real_worker_evidence_adapter_v1 import (
    EvidenceBlocked, cost_decision, load_bundle, sha256
)

BUNDLE = BASE / "fixtures" / "lf-evidence-bundle-v1.json"
# Must be set from the independent sandbox workflow artifact only.
# Do not derive this pin dynamically from whatever file happens to be here.
EXPECTED_BUNDLE_SHA256 = None


def real_fixture(tmp_path):
    if EXPECTED_BUNDLE_SHA256 is None or not BUNDLE.is_file():
        pytest.skip("REAL_BUNDLE_NOT_READY: merge sandbox PR and pin exact artifact SHA")
    raw = BUNDLE.read_bytes()
    assert sha256(raw) == EXPECTED_BUNDLE_SHA256, "FIXTURE_PIN_MISMATCH"
    return json.loads(raw)


def serialize(data):
    return (json.dumps(data, sort_keys=True, ensure_ascii=False,
                       separators=(",", ":")) + "\n").encode("utf-8")


def run_candidate(tmp_path, data, *, repin=True):
    raw = serialize(data)
    p = tmp_path / "mutated-real-bundle.json"
    p.write_bytes(raw)
    expected = sha256(raw) if repin else EXPECTED_BUNDLE_SHA256
    return load_bundle(p, expected)


def test_missing_pin_blocks(tmp_path):
    p = tmp_path / "bundle.json"
    p.write_bytes(b"{}")
    with pytest.raises(EvidenceBlocked, match="BLOCK_PIN_REQUIRED"):
        load_bundle(p, "")


@pytest.mark.parametrize("value,verdict", [
    ("0.070022", "REPORTED_WITHIN_BUDGET_UNVERIFIED"),
    ("0.28", "WARN"),
    ("0.35", "REQUIRES_DECISION"),
])
def test_budget_thresholds(value, verdict):
    raw = json.dumps({"total_estimated_usd": value}).encode()
    assert cost_decision(raw)["verdict"] == verdict


def test_over_budget_blocks():
    with pytest.raises(EvidenceBlocked, match="BLOCK_COST_EXCEEDED"):
        cost_decision(b'{"total_estimated_usd":"0.350001"}')


def test_real_bundle_and_reported_checks(tmp_path):
    data = real_fixture(tmp_path)
    p = tmp_path / "real.json"
    p.write_bytes(serialize(data))
    result = load_bundle(p, EXPECTED_BUNDLE_SHA256)
    assert result["_derived"]["git_subtree_verified_from_bytes"] is True
    assert result["_derived"]["raw_commit_oid_verified_from_bytes"] is True
    assert result["_derived"]["maven_result"] == "REPORTED_PASS_UNVERIFIED"
    assert result["_derived"]["cost_decision"]["verdict"] == "REPORTED_WITHIN_BUDGET_UNVERIFIED"


@pytest.mark.parametrize("mutation,reason", [
    ("patch_byte", "BLOCK_PATCH_SHA"),
    ("stdout_digest", "BLOCK_DIGEST_MAVEN_STDOUT"),
    ("stdout_body", "BLOCK_DIGEST_MAVEN_STDOUT"),
    ("nonzero_exit_pass", "BLOCK_MAVEN_EXIT_OR_COMMAND"),
    ("cost_above", "BLOCK_COST_EXCEEDED"),
    ("missing_hunk_requirement", "BLOCK_HUNK_REQUIREMENT_MISSING"),
    ("missing_requirement_coverage", "BLOCK_REQUIREMENT_WITHOUT_HUNK"),
    ("blob_mutation", "BLOCK_BLOB_OID"),
    ("tree_mutation", "BLOCK_GIT_IDENTITY"),
    ("raw_commit_mutation", "BLOCK_COMMIT_OID"),
    ("authority_even_rehashed", "BLOCK_AUTHORITY_INJECTED"),
])
def test_mutations_block_at_exact_evidence_consumer(tmp_path, mutation, reason):
    data = real_fixture(tmp_path)
    d = deepcopy(data)
    if mutation == "patch_byte":
        p = d["patch"]
        raw = bytearray(base64.b64decode(p["text_base64"]))
        raw[len(raw) // 2] ^= 1
        p["text_base64"] = base64.b64encode(raw).decode()
    elif mutation == "stdout_digest":
        d["execution"]["maven_verify"]["stdout_sha256"] = "0" * 64
    elif mutation == "stdout_body":
        p = d["execution"]["maven_verify"]
        raw = bytearray(base64.b64decode(p["stdout_base64"]))
        raw[0:1] = b"X"
        p["stdout_base64"] = base64.b64encode(raw).decode()
    elif mutation == "nonzero_exit_pass":
        d["execution"]["maven_verify"]["exit_code"] = 1
    elif mutation == "cost_above":
        p = d["worker"]["receipts"]["cost.json"]
        cost = json.loads(base64.b64decode(p["content_base64"]))
        cost["total_estimated_usd"] = "0.36"
        raw = json.dumps(cost, sort_keys=True).encode()
        p.update(content_base64=base64.b64encode(raw).decode(),
                 sha256=sha256(raw), bytes=len(raw))
    elif mutation == "missing_hunk_requirement":
        d["patch"]["hunks"][0]["requirements"] = []
    elif mutation == "missing_requirement_coverage":
        for h in d["patch"]["hunks"]:
            h["requirements"] = [r for r in h["requirements"] if r != "REM-C7"]
    elif mutation == "blob_mutation":
        p = d["files"][0]
        raw = bytearray(base64.b64decode(p["content_base64"]))
        raw[0] ^= 1
        p["content_base64"] = base64.b64encode(raw).decode()
    elif mutation == "tree_mutation":
        d["git"]["subtree_oid"] = "0" * 40
    elif mutation == "raw_commit_mutation":
        p = d["git"]
        raw = bytearray(base64.b64decode(p["raw_commit_base64"]))
        raw[0] ^= 1
        p["raw_commit_base64"] = base64.b64encode(raw).decode()
    elif mutation == "authority_even_rehashed":
        d["production_authority"] = True
    with pytest.raises(EvidenceBlocked, match=reason):
        run_candidate(tmp_path, d)


def test_replaced_bundle_different_sha_blocks_even_if_rehashed(tmp_path):
    d = real_fixture(tmp_path)
    d["evidence_kind"] = "OTHER"
    with pytest.raises(EvidenceBlocked, match="BLOCK_BUNDLE_SHA"):
        run_candidate(tmp_path, d, repin=False)
