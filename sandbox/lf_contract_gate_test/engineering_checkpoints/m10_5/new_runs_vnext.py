#!/usr/bin/env python3
"""M10.5 CP2: readback predicate. Never fabricates checkpoint PASS."""
import argparse
import json
import sys

EXPECTED = 13
COUNTS = ("cohort_count", "fresh_completed_count", "release_bound_count",
          "source_current_count", "validator_assessed_count",
          "edge_identity_count", "edge_provenance_receipt_count")

def classify(data):
    if not isinstance(data, dict) or data.get("schema_version") != "IG_M105_CP2_RELEASE_READBACK_V1":
        return "BLOCK_SCHEMA"
    if data.get("current_release") in (None, "", data.get("previous_release")):
        return "BLOCK_REAL_VNEXT_RELEASE_MISSING"
    if not data.get("previous_release") or not data.get("current_manifest_sha256"):
        return "BLOCK_RELEASE_PROVENANCE_MISSING"
    for key in COUNTS:
        if type(data.get(key)) is not int or data[key] != EXPECTED:
            return "BLOCK_" + key.upper()
    if data.get("scope_origin") != "M105_SCOPE_SNAPSHOT_V1":
        return "BLOCK_SCOPE"
    # Input JSON can be forged. Only the independent canonical receipt can
    # qualify CP2 as PASS; passing this predicate is NOT terminal evidence.
    return "ELIGIBLE_UNATTESTED"

def selftest():
    base = dict(schema_version="IG_M105_CP2_RELEASE_READBACK_V1",
                current_release="vNext", previous_release="vPrior",
                current_manifest_sha256="a"*64,
                scope_origin="M105_SCOPE_SNAPSHOT_V1")
    base.update({k:13 for k in COUNTS})
    assert classify(base) == "ELIGIBLE_UNATTESTED"
    for key in COUNTS:
        bad = dict(base, **{key: 0})
        assert classify(bad).startswith("BLOCK_")
    assert classify(dict(base, previous_release=None)).startswith("BLOCK_")
    assert classify(dict(base, current_release="vPrior")).startswith("BLOCK_")
    assert classify({}) == "BLOCK_SCHEMA"
    print("LOGIC_ONLY=11/11; MATERIAL_PASS=false")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--readback")
    a = p.parse_args()
    if a.self_test:
        selftest()
    else:
        if not a.readback:
            p.error("--readback required")
        with open(a.readback, encoding="utf-8") as f:
            v = classify(json.load(f))
        print(v)
        sys.exit(3 if v == "ELIGIBLE_UNATTESTED" else 2)
