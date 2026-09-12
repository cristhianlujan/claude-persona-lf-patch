#!/usr/bin/env python3
"""Fail-closed local validator for the Draft 7 subset governed by P0 schemas.

The P0 gates must remain executable when the optional ``jsonschema`` package is
not installed.  This module intentionally supports only the keywords present in
the governed schema set.  A new/unknown schema keyword is a validation error,
not something that is silently ignored.
"""
from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any

_ANNOTATION_KEYWORDS = {"$schema", "$id", "title", "description", "default", "examples"}
_VALIDATION_KEYWORDS = {
    "type",
    "required",
    "properties",
    "additionalProperties",
    "items",
    "enum",
    "const",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minLength",
    "maxLength",
    "pattern",
    "format",
    "allOf",
    "anyOf",
    "oneOf",
    "not",
    "if",
    "then",
    "else",
}
_SUPPORTED_KEYWORDS = _ANNOTATION_KEYWORDS | _VALIDATION_KEYWORDS
_SUPPORTED_TYPES = {"null", "boolean", "object", "array", "number", "integer", "string"}
_SUPPORTED_FORMATS = {"date-time"}


def _join(path: str, token: Any) -> str:
    return f"{path}/{str(token).replace('~', '~0').replace('/', '~1')}"


def _schema_definition_errors(schema: Any, path: str = "$", *, in_properties: bool = False) -> list[str]:
    if isinstance(schema, bool):
        return []
    if not isinstance(schema, dict):
        return [f"{path}:schema_must_be_object_or_boolean"]

    errors: list[str] = []
    for keyword in schema:
        if keyword not in _SUPPORTED_KEYWORDS:
            errors.append(f"{path}:unsupported_schema_keyword:{keyword}")

    schema_type = schema.get("type")
    if schema_type is not None:
        types = schema_type if isinstance(schema_type, list) else [schema_type]
        if not types or any(item not in _SUPPORTED_TYPES for item in types):
            errors.append(f"{path}:unsupported_or_invalid_type:{schema_type!r}")

    schema_format = schema.get("format")
    if schema_format is not None and schema_format not in _SUPPORTED_FORMATS:
        errors.append(f"{path}:unsupported_format:{schema_format}")

    properties = schema.get("properties")
    if properties is not None:
        if not isinstance(properties, dict):
            errors.append(f"{path}:properties_must_be_object")
        else:
            for name, child in properties.items():
                errors.extend(_schema_definition_errors(child, _join(path, f"properties/{name}"), in_properties=True))

    items = schema.get("items")
    if items is not None:
        if isinstance(items, list):
            errors.append(f"{path}:tuple_items_not_supported")
        else:
            errors.extend(_schema_definition_errors(items, _join(path, "items")))

    additional = schema.get("additionalProperties")
    if isinstance(additional, dict):
        errors.extend(_schema_definition_errors(additional, _join(path, "additionalProperties")))
    elif additional is not None and not isinstance(additional, bool):
        errors.append(f"{path}:additionalProperties_must_be_boolean_or_schema")

    for keyword in ("allOf", "anyOf", "oneOf"):
        value = schema.get(keyword)
        if value is None:
            continue
        if not isinstance(value, list) or not value:
            errors.append(f"{path}:{keyword}_must_be_nonempty_array")
            continue
        for index, child in enumerate(value):
            errors.extend(_schema_definition_errors(child, _join(path, f"{keyword}/{index}")))

    for keyword in ("not", "if", "then", "else"):
        if keyword in schema:
            errors.extend(_schema_definition_errors(schema[keyword], _join(path, keyword)))

    return errors


def schema_definition_errors(schema: Any) -> list[str]:
    """Return deterministic errors for unsupported or malformed schema structure."""
    return sorted(_schema_definition_errors(schema))


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return False


def _json_equal(left: Any, right: Any) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, list):
        return len(left) == len(right) and all(_json_equal(a, b) for a, b in zip(left, right))
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(_json_equal(left[key], right[key]) for key in left)
    return left == right


def _unique_key(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _valid_datetime(value: str) -> bool:
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00" if value.endswith("Z") else value)
    except ValueError:
        return False
    return "T" in value and parsed.tzinfo is not None


def _validate(schema: Any, value: Any, path: str) -> list[str]:
    if schema is True:
        return []
    if schema is False:
        return [f"{path}:boolean_schema_false"]

    errors: list[str] = []
    expected = schema.get("type")
    if expected is not None:
        types = expected if isinstance(expected, list) else [expected]
        if not any(_matches_type(value, item) for item in types):
            return [f"{path}:type_expected:{'|'.join(types)}"]

    if "enum" in schema and not any(_json_equal(value, item) for item in schema["enum"]):
        errors.append(f"{path}:not_in_enum")
    if "const" in schema and not _json_equal(value, schema["const"]):
        errors.append(f"{path}:const_mismatch")

    if isinstance(value, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if key not in value:
                    errors.append(f"{_join(path, key)}:required")
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for key, child_schema in properties.items():
                if key in value:
                    errors.extend(_validate(child_schema, value[key], _join(path, key)))
            extras = [key for key in value if key not in properties]
            additional = schema.get("additionalProperties", True)
            if additional is False:
                errors.extend(f"{_join(path, key)}:additional_property" for key in extras)
            elif isinstance(additional, dict):
                for key in extras:
                    errors.extend(_validate(additional, value[key], _join(path, key)))

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}:minItems:{schema['minItems']}")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}:maxItems:{schema['maxItems']}")
        if schema.get("uniqueItems") is True:
            try:
                keys = [_unique_key(item) for item in value]
                if len(keys) != len(set(keys)):
                    errors.append(f"{path}:uniqueItems")
            except (TypeError, ValueError):
                errors.append(f"{path}:uniqueItems_unserializable")
        if "items" in schema and not isinstance(schema["items"], list):
            for index, item in enumerate(value):
                errors.extend(_validate(schema["items"], item, _join(path, index)))

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{path}:minLength:{schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{path}:maxLength:{schema['maxLength']}")
        if "pattern" in schema:
            try:
                if re.search(schema["pattern"], value) is None:
                    errors.append(f"{path}:pattern_mismatch")
            except re.error:
                errors.append(f"{path}:invalid_schema_pattern")
        if schema.get("format") == "date-time" and not _valid_datetime(value):
            errors.append(f"{path}:format_date-time")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}:minimum:{schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}:maximum:{schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(f"{path}:exclusiveMinimum:{schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(f"{path}:exclusiveMaximum:{schema['exclusiveMaximum']}")

    for child in schema.get("allOf", []):
        errors.extend(_validate(child, value, path))
    if "anyOf" in schema and not any(not _validate(child, value, path) for child in schema["anyOf"]):
        errors.append(f"{path}:anyOf")
    if "oneOf" in schema:
        matched = sum(1 for child in schema["oneOf"] if not _validate(child, value, path))
        if matched != 1:
            errors.append(f"{path}:oneOf:{matched}")
    if "not" in schema and not _validate(schema["not"], value, path):
        errors.append(f"{path}:not")
    if "if" in schema:
        branch = "then" if not _validate(schema["if"], value, path) else "else"
        if branch in schema:
            errors.extend(_validate(schema[branch], value, path))

    return errors


def validate_instance(schema: Any, value: Any) -> list[str]:
    """Validate an instance; fail closed when the schema uses unsupported syntax."""
    definition_errors = schema_definition_errors(schema)
    if definition_errors:
        return [f"schema_definition:{error}" for error in definition_errors]
    return sorted(_validate(schema, value, "$"))
