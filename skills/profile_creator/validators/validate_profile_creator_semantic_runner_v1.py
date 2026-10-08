#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REQUIRED = {
    "schema","status","execution_surface","producer","case_id","run_id",
    "producer_source_ref","producer_source_sha","profile_snapshot_sha","input_sha256",
    "raw_output_ref","raw_output_sha256","runtime_model_stamp",
    "fresh_context","profile_source_write_executed","runtime_activation","production_activation",
}
SHA40 = set("0123456789abcdef")
SHA64 = set("0123456789abcdef")
FORBIDDEN = {
    "DIRECT_LLAMA_SERVER",
    "SYNTHETIC_OUTPUT_GENERATOR",
    "REUSED_PRIOR_RAW",
    "UNBOUND_GENERIC_MODEL_CALL",
    "PROFILE_RUNTIME_AS_IMPLICIT_PROFILE_CREATOR",
}


def _hex(value: Any, n: int, alphabet: set[str]) -> bool:
    return isinstance(value, str) and len(value) == n and all(ch in alphabet for ch in value)


def evaluate(receipt: dict[str, Any]) -> dict[str, Any]:
    blockers: list[str] = []
    if not isinstance(receipt, dict):
        return {"schema":"PROFILE_CREATOR_SEMANTIC_RUNNER_VALIDATION_V1","status":"FAIL","blocking_codes":["RECEIPT_NOT_OBJECT"]}

    missing = sorted(REQUIRED - set(receipt))
    blockers.extend(f"RECEIPT_FIELD_MISSING:{x}" for x in missing)

    if receipt.get("schema") != "PROFILE_CREATOR_SEMANTIC_RUNNER_RECEIPT_V1":
        blockers.append("RUNNER_RECEIPT_SCHEMA_INVALID")
    if receipt.get("status") != "READY":
        blockers.append("RUNNER_NOT_READY")
    if receipt.get("producer") != "PROFILE_CREATOR":
        blockers.append("RUNNER_PRODUCER_INVALID")
    surface = receipt.get("execution_surface")
    if surface in FORBIDDEN:
        blockers.append(f"RUNNER_EXECUTION_SURFACE_FORBIDDEN:{surface}")
    if surface != "GOVERNED_PROFILE_CREATOR_WORKER":
        blockers.append("RUNNER_EXECUTION_SURFACE_NOT_GOVERNED_PROFILE_CREATOR")
    if receipt.get("fresh_context") is not True:
        blockers.append("RUNNER_FRESH_CONTEXT_REQUIRED")
    if receipt.get("profile_source_write_executed") is not False:
        blockers.append("RUNNER_PROFILE_SOURCE_WRITE_FORBIDDEN")
    if receipt.get("runtime_activation") is not False:
        blockers.append("RUNNER_RUNTIME_ACTIVATION_FORBIDDEN")
    if receipt.get("production_activation") is not False:
        blockers.append("RUNNER_PRODUCTION_ACTIVATION_FORBIDDEN")

    if not _hex(receipt.get("producer_source_sha"), 40, SHA40):
        blockers.append("RUNNER_PRODUCER_SOURCE_SHA_INVALID")
    if not _hex(receipt.get("profile_snapshot_sha"), 40, SHA40):
        blockers.append("RUNNER_PROFILE_SNAPSHOT_SHA_INVALID")
    if not _hex(receipt.get("input_sha256"), 64, SHA64):
        blockers.append("RUNNER_INPUT_SHA256_INVALID")
    if not _hex(receipt.get("raw_output_sha256"), 64, SHA64):
        blockers.append("RUNNER_RAW_OUTPUT_SHA256_INVALID")
    if not isinstance(receipt.get("raw_output_ref"), str) or not receipt.get("raw_output_ref","").strip():
        blockers.append("RUNNER_RAW_OUTPUT_REF_REQUIRED")
    if not isinstance(receipt.get("runtime_model_stamp"), dict) or not receipt["runtime_model_stamp"]:
        blockers.append("RUNNER_RUNTIME_MODEL_STAMP_REQUIRED")
    if not isinstance(receipt.get("case_id"), str) or not receipt.get("case_id"):
        blockers.append("RUNNER_CASE_ID_REQUIRED")
    if not isinstance(receipt.get("run_id"), str) or not receipt.get("run_id"):
        blockers.append("RUNNER_RUN_ID_REQUIRED")
    if not isinstance(receipt.get("producer_source_ref"), str) or "profile_creator" not in receipt.get("producer_source_ref",""):
        blockers.append("RUNNER_PRODUCER_SOURCE_REF_INVALID")

    return {
        "schema":"PROFILE_CREATOR_SEMANTIC_RUNNER_VALIDATION_V1",
        "status":"PASS" if not blockers else "FAIL",
        "blocking_codes": sorted(set(blockers)),
    }


def self_test() -> None:
    good = {
        "schema":"PROFILE_CREATOR_SEMANTIC_RUNNER_RECEIPT_V1",
        "status":"READY",
        "execution_surface":"GOVERNED_PROFILE_CREATOR_WORKER",
        "producer":"PROFILE_CREATOR",
        "case_id":"FB-001",
        "run_id":"run-001",
        "producer_source_ref":"github://repo/skills/profile_creator/SKILL.md",
        "producer_source_sha":"a"*40,
        "profile_snapshot_sha":"b"*40,
        "input_sha256":"c"*64,
        "raw_output_ref":"benchmark://raw/FB-001",
        "raw_output_sha256":"d"*64,
        "runtime_model_stamp":{"model":"EXACT_RUNTIME_MODEL","config":"FRESH"},
        "fresh_context":True,
        "profile_source_write_executed":False,
        "runtime_activation":False,
        "production_activation":False,
    }
    assert evaluate(good)["status"] == "PASS"

    bad = dict(good)
    bad["execution_surface"] = "DIRECT_LLAMA_SERVER"
    assert evaluate(bad)["status"] == "FAIL"

    bad = dict(good)
    bad["fresh_context"] = False
    assert evaluate(bad)["status"] == "FAIL"

    bad = dict(good)
    bad["profile_source_write_executed"] = True
    assert evaluate(bad)["status"] == "FAIL"

    bad = dict(good)
    bad["raw_output_sha256"] = "x"*64
    assert evaluate(bad)["status"] == "FAIL"

    bad = dict(good)
    bad["runtime_model_stamp"] = {}
    assert evaluate(bad)["status"] == "FAIL"

    print("PASS_PROFILE_CREATOR_SEMANTIC_RUNNER_V1 positive=1 negative=5 direct_model_bypass=blocked")


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return 0
    if len(sys.argv) != 2:
        print("usage: validate_profile_creator_semantic_runner_v1.py <receipt.json> | --self-test", file=sys.stderr)
        return 2
    obj = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    result = evaluate(obj)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 3


if __name__ == "__main__":
    raise SystemExit(main())
