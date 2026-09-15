#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LOCATOR = ROOT / "CAPABILITY.json"
REQUIRED_FILES = [
    ROOT / "LF_GOVERNED_CANARY_RUNNER_V1.yaml",
    ROOT / "CONSUME.md",
    ROOT / "lf_governed_canary_runner.py",
]


def resolve(mode: str) -> dict:
    data = json.loads(LOCATOR.read_text(encoding="utf-8"))
    if data.get("schema_version") != "LF_CAPABILITY_LOCATOR_V1":
        return {"status": "STALE", "blocking_code": "LOCATOR_SCHEMA_INVALID"}
    missing = [str(p.relative_to(ROOT)) for p in REQUIRED_FILES if not p.is_file()]
    if missing:
        return {"status": "STALE", "blocking_code": "PACKAGE_INCOMPLETE", "missing": missing}
    if data.get("lifecycle_status") not in {"AVAILABLE_WITH_RESTRICTIONS", "ACTIVE_CONTROLLED"}:
        return {"status": "BLOCKED", "blocking_code": "LIFECYCLE_NOT_CONSUMABLE"}
    if data.get("usage_authorized") is not True:
        return {"status": "BLOCKED", "blocking_code": "USAGE_NOT_AUTHORIZED"}
    availability = data.get("mode_availability", {}).get(mode)
    if not isinstance(availability, dict):
        return {"status": "BLOCKED", "blocking_code": "MODE_UNKNOWN", "mode": mode}
    status = availability.get("status")
    result = {
        "capability_code": data["capability_code"],
        "lifecycle_status": data["lifecycle_status"],
        "mode": mode,
        "status": status,
        "entrypoint": data["entrypoint"],
        "contract": data["contract"],
        "claim_ceiling": data["claim_ceiling"],
    }
    if status != "AVAILABLE":
        result["blocking_code"] = availability.get("blocking_code", "MODE_NOT_AVAILABLE")
    return result


def self_test() -> int:
    expected = {
        "GENERIC_SANDBOX": "AVAILABLE",
        "REPOSITORY_ONLY": "AVAILABLE",
        "MIGRATION_EXACT_VERSION": "BLOCKED",
        "RUNTIME_CANDIDATE": "BLOCKED",
    }
    failures = []
    for mode, status in expected.items():
        got = resolve(mode)
        if got.get("status") != status:
            failures.append(f"{mode}:{got.get('status')}!=${status}")
    unknown = resolve("UNKNOWN_MODE")
    if unknown.get("status") != "BLOCKED" or unknown.get("blocking_code") != "MODE_UNKNOWN":
        failures.append("UNKNOWN_MODE_NOT_FAIL_CLOSED")
    if failures:
        print(json.dumps({"status": "FAIL", "failures": failures}, sort_keys=True))
        return 1
    print(json.dumps({"status": "PASS", "checks": len(expected) + 1}, sort_keys=True))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.mode:
        parser.error("--mode is required unless --self-test is used")
    result = resolve(args.mode)
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if result.get("status") == "AVAILABLE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
