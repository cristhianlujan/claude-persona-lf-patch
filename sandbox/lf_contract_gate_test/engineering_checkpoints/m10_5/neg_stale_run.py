#!/usr/bin/env python3
"""M10.5 CP5 negative readback checker.

The actual terminal checkpoint needs a governed adversarial execution with
an independently issued verification receipt. A local fixture NEVER passes CP5.
"""
import argparse
import json
import sys


def admit(case):
    """Equivalent fail-closed conjunction; logical self-test, not runtime proof."""
    if not isinstance(case, dict):
        return False
    return all(case.get(key) is True for key in (
        "fresh_vnext", "source_current", "release_bound",
        "edge_identities", "agent_edge_receipt"
    ))


def classify(readback):
    if not isinstance(readback, dict):
        return "BLOCK_SHAPE"
    if readback.get("classification") != "OBSERVATION_ONLY_NEGATIVE_TEST_REQUIRED":
        return "BLOCK_PROVENANCE"
    if type(readback.get("total_screens")) is not int or readback["total_screens"] != 13:
        return "BLOCK_COHORT"
    cases = readback.get("observed_cases")
    if not isinstance(cases, list) or len(cases) != 13:
        return "BLOCK_CASE_COUNT"
    ids = [row.get("pantalla_id") for row in cases if isinstance(row, dict)]
    if len(set(ids)) != 13:
        return "BLOCK_SCREEN_DUPLICATE"
    if any(admit(row) for row in cases):
        return "BLOCK_OBSERVED_ADMITTED_WITHOUT_ADVERSARIAL_RECEIPT"
    if any(not isinstance(row.get("source_current"), bool) or
           not isinstance(row.get("fresh_vnext"), bool) or
           not isinstance(row.get("release_bound"), bool)
           for row in cases):
        return "BLOCK_UNTYPED_CASE"
    # Source observation alone is never a real executed negative test.
    return "OBSERVED_NOT_MATERIAL_TEST"


def self_test():
    good = dict(fresh_vnext=True, source_current=True, release_bound=True,
                edge_identities=True, agent_edge_receipt=True)
    assert admit(good)
    for dimension in tuple(good):
        case = dict(good, **{dimension: False})
        assert not admit(case), dimension
    cases = [dict(pantalla_id=i, **{**good, "fresh_vnext": False})
             for i in range(1, 14)]
    readback = dict(classification="OBSERVATION_ONLY_NEGATIVE_TEST_REQUIRED",
                    total_screens=13, observed_cases=cases)
    assert classify(readback) == "OBSERVED_NOT_MATERIAL_TEST"
    assert classify(dict(readback, total_screens=12)) == "BLOCK_COHORT"
    assert classify(dict(readback, observed_cases=cases[:-1])) == "BLOCK_CASE_COUNT"
    assert classify(dict(readback, classification="VERIFIED")) == "BLOCK_PROVENANCE"
    assert classify(dict(readback, observed_cases=[good]*13)) == "BLOCK_SCREEN_DUPLICATE"
    print("LOGICAL_POSITIVE_AND_NEGATIVES=11/11; MATERIAL_CP5_PASS=false")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--readback")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if not args.readback:
            parser.error("--readback is required")
        with open(args.readback, encoding="utf-8") as fp:
            result = classify(json.load(fp))
        print(result)
        sys.exit(3 if result == "OBSERVED_NOT_MATERIAL_TEST" else 2)
