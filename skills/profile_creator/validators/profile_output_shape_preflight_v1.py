#!/usr/bin/env python3
"""Read-only structural output parity for creation/evolution candidate samples.

This is a deliberately narrow structural preflight, NOT a replacement for a
profile-local canonical validator, JSON Schema engine or independent reviewer.
No untrusted profile Python is imported or executed.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SCHEMA = "PROFILE_OUTPUT_SHAPE_PREFLIGHT_V1"
MAX_DEPTH = 48
COVERED = (
    "type", "required", "properties", "additionalProperties",
    "enum", "const", "items", "minItems", "maxItems", "minLength",
    "maxLength", "minimum", "maximum", "pattern"
)
UNSUPPORTED_APPLICATORS = ("$ref", "$dynamicRef", "oneOf", "anyOf", "allOf",
                           "not", "if", "then", "else", "dependentSchemas",
                           "patternProperties", "unevaluatedProperties")


def _type_ok(value: Any, declared: str) -> bool:
    return {
        "object": lambda: isinstance(value, dict),
        "array": lambda: isinstance(value, list),
        "string": lambda: isinstance(value, str),
        "integer": lambda: type(value) is int,
        "number": lambda: type(value) in (int, float),
        "boolean": lambda: type(value) is bool,
        "null": lambda: value is None,
    }.get(declared, lambda: False)()


def _same(a: Any, b: Any) -> bool:
    return type(a) is type(b) and a == b


def validate_shape(schema: Any, value: Any) -> dict[str, Any]:
    """Bounded check of known shape rules. Unsupported logic blocks instead of silently passing."""
    errors: list[dict[str, str]] = []

    def fail(code: str, path: str) -> None:
        errors.append({"code": code, "path": path})

    def walk(rule: Any, item: Any, path: str, depth: int) -> None:
        if depth >= MAX_DEPTH:
            fail("DEPTH_LIMIT", path)
            return
        if not isinstance(rule, dict):
            fail("SCHEMA_NODE_NOT_OBJECT", path)
            return
        for keyword in UNSUPPORTED_APPLICATORS:
            if keyword in rule:
                fail("REQUIRES_CANONICAL_SCHEMA_VALIDATOR:" + keyword, path)
        declared = rule.get("type")
        if isinstance(declared, str):
            if not _type_ok(item, declared):
                fail("TYPE_MISMATCH:" + declared, path)
                return
        elif declared is not None:
            fail("REQUIRES_CANONICAL_SCHEMA_VALIDATOR:type", path)
        if "const" in rule and not _same(item, rule["const"]):
            fail("CONST_MISMATCH", path)
        if "enum" in rule:
            if not isinstance(rule["enum"], list) or not any(_same(item, x) for x in rule["enum"]):
                fail("ENUM_MISMATCH", path)
        if isinstance(item, dict):
            required = rule.get("required", [])
            if not isinstance(required, list) or any(not isinstance(x, str) for x in required):
                fail("SCHEMA_REQUIRED_INVALID", path)
                required = []
            for key in required:
                if key not in item:
                    fail("REQUIRED_MISSING:" + key, path)
            props = rule.get("properties", {})
            if not isinstance(props, dict):
                fail("SCHEMA_PROPERTIES_INVALID", path)
                return
            extras = item.keys() - props.keys()
            if rule.get("additionalProperties") is False:
                for key in sorted(extras):
                    fail("ADDITIONAL_PROPERTY:" + key, path)
            elif isinstance(rule.get("additionalProperties"), dict):
                for key in sorted(extras):
                    walk(rule["additionalProperties"], item[key], path + "." + key, depth+1)
            for key in sorted(item.keys() & props.keys()):
                walk(props[key], item[key], path + "." + key, depth+1)
        if isinstance(item, list):
            for flag, check in (("minItems", lambda n: len(item) < n),
                                ("maxItems", lambda n: len(item) > n)):
                if type(rule.get(flag)) is int and check(rule[flag]):
                    fail(flag.upper() + "_FAILED", path)
            if "items" in rule:
                for idx, child in enumerate(item):
                    walk(rule["items"], child, f"{path}[{idx}]", depth+1)
        if isinstance(item, str):
            for flag, check in (("minLength", lambda n: len(item) < n),
                                ("maxLength", lambda n: len(item) > n)):
                if type(rule.get(flag)) is int and check(rule[flag]):
                    fail(flag.upper() + "_FAILED", path)
            if isinstance(rule.get("pattern"), str):
                try:
                    if re.search(rule["pattern"], item) is None:
                        fail("PATTERN_MISMATCH", path)
                except re.error:
                    fail("SCHEMA_PATTERN_INVALID", path)
        if type(item) in (int, float):
            if type(rule.get("minimum")) in (int, float) and item < rule["minimum"]:
                fail("MINIMUM_FAILED", path)
            if type(rule.get("maximum")) in (int, float) and item > rule["maximum"]:
                fail("MAXIMUM_FAILED", path)

    walk(schema, value, "$", 0)
    return {
        "schema": SCHEMA, "status": "PASS" if not errors else "FAIL",
        "blocking_codes": errors,
        "coverage": list(COVERED),
        "full_json_schema_validation": False,
        "profile_local_validator_executed": False,
        "semantic_review_executed": False,
        "provider_attestation": False,
        "cutover_authorized": False,
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--schema", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    try:
        result = validate_shape(
            json.loads(args.schema.read_text(encoding="utf-8")),
            json.loads(args.output.read_text(encoding="utf-8")),
        )
    except (OSError, ValueError) as exc:
        result = {
            "schema": SCHEMA, "status": "FAIL",
            "blocking_codes": [{"code": "INPUT_UNREADABLE", "path": "$", "detail": type(exc).__name__}],
            "full_json_schema_validation": False,
            "profile_local_validator_executed": False,
            "provider_attestation": False,
            "cutover_authorized": False,
        }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
