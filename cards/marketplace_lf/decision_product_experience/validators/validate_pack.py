#!/usr/bin/env python3
"""Validate MarketPlace LF decision product experience card pack."""
from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED_FILES = [
    "README.md",
    "CARD.md",
    "context_pack.md",
    "contracts/main_contract.md",
    "contracts/missing_input_policy.md",
    "schemas/decision_request.schema.json",
    "schemas/decision_output.schema.json",
    "judges/decision_judge.md",
    "judges/score_rubric.md",
    "examples/juan_digital_case.md",
    "examples/map_surface_case.md",
    "fixtures/juan_digital_decision_request.json",
    "fixtures/map_surface_decision_request.json",
    "fixtures/missing_source_decision_request.json",
    "evals/evals.json",
    "handoffs/to_quality_pack.handoff.json",
    "adapters/github_pack_adapter.md",
    "adapters/documentation_adapter.md",
]

FORBIDDEN_MARKERS = [
    "VALIDATED: true",
    "Runtime: ENABLED",
    "Automatic impact: ENABLED",
    "PRODUCTION_READY",
    "GOLDEN_APPROVED",
]

REQUIRED_MARKERS = [
    "RUNTIME_PACK_CANDIDATE",
    "READ_ONLY",
    "Automatic impact: BLOCKED",
]


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    errors: list[str] = []

    for rel in REQUIRED_FILES:
        if not (root / rel).exists():
            errors.append(f"missing required file: {rel}")

    for rel in REQUIRED_FILES:
        path = root / rel
        if path.exists() and path.suffix in {".md", ".json"}:
            text = path.read_text(encoding="utf-8")
            for marker in FORBIDDEN_MARKERS:
                if marker in text:
                    errors.append(f"forbidden marker {marker!r} in {rel}")

    readme = root / "README.md"
    if readme.exists():
        text = readme.read_text(encoding="utf-8")
        for marker in REQUIRED_MARKERS:
            if marker not in text:
                errors.append(f"required marker {marker!r} missing in README.md")

    for rel in [
        "schemas/decision_request.schema.json",
        "schemas/decision_output.schema.json",
        "fixtures/juan_digital_decision_request.json",
        "fixtures/map_surface_decision_request.json",
        "fixtures/missing_source_decision_request.json",
        "evals/evals.json",
        "handoffs/to_quality_pack.handoff.json",
    ]:
        path = root / rel
        if path.exists():
            try:
                load_json(path)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"invalid JSON in {rel}: {exc}")

    if errors:
        print("PACK_VALIDATION_FAIL")
        for err in errors:
            print(f"- {err}")
        return 1

    print("PACK_VALIDATION_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
