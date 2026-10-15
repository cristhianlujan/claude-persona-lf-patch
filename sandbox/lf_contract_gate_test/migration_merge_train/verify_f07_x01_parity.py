#!/usr/bin/env python3
"""Read-only parity check between Train pre-apply checks and a GitHub ruleset."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

RULESET_ID = 20571741
TRAIN_CONTEXT = "lf-merge-train/verified"
DEFAULT_CHECKS_FILE = Path(__file__).with_name("lf_train_required_pre_apply_checks_v1.json")


def load_required_checks(path: Path = DEFAULT_CHECKS_FILE) -> set[str]:
    document = json.loads(path.read_text(encoding="utf-8"))
    checks = document.get("required_checks") if isinstance(document, dict) else None
    if not isinstance(checks, list) or any(not isinstance(item, str) for item in checks):
        raise ValueError("FAIL_F07_X01_PARITY_INVALID_CHECKS_FILE")
    return set(checks)


def contexts_from_ruleset(payload: Any) -> set[str]:
    rules = payload.get("rules") if isinstance(payload, dict) else None
    if not isinstance(rules, list):
        raise ValueError("FAIL_F07_X01_PARITY_INVALID_RULESET")
    contexts: set[str] = set()
    for rule in rules:
        if not isinstance(rule, dict) or rule.get("type") != "required_status_checks":
            continue
        parameters = rule.get("parameters")
        required = parameters.get("required_status_checks") if isinstance(parameters, dict) else None
        if not isinstance(required, list):
            raise ValueError("FAIL_F07_X01_PARITY_INVALID_RULESET")
        for item in required:
            if isinstance(item, dict) and isinstance(item.get("context"), str):
                contexts.add(item["context"])
    contexts.discard(TRAIN_CONTEXT)
    return contexts


def compare(required: set[str], ruleset: Any) -> tuple[bool, list[str], list[str]]:
    actual = contexts_from_ruleset(ruleset)
    missing = sorted(required - actual)
    surplus = sorted(actual - required)
    return not missing and not surplus, missing, surplus


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="cristhianlujan/claude-persona-lf-patch")
    parser.add_argument("--ruleset-id", type=int, default=RULESET_ID)
    parser.add_argument("--checks-file", type=Path, default=DEFAULT_CHECKS_FILE)
    parser.add_argument("--ruleset-json", type=Path, help="fixture input; skips GitHub read")
    args = parser.parse_args()
    try:
        required = load_required_checks(args.checks_file)
        if args.ruleset_json:
            ruleset = json.loads(args.ruleset_json.read_text(encoding="utf-8"))
        else:
            endpoint = f"repos/{args.repo}/rulesets/{args.ruleset_id}"
            response = subprocess.run(["gh", "api", endpoint], check=True, text=True,
                                      capture_output=True)
            ruleset = json.loads(response.stdout)
        same, missing, surplus = compare(required, ruleset)
    except (OSError, json.JSONDecodeError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"FAIL_F07_X01_PARITY_READ_ERROR detail={exc}")
        return 2
    if same:
        print("PASS_F07_X01_PARITY")
        return 0
    print(f"FAIL_F07_X01_PARITY missing={json.dumps(missing, ensure_ascii=False)} surplus={json.dumps(surplus, ensure_ascii=False)}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
