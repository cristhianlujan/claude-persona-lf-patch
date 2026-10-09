#!/usr/bin/env python3
"""M7.13 checkpoint 3. Independent negative for any new IG release-quality gate.

Consumes the exact two declared Supabase SQL query results transported by the
runner; never queries a public network or manufactures a passing DB readback.
Mutation controls exercise rejection of false negatives.
"""
from __future__ import annotations
import argparse
import json
import re

OWN_GATE = re.compile(r"(?:IG[_-]?RELEASE|RELEASE[_-]?QUALITY|M7[_-]?13)", re.I)


def enforce(snapshot: dict) -> None:
    if snapshot.get("evidence_transport") != "SUPABASE_LIVE_READBACK":
        raise ValueError("LIVE_EVIDENCE_REQUIRED")
    rows = snapshot.get("gates")
    if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
        raise ValueError("GATE_ROWS_INVALID")
    if len(rows) != snapshot.get("gate_count"):
        raise ValueError("PARTIAL_GATE_READBACK")
    for item in rows:
        code = item.get("gate_codigo")
        if not isinstance(code, str) or not code:
            raise ValueError("GATE_CODE_INVALID")
        if OWN_GATE.search(code):
            raise ValueError("OWN_IG_RELEASE_GATE_FORBIDDEN")
    if type(snapshot.get("release_quality_gate_function_count")) is not int:
        raise ValueError("FUNCTION_COUNT_INVALID")
    if snapshot["release_quality_gate_function_count"] != 0:
        raise ValueError("RELEASE_QUALITY_GATE_FUNCTION_FORBIDDEN")


def run(snapshot: dict) -> None:
    enforce(snapshot)
    for poisoned, expected in (
        ({**snapshot, "release_quality_gate_function_count": 1}, "RELEASE_QUALITY_GATE_FUNCTION_FORBIDDEN"),
        ({**snapshot, "gates": snapshot["gates"] + [{"gate_codigo": "IG_RELEASE_QUALITY_GATE"}],
          "gate_count": snapshot["gate_count"] + 1}, "OWN_IG_RELEASE_GATE_FORBIDDEN"),
        ({**snapshot, "gate_count": snapshot["gate_count"] + 1}, "PARTIAL_GATE_READBACK"),
        ({**snapshot, "evidence_transport": "UNTRUSTED"}, "LIVE_EVIDENCE_REQUIRED"),
    ):
        try:
            enforce(poisoned)
        except ValueError as exc:
            assert str(exc) == expected, (str(exc), expected)
        else:
            raise AssertionError("ADVERSARIAL_NEGATIVE_NOT_REJECTED")
    print("PASS_M713_NO_OWN_GATE_NEGATIVE live_gate_count=%d prohibited=0 mutations_rejected=4" % len(snapshot["gates"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--live-json", required=True)
    args = parser.parse_args()
    run(json.loads(args.live_json))
