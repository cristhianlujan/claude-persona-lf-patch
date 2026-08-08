#!/usr/bin/env python3
"""Static security gate for blind visual inputs and retained P0 evidence."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
FIXTURES = ROOT / "evals" / "p0-contract-fixtures.json"


def errors_for(name: str, value: Any) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise RuntimeError("jsonschema_not_available") from exc
    schema = load(SCHEMAS / name)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    return sorted(error.message for error in validator.iter_errors(value))


def validate(bundle: Any, observations: Any, evidence: Any) -> dict[str, Any]:
    bundle_errors = errors_for("blind-input-bundle.schema.json", bundle)
    observation_errors = sum((errors_for("visual-observation.schema.json", item) for item in observations if isinstance(observations, list)), [])
    evidence_errors = sum((errors_for("evidence.schema.json", item) for item in evidence if isinstance(evidence, list)), [])
    sensitive_unredacted = sum(1 for item in evidence if isinstance(item, dict) and item.get("data_classification") == "SENSITIVE" and item.get("kind") in {"CROP", "AUXILIARY_SOURCE", "ADJUDICATION"} and item.get("redacted") is not True)
    checks = {
        "blind_bundle_schema_invalid": len(bundle_errors),
        "visual_observation_schema_invalid": len(observation_errors),
        "evidence_schema_invalid": len(evidence_errors),
        "sensitive_retained_evidence_unredacted": sensitive_unredacted,
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {"result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED", "blocking_assertions": failed, "checks": checks}


def fixture(name: str) -> dict[str, Any]:
    doc = load(FIXTURES)
    return copy.deepcopy(next(case["positive"] for case in doc["cases"] if case["schema"] == name))


def self_test() -> int:
    bundle = fixture("blind-input-bundle.schema.json")
    observation = fixture("visual-observation.schema.json")
    evidence = fixture("evidence.schema.json")
    positive = validate(bundle, [observation], [evidence])
    cases = []
    x = copy.deepcopy(bundle); x["auxiliary_context"] = {"business_rule": "must remain outside blind pass"}; cases.append(("auxiliary_context_in_blind_bundle", x, [observation], [evidence], "blind_bundle_schema_invalid"))
    o = copy.deepcopy(observation); o["tool_calls"] = [{"name": "ignore_policy"}]; cases.append(("tool_call_in_visual_output", bundle, [o], [evidence], "visual_observation_schema_invalid"))
    e = copy.deepcopy(evidence); e["redacted"] = False; cases.append(("sensitive_crop_unredacted", bundle, [observation], [e], "sensitive_retained_evidence_unredacted"))
    outcomes = []
    for name, b, obs, ev, expected in cases:
        result = validate(b, obs, ev)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": positive["result"] == "PASS_WITH_EVIDENCE", "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if not args.self_test:
        parser.error("--self-test is currently the only supported mode")
    return self_test()


if __name__ == "__main__":
    raise SystemExit(main())
