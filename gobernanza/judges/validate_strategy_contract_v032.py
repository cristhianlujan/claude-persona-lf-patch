#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

import yaml

BASE_PATH = Path(__file__).with_name("validate_strategy_contract.py")
spec = importlib.util.spec_from_file_location("validate_strategy_contract_v031", BASE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("validator v0.3.1 module load failed")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

VERSION = "v0.3.2"
ARCHETYPE_REQUIRED_FIELDS = base.ARCHETYPE_REQUIRED_FIELDS


def load_document(path: Path) -> dict[str, Any]:
    return base.load_document(path)


def _finalize(result: dict[str, Any], errors: list[dict[str, str]]) -> dict[str, Any]:
    result = dict(result)
    result.pop("results_sha256", None)
    result["validator_version"] = VERSION
    result["errors"] = errors
    result["valid"] = not errors
    result["blocking_codes"] = sorted({str(e.get("code")) for e in errors})
    result["results_sha256"] = hashlib.sha256(
        json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return result


def validate(data: dict[str, Any], mode: str = "prewrite") -> dict[str, Any]:
    result = base.validate(data, mode)
    errors = [dict(item) for item in result.get("errors", [])]

    if mode == "close":
        stages = data.get("stages")
        frontier = data.get("execution_frontier")
        stage_codes = [
            stage.get("stage_code")
            for stage in stages
            if isinstance(stage, dict) and isinstance(stage.get("stage_code"), str) and stage.get("stage_code").strip()
        ] if isinstance(stages, list) else []

        if stage_codes and isinstance(frontier, dict):
            current_stage = frontier.get("current_stage")
            last_declared_stage = stage_codes[-1]
            if current_stage not in {"TERMINAL", last_declared_stage}:
                errors.append({
                    "code": "STALE_EXECUTION_FRONTIER",
                    "path": "execution_frontier.current_stage",
                    "message": (
                        "close mode requires current_stage=TERMINAL or the last declared/completed stage; "
                        f"expected one of ['TERMINAL', {last_declared_stage!r}], found {current_stage!r}"
                    ),
                })

    return _finalize(result, errors)


def self_test() -> dict[str, Any]:
    inherited = base.self_test()
    return {
        "validator_version": VERSION,
        "all_pass": bool(inherited.get("all_pass")),
        "case_count": int(inherited.get("case_count", 0)),
        "inherited_v031": inherited,
        "note": "v0.3.2 adds close-frontier terminal/last-stage enforcement; dedicated external canary covers the regression.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--mode", choices=["prewrite", "close"], default="prewrite")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        result = self_test()
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result["all_pass"] else 1
    if args.path is None:
        parser.error("path is required unless --self-test is used")
    try:
        result = validate(load_document(args.path), args.mode)
    except Exception as exc:
        result = {
            "validator_version": VERSION,
            "valid": False,
            "errors": [{"code": "MALFORMED_INPUT", "path": "$", "message": str(exc)}],
            "blocking_codes": ["MALFORMED_INPUT"],
        }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    sys.exit(main())
