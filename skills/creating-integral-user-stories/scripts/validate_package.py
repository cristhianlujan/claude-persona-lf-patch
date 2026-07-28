"""Validate package inventory, syntax, schemas, references and placeholders for J11."""
from __future__ import annotations

import ast
import json
import re
from pathlib import Path

from lf_common import (
    ValidationInputError, add_common_input, emit, failure, load_json, load_yaml,
    main_guard, parser, result_object,
)

JUDGE = "J11_SKILL_PACKAGE"
TEXT_SUFFIXES = {".md", ".yaml", ".yml", ".json", ".py"}
PLACEHOLDER_RE = re.compile(r"\b(?:TODO|TBD|FIXME|LOREM_IPSUM|PENDIENTE_RELLENAR)\b")
PATH_RE = re.compile(
    r"(?:SKILL\.md|manifest\.yaml|(?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/[A-Za-z0-9_./-]+\.(?:md|yaml|json|py))"
)


def manifest_paths(manifest: dict) -> list[str]:
    paths = []
    files = manifest.get("files", {})
    if not isinstance(files, dict):
        raise ValidationInputError("manifest.files_must_be_object")
    for values in files.values():
        if isinstance(values, list):
            paths.extend(str(item) for item in values)
    profiles = manifest.get("external_profiles", {}).get("files", [])
    if isinstance(profiles, list):
        paths.extend(str(item) for item in profiles)
    return sorted(set(paths))


def run() -> int:
    cli = parser(__doc__)
    add_common_input(cli, "Package root directory")
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    root = args.input
    if not root.is_dir():
        raise ValidationInputError(f"package_root_not_found:{root}")
    manifest_file = root / "manifest.yaml"
    manifest = load_yaml(manifest_file)
    if not isinstance(manifest, dict):
        raise ValidationInputError("manifest_must_be_object")

    expected = set(manifest_paths(manifest))
    expected.update({"SKILL.md", "manifest.yaml"})
    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
    }
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    empty = []
    placeholder_hits = []
    json_errors = []
    yaml_errors = []
    python_errors = []
    broken_refs = []

    for rel in sorted(actual):
        path = root / rel
        try:
            body = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            empty.append(f"{rel}:not_utf8")
            continue
        if not body.strip():
            empty.append(rel)
        if rel != "scripts/validate_package.py":
            for match in PLACEHOLDER_RE.finditer(body):
                placeholder_hits.append({"path": rel, "token": match.group(0)})
        if path.suffix == ".json":
            try:
                json.loads(body)
            except json.JSONDecodeError as exc:
                json_errors.append(f"{rel}:{exc.lineno}:{exc.colno}")
        elif path.suffix in {".yaml", ".yml"}:
            try:
                load_yaml(path)
            except ValidationInputError as exc:
                yaml_errors.append(f"{rel}:{exc}")
        elif path.suffix == ".py":
            try:
                ast.parse(body, filename=rel)
            except SyntaxError as exc:
                python_errors.append(f"{rel}:{exc.lineno}:{exc.offset}")
        if path.suffix in TEXT_SUFFIXES:
            for ref in PATH_RE.findall(body):
                if ref == rel:
                    continue
                if ref not in actual and not ref.startswith("evidence/"):
                    if f"evidence/{ref}" in body:
                        continue
                    broken_refs.append({"from": rel, "to": ref})

    schema_validation_errors = []
    try:
        import jsonschema
        for rel in sorted(path for path in actual if path.startswith("schemas/") and path.endswith(".json")):
            try:
                jsonschema.Draft7Validator.check_schema(load_json(root / rel))
            except Exception as exc:
                schema_validation_errors.append(f"{rel}:{exc}")
    except ImportError:
        schema_validation_errors.append("jsonschema_not_available")

    checks = {
        "missing_required_files": missing,
        "unexpected_files": unexpected,
        "empty_required_sections": empty,
        "placeholder_hits": placeholder_hits,
        "json_parse_errors": json_errors,
        "yaml_parse_errors": yaml_errors,
        "script_compilation_errors": python_errors,
        "broken_internal_references": sorted(
            {json.dumps(item, sort_keys=True) for item in broken_refs}
        ),
        "schema_validation_errors": schema_validation_errors,
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "$package", f"Repair findings: {values[:20]}")
        for key, values in checks.items() if values
    ]
    evidence = {
        "expected_files": len(expected),
        "actual_files": len(actual),
        "checks": checks,
        "input_path": str(root),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"directory:{root}"],
        repairs, retry_count=args.retry_count,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
