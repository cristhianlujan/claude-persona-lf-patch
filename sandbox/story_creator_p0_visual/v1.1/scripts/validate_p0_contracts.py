#!/usr/bin/env python3
"""Validate P0 candidate schemas against explicit positive and negative fixtures."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from p0_schema import schema_definition_errors, validate_instance

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schemas"
FIXTURES = ROOT / "evals" / "p0-contract-fixtures.json"
EXPECTED = {
    "blind-input-bundle.schema.json",
    "visual-observation.schema.json",
    "evidence.schema.json",
    "criticality.schema.json",
    "ui-structure.schema.json",
    "enriched-understanding.schema.json",
    "human-review-packet.schema.json",
    "human-review-decision.schema.json",
    "image-admission-record.schema.json",
    "p0-judge-decision.schema.json",
    "p0-j02-handoff.schema.json",
}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def run() -> tuple[bool, dict[str, Any]]:
    fixture_doc = load(FIXTURES)
    cases = fixture_doc.get("cases", []) if isinstance(fixture_doc, dict) else []
    names = {case.get("schema") for case in cases if isinstance(case, dict)}
    results = []
    for case in cases:
        name = case["schema"]
        schema = load(SCHEMA_DIR / name)
        definition_errors = schema_definition_errors(schema)
        positive_errors = validate_instance(schema, case["positive"])
        negative_errors = validate_instance(schema, case["negative"])
        results.append({"schema": name, "schema_definition_errors": definition_errors, "positive_pass": not positive_errors, "negative_rejected": bool(negative_errors), "positive_errors": positive_errors, "negative_error_count": len(negative_errors)})
    exact = names == EXPECTED and len(cases) == len(EXPECTED)
    passed = exact and all(row["positive_pass"] and row["negative_rejected"] for row in results)
    return passed, {"schema_version": fixture_doc.get("schema_version"), "expected_schema_count": len(EXPECTED), "observed_schema_count": len(names), "expected_set_exact": exact, "results": results}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Run the governed fixture set")
    args = parser.parse_args()
    if not args.self_test:
        parser.error("--self-test is required")
    passed, evidence = run()
    evidence["result"] = "PASS_WITH_EVIDENCE" if passed else "BLOCKED"
    print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
