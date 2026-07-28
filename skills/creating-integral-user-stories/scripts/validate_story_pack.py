"""Validate one Story Pack against schema and J03 semantic assertions."""
from __future__ import annotations

from pathlib import Path

from lf_common import (
    ValidationInputError, add_common_input, duplicate_values, emit, failure,
    load_json, main_guard, parser, require_object, result_object,
)

JUDGE = "J03_STORY_CORE"
SECTIONS = (
    "identity", "core", "interaction", "screen_fields", "fields", "validations",
    "observations", "errors", "security_privacy", "states", "audit",
    "tokens_messages", "analytics", "observability",
    "responsive_accessibility", "tests", "dependencies_risks", "judges_evidence",
)
CORE_KEYS = (
    "actor", "need", "benefit", "preconditions", "trigger", "main_flow",
    "alternative_flows", "postconditions", "acceptance_criteria", "out_of_scope",
)


def schema_errors(instance, schema_path: Path) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    schema = load_json(schema_path)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    return sorted(
        f"{'/'.join(str(part) for part in error.absolute_path) or '$'}:{error.message}"
        for error in validator.iter_errors(instance)
    )


def run() -> int:
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument(
        "--schema",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "schemas/story-pack.schema.json",
    )
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")

    failed: list[str] = []
    repairs = []
    missing_sections = [section for section in SECTIONS if section not in pack]
    if missing_sections:
        failed.append(f"missing_sections={len(missing_sections)}")
        repairs.append(failure("missing_sections", "$", f"Add sections: {', '.join(missing_sections)}"))

    core = pack.get("core") if isinstance(pack.get("core"), dict) else {}
    missing_core = [key for key in CORE_KEYS if key not in core or core.get(key) in (None, "", [])]
    missing_core = [key for key in missing_core if key != "alternative_flows"]
    if missing_core:
        failed.append(f"core_keys_missing={len(missing_core)}")
        repairs.append(failure("core_keys_missing", "core", f"Complete: {', '.join(missing_core)}"))

    criteria = core.get("acceptance_criteria", [])
    criteria = criteria if isinstance(criteria, list) else []
    invalid_gwt = [
        index for index, item in enumerate(criteria)
        if not isinstance(item, dict)
        or not all(isinstance(item.get(key), str) and item.get(key).strip()
                   for key in ("criterion_code", "given", "when", "then", "source_ref"))
    ]
    if invalid_gwt:
        failed.append(f"criteria_without_given_when_then={len(invalid_gwt)}")
        repairs.append(failure(
            "criteria_without_given_when_then",
            "core.acceptance_criteria",
            f"Repair criteria at indexes: {invalid_gwt}",
        ))

    codes = [item.get("criterion_code") for item in criteria if isinstance(item, dict)]
    duplicate_codes = duplicate_values(code for code in codes if code)
    if duplicate_codes:
        failed.append(f"duplicate_criterion_codes={len(duplicate_codes)}")
        repairs.append(failure(
            "duplicate_criterion_codes", "core.acceptance_criteria",
            f"Assign unique deterministic codes; duplicates: {duplicate_codes}",
        ))

    identity = pack.get("identity") if isinstance(pack.get("identity"), dict) else {}
    if not identity.get("source_decision_id") or not identity.get("source_snapshot_sha"):
        failed.append("stories_without_source_trace=1")
        repairs.append(failure(
            "stories_without_source_trace", "identity",
            "Provide source_decision_id and source_snapshot_sha from the approved source.",
        ))

    schema_failures = schema_errors(pack, args.schema)
    if schema_failures:
        failed.append(f"schema_validation_errors={len(schema_failures)}")
        repairs.append(failure(
            "schema_validation_errors", "$",
            "Resolve every JSON Schema error without weakening the schema.",
        ))

    evidence = {
        "sections_present": len(SECTIONS) - len(missing_sections),
        "sections_expected": len(SECTIONS),
        "missing_sections": missing_sections,
        "missing_core_keys": missing_core,
        "acceptance_criteria_count": len(criteria),
        "invalid_criterion_indexes": invalid_gwt,
        "duplicate_criterion_codes": duplicate_codes,
        "schema_error_count": len(schema_failures),
        "schema_errors": schema_failures[:50],
        "input_path": str(args.input),
        "schema_path": str(args.schema),
    }
    out = result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
    )
    return emit(out)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
