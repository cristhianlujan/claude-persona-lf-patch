#!/usr/bin/env python3
"""M7.13 checkpoint 4: actual M4.9 mutation evidence negative test.

M7.7 is FUSED into M4.9. Inputs must be results of live Supabase queries
for the canonical M4.9/PAULO-063 10-case campaign. The SQL evaluator itself
is separately tested with a transactional false_pass=true mutation/ROLLBACK.
"""
from __future__ import annotations
import argparse
import copy
import json
import re


def check(data: dict) -> None:
    if data.get("source") != "SUPABASE_LIVE_READBACK" or data.get("unit") != "M4.9":
        raise AssertionError("FUSED_AUTHORITY_NOT_VERIFIED")
    if data.get("receipt_status") != "VERIFIED" or data.get("suite_status") != "PASSED":
        raise AssertionError("MUTATION_SUITE_NOT_VERIFIED")
    cases = data.get("cases")
    if not isinstance(cases, list) or len(cases) != 10:
        raise AssertionError("MUTATION_CASE_SET_INCOMPLETE")
    ids = set()
    for case in cases:
        code = case.get("test_code")
        if not isinstance(code, str) or not re.fullmatch(r"M4_9_T(?:0[1-9]|10)_[A-Z0-9_]+", code):
            raise AssertionError("MUTATION_CASE_NOT_CANONICAL")
        if code in ids:
            raise AssertionError("MUTATION_CASE_DUPLICATE")
        ids.add(code)
        if case.get("test_status") != "PASS" or case.get("assertion_status") != "PASS":
            raise AssertionError("MUTATION_CASE_NOT_PASS")
        value = case.get("actual_value")
        if not isinstance(value, dict) or value.get("detected") is not True:
            raise AssertionError("MUTATION_NOT_DETECTED")
        if value.get("false_pass") is not False:
            raise AssertionError("KNOWN_FALSE_PASS_MUST_BLOCK")
    if len(ids) != 10:
        raise AssertionError("MUTATION_COVERAGE_INCOMPLETE")


def main(data: dict) -> None:
    check(data)
    for field, expected in (("false_pass", "KNOWN_FALSE_PASS_MUST_BLOCK"),
                            ("detected", "MUTATION_NOT_DETECTED")):
        mutant = copy.deepcopy(data)
        mutant["cases"][0]["actual_value"][field] = field == "false_pass"
        try:
            check(mutant)
        except AssertionError as exc:
            assert str(exc) == expected, (str(exc), expected)
        else:
            raise AssertionError("NEGATIVE_FALSE_PASS_NOT_REJECTED")
    mutant = copy.deepcopy(data); mutant["cases"].pop()
    try:
        check(mutant)
    except AssertionError as exc:
        assert str(exc) == "MUTATION_CASE_SET_INCOMPLETE"
    else:
        raise AssertionError("NEGATIVE_MISSING_CASE_NOT_REJECTED")
    print("PASS_M713_FALSE_PASS_BLOCKS source=M4.9 cases=10 known_false_pass=0 adversarial_rejected=3")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--live-json", required=True)
    main(json.loads(parser.parse_args().live_json))
