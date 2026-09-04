#!/usr/bin/env python3
"""External entrypoint for the Golden Family adversarial selftests."""
from __future__ import annotations

import json

import validate_golden_family_contract as validator


def main() -> int:
    data = json.loads(validator.CONTRACT.read_text(encoding="utf-8"))
    result = validator.validate_contract(data)
    if "status=E2E_BLOCKED" not in result:
        raise AssertionError(f"canonical contract must remain blocked, got: {result}")
    cases = validator.run_negative_selftests(data)
    if cases != 15:
        raise AssertionError(f"expected 15 negative cases, got {cases}")
    print(f"GOLDEN_FAMILY_NEGATIVE_FIXTURES_PASS cases={cases}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
