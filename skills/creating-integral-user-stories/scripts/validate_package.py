"""Validate LF package inventory, quality rubric, consistency and negative behavior.

The validator is intentionally able to fail. It audits every manifest artifact,
assigns a deterministic 0-20 score using type-specific controls, checks internal
references and contract/schema consistency, and rejects any artifact below its
tier threshold (NUCLEO=18, SOPORTE=14).
"""
from __future__ import annotations

import argparse
import ast
import json
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from lf_common import (
    ValidationInputError,
    emit,
    failure,
    load_json,
    load_yaml,
    main_guard,
    result_object,
)

JUDGE = "J11_SKILL_PACKAGE"
TEXT_SUFFIXES = {".md", ".yaml", ".yml", ".json", ".py"}
PLACEHOLDER_RE = re.compile(r"\b(?:TODO|TBD|FIXME|LOREM_IPSUM|PENDIENTE_RELLENAR)\b")
PATH_RE = re.compile(
    r"(?:SKILL\.md|manifest\.yaml|(?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/[A-Za-z0-9_./-]+\.(?:md|yaml|yml|json|py))"
)
FORBIDDEN_STATUS_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?:VALIDATED|PRODUCTION|APROBADO_FINAL|VIGENTE)(?![A-Za-z0-9_])",
    re.IGNORECASE,
)
TOKEN_RE = re.compile(r"\w+|[^\w\s]", re.UNICODE)
SNAKE_FIELD_RE = re.compile(r"\b[a-z][a-z0-9_]{2,}\b")

TIER_BY_PATH = {
    "SKILL.md": "NUCLEO",
    "manifest.yaml": "NUCLEO",
    "references/field-contract.md": "NUCLEO",
    "references/screen-decomposition-protocol.md": "NUCLEO",
    "references/story-pack-contract.md": "NUCLEO",
}
CORE_PREFIXES = ("agents/", "judges/", "schemas/", "scripts/", "evals/")
SUPPORT_PREFIXES = ("perfiles/", "templates/")
SUPPORT_REFERENCES = {
    "references/accessibility-responsive-contract.md",
    "references/analytics-observability-contract.md",
    "references/audit-traceability-contract.md",
    "references/observations-errors-contract.md",
    "references/security-privacy-contract.md",
    "references/supabase-source-map.md",
    "references/test-derivation-contract.md",
    "references/tokens-messages-contract.md",
}
SUPPORT_FIXTURES_PREFIX = "evals/fixtures/"
THRESHOLD_BY_TIER = {"NUCLEO": 18, "SOPORTE": 14}

BYTE_BANDS = {
    "AGENT": (700, 30000),
    "PROFILE": (1000, 12000),
    "REFERENCE": (900, 30000),
    "MANIFEST": (3000, 50000),
    "SCHEMA": (1000, 50000),
    "SCRIPT": (900, 50000),
    "SHARED_MODULE": (900, 50000),
    "JUDGE": (900, 12000),
    "EVAL": (1000, 30000),
    "FIXTURE": (120, 5000),
    "SKILL_MD": (4000, 30000),
    "TEMPLATE": (700, 30000),
}

TYPE_BY_PATH: tuple[tuple[str, str], ...] = (
    ("agents/", "AGENT"),
    ("perfiles/", "PROFILE"),
    ("references/", "REFERENCE"),
    ("schemas/", "SCHEMA"),
    ("scripts/lf_common.py", "SHARED_MODULE"),
    ("scripts/", "SCRIPT"),
    ("judges/", "JUDGE"),
    ("evals/fixtures/", "FIXTURE"),
    ("evals/", "EVAL"),
    ("templates/", "TEMPLATE"),
)


@dataclass(frozen=True)
class Dimension:
    name: str
    passed: bool
    evidence: str


@dataclass(frozen=True)
class ArtifactAudit:
    path: str
    artifact_type: str
    tier: str
    threshold: int
    score: int
    dimensions: tuple[Dimension, ...]
    bytes_count: int
    token_count: int
    measurement_method: str

    @property
    def passed(self) -> bool:
        return self.score >= self.threshold

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "artifact_type": self.artifact_type,
            "tier": self.tier,
            "threshold": self.threshold,
            "score": self.score,
            "passed": self.passed,
            "bytes": self.bytes_count,
            "tokens": self.token_count,
            "measurement_method": self.measurement_method,
            "dimensions": [
                {"name": item.name, "passed": item.passed, "evidence": item.evidence}
                for item in self.dimensions
            ],
        }


def manifest_paths(manifest: dict[str, Any]) -> list[str]:
    paths: list[str] = []
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


def artifact_type(rel: str) -> str:
    if rel == "SKILL.md":
        return "SKILL_MD"
    if rel == "manifest.yaml":
        return "MANIFEST"
    for prefix, kind in TYPE_BY_PATH:
        if rel == prefix or rel.startswith(prefix):
            return kind
    return "UNKNOWN"


def artifact_tier(rel: str) -> str:
    if rel in TIER_BY_PATH:
        return TIER_BY_PATH[rel]
    if rel.startswith(SUPPORT_FIXTURES_PREFIX):
        return "SOPORTE"
    if rel in SUPPORT_REFERENCES or rel.startswith(SUPPORT_PREFIXES):
        return "SOPORTE"
    if rel.startswith(CORE_PREFIXES):
        return "NUCLEO"
    raise ValidationInputError(f"tier_not_defined:{rel}")


def has_any(text: str, values: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(value.lower() in lowered for value in values)


def parsed_payload(path: Path, body: str) -> Any:
    if path.suffix == ".json":
        return json.loads(body)
    if path.suffix in {".yaml", ".yml"}:
        return load_yaml(path)
    if path.suffix == ".py":
        return ast.parse(body, filename=path.as_posix())
    return None


def mapping_has(data: Any, *keys: str) -> bool:
    return isinstance(data, dict) and all(key in data for key in keys)


def list_contains_kind(data: Any, kind: str) -> bool:
    if not isinstance(data, dict):
        return False
    for value in data.values():
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict) and str(item.get("kind", "")).lower() == kind:
                    return True
    return False


def required_reference_state(body: str, rel: str, actual: set[str]) -> tuple[bool, str]:
    refs = sorted(set(PATH_RE.findall(body)) - {rel})
    broken = [ref for ref in refs if ref not in actual and not ref.startswith("evidence/")]
    return not broken, f"refs={len(refs)} broken={broken[:5]}"


def forbidden_state(body: str, rel: str) -> tuple[bool, str]:
    if rel in {"manifest.yaml", "scripts/validate_package.py"}:
        return True, "policy_definition_exempt"
    hits = sorted(set(match.group(0).upper() for match in FORBIDDEN_STATUS_RE.finditer(body)))
    return not hits, f"forbidden_status_hits={hits}"


def base_dimensions(
    rel: str,
    kind: str,
    body: str,
    parsed: Any,
    actual: set[str],
) -> list[Dimension]:
    low, high = BYTE_BANDS.get(kind, (1, 50000))
    byte_count = len(body.encode("utf-8"))
    ref_ok, ref_evidence = required_reference_state(body, rel, actual)
    forbidden_ok, forbidden_evidence = forbidden_state(body, rel)
    return [
        Dimension("syntax_parse", parsed is not False, "utf8_and_parser_ok"),
        Dimension("byte_band", low <= byte_count <= high, f"bytes={byte_count} band={low}-{high}"),
        Dimension("internal_references", ref_ok, ref_evidence),
        Dimension("forbidden_status", forbidden_ok, forbidden_evidence),
    ]


def type_dimensions(rel: str, kind: str, body: str, parsed: Any) -> list[Dimension]:
    lower = body.lower()
    if kind in {"AGENT", "PROFILE", "REFERENCE", "SKILL_MD"}:
        purpose = has_any(lower, ("## objetivo", "## misión", "## proposito", "## propósito", "regla madre"))
        inputs = has_any(lower, ("## entradas", "required_inputs", "entrada mínima", "entradas mínimas"))
        procedure = has_any(lower, ("## procedimiento", "## workflow", "## flujo", "paso 1", "ciclo", "reglas de ejecución"))
        output = has_any(lower, ("## salida", "## output", "output schema", "entregable"))
        positive = has_any(lower, ("ejemplo positivo", "caso positivo", "pass_with_evidence", "assertions de aceptacion", "assertions obligatorias"))
        negative = has_any(lower, ("ejemplo negativo", "caso negativo", "prohibiciones", "acciones prohibidas", "block", "return_to_worker", "falla"))
        return [
            Dimension("purpose_scope", purpose, "objective_or_mission"),
            Dimension("input_contract", inputs, "inputs_declared"),
            Dimension("deterministic_procedure", procedure, "procedure_or_flow"),
            Dimension("output_contract", output, "output_declared"),
            Dimension("positive_behavior", positive, "positive_assertion_or_example"),
            Dimension("negative_behavior", negative, "negative_case_or_stop_condition"),
        ]
    if kind == "JUDGE":
        data = parsed if isinstance(parsed, dict) else {}
        return [
            Dimension("purpose_scope", mapping_has(data, "judge_code", "scope"), "judge_code+scope"),
            Dimension("input_contract", mapping_has(data, "required_inputs"), "required_inputs"),
            Dimension("deterministic_procedure", mapping_has(data, "pass_if", "fail_if", "block_if"), "pass/fail/block rules"),
            Dimension("output_contract", mapping_has(data, "output", "result_values"), "output+result_values"),
            Dimension("positive_behavior", bool(data.get("pass_if")), "pass_if_nonempty"),
            Dimension("negative_behavior", bool(data.get("fail_if")) and bool(data.get("block_if")), "fail_if+block_if_nonempty"),
        ]
    if kind == "SCHEMA":
        data = parsed if isinstance(parsed, dict) else {}
        serialized = json.dumps(data, ensure_ascii=False)
        return [
            Dimension("purpose_scope", mapping_has(data, "$schema", "title", "type"), "$schema+title+type"),
            Dimension("input_contract", bool(data.get("required")), "root_required_nonempty"),
            Dimension("deterministic_procedure", "properties" in data, "properties_declared"),
            Dimension("output_contract", data.get("type") in {"object", "array"}, "root_type_bounded"),
            Dimension("positive_behavior", "examples" in serialized or "default" in serialized or "const" in serialized, "example/default/const"),
            Dimension("negative_behavior", any(token in serialized for token in ('"enum"', '"minLength"', '"minItems"', '"pattern"', '"additionalProperties": false')), "rejecting_constraints"),
        ]
    if kind in {"SCRIPT", "SHARED_MODULE"}:
        tree = parsed if isinstance(parsed, ast.AST) else None
        function_names = {node.name for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))} if tree else set()
        return [
            Dimension("purpose_scope", bool(ast.get_docstring(tree)) if tree else False, "module_docstring"),
            Dimension("input_contract", has_any(lower, ("argparse", "add_common_input", "parser(")), "cli_or_input_contract"),
            Dimension("deterministic_procedure", len(function_names) >= 2, f"functions={len(function_names)}"),
            Dimension("output_contract", has_any(lower, ("result_object", "emit(", "return")), "structured_result_or_return"),
            Dimension("positive_behavior", has_any(lower, ("pass_with_evidence", "compliance_bit", "self-test", "self_test")), "positive_result_path"),
            Dimension("negative_behavior", has_any(lower, ("failure(", "validationinputerror", "except", "return_to_worker", "blocked")), "negative_or_exception_path"),
        ]
    if kind == "EVAL":
        data = parsed if isinstance(parsed, dict) else {}
        serialized = json.dumps(data, ensure_ascii=False)
        return [
            Dimension("purpose_scope", any(key in data for key in ("cases", "assertions", "triggers")), "eval_collection"),
            Dimension("input_contract", "fixture_ref" in serialized or "prompt" in serialized, "prompt_or_fixture_ref"),
            Dimension("deterministic_procedure", "assertions" in serialized, "assertions_declared"),
            Dimension("output_contract", "expected_result" in serialized or "expected_output" in serialized, "expected_result/output"),
            Dimension("positive_behavior", list_contains_kind(data, "positive") or "PASS_WITH_EVIDENCE" in serialized, "positive_case"),
            Dimension("negative_behavior", list_contains_kind(data, "negative") or "RETURN_TO_WORKER" in serialized or "BLOCKED" in serialized, "negative_case"),
        ]
    if kind == "FIXTURE":
        data = parsed if isinstance(parsed, dict) else {}
        structural_keys = {"fields", "actions", "contexts", "permissions", "steps", "screen_code"}
        return [
            Dimension("purpose_scope", bool(set(data) & {"screen_code", "case_id", "id", "version"}), "fixture_identity"),
            Dimension("input_contract", len(data) >= 3, f"root_keys={len(data)}"),
            Dimension("deterministic_procedure", bool(set(data) & structural_keys), "domain_structure"),
            Dimension("output_contract", "version" in data or "expected_result" in data, "version_or_expected_result"),
            Dimension("positive_behavior", bool(set(data) & {"actions", "contexts", "fields", "steps"}), "executable_input_shape"),
            Dimension("negative_behavior", bool(set(data) & {"missing", "sensitive", "invalid", "expected_result"}) or "insufficient" in rel or "sensitive" in rel, "negative_signal_when_applicable"),
        ]
    if kind == "TEMPLATE":
        placeholder = bool(re.search(r"<[^>]+>|\{\{[^}]+\}\}", body))
        return [
            Dimension("purpose_scope", placeholder, "template_placeholders"),
            Dimension("input_contract", placeholder and len(body) >= 700, "fillable_contract"),
            Dimension("deterministic_procedure", has_any(lower, ("given", "when", "then", "required", "judge", "evidence")), "structured_sections"),
            Dimension("output_contract", body.strip().startswith(("{", "#", "judge_code", "---")), "renderable_root"),
            Dimension("positive_behavior", has_any(lower, ("pass_with_evidence", "candidato_read_only", "given")), "valid_target_state"),
            Dimension("negative_behavior", has_any(lower, ("blocked", "failed", "pending_decision", "out_of_scope", "repair")), "failure_or_pending_state"),
        ]
    if kind == "MANIFEST":
        data = parsed if isinstance(parsed, dict) else {}
        workflow = data.get("workflow", {}) if isinstance(data.get("workflow"), dict) else {}
        steps = workflow.get("steps", []) if isinstance(workflow, dict) else []
        return [
            Dimension("purpose_scope", mapping_has(data, "skill_code", "operation_code", "package_contract"), "identity+package_contract"),
            Dimension("input_contract", mapping_has(data, "source_authority", "canonical_store"), "sources+canonical_store"),
            Dimension("deterministic_procedure", isinstance(steps, list) and len(steps) == 13, f"workflow_steps={len(steps) if isinstance(steps, list) else 0}"),
            Dimension("output_contract", mapping_has(data, "files", "quality_policy"), "files+quality_policy"),
            Dimension("positive_behavior", data.get("package_contract", {}).get("readback_required") is True, "readback_required"),
            Dimension("negative_behavior", mapping_has(data, "limits") and data.get("limits", {}).get("no_merge") is True, "hard_limits"),
        ]
    return [Dimension(f"unknown_{index}", False, "unsupported_artifact_type") for index in range(6)]


def audit_artifact(root: Path, rel: str, actual: set[str]) -> ArtifactAudit:
    path = root / rel
    body = path.read_text(encoding="utf-8")
    kind = artifact_type(rel)
    try:
        parsed = parsed_payload(path, body)
    except (json.JSONDecodeError, SyntaxError, ValidationInputError):
        parsed = False
    dimensions = base_dimensions(rel, kind, body, parsed, actual)
    dimensions.extend(type_dimensions(rel, kind, body, parsed))
    if len(dimensions) != 10:
        raise ValidationInputError(f"rubric_dimension_count_invalid:{rel}:{len(dimensions)}")
    score = sum(2 for item in dimensions if item.passed)
    tier = artifact_tier(rel)
    return ArtifactAudit(
        path=rel,
        artifact_type=kind,
        tier=tier,
        threshold=THRESHOLD_BY_TIER[tier],
        score=score,
        dimensions=tuple(dimensions),
        bytes_count=len(body.encode("utf-8")),
        token_count=len(TOKEN_RE.findall(body)),
        measurement_method="utf8_bytes+regex_lexeme_v1",
    )


def collect_schema_properties(node: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        properties = node.get("properties")
        if isinstance(properties, dict):
            found.update(str(key) for key in properties)
        for value in node.values():
            found.update(collect_schema_properties(value))
    elif isinstance(node, list):
        for item in node:
            found.update(collect_schema_properties(item))
    return found


def story_contract_fields(body: str) -> set[str]:
    fields: set[str] = set()
    for block in re.findall(r"```text\s*(.*?)```", body, flags=re.DOTALL | re.IGNORECASE):
        for token in SNAKE_FIELD_RE.findall(block):
            if token not in {"true", "false", "null", "maximo", "minimo"}:
                fields.add(token)
    return fields


def contract_schema_consistency(root: Path) -> dict[str, Any]:
    contract_path = root / "references/story-pack-contract.md"
    schema_path = root / "schemas/story-pack.schema.json"
    if not contract_path.is_file() or not schema_path.is_file():
        return {"passed": False, "missing": [str(contract_path), str(schema_path)]}
    contract_fields = story_contract_fields(contract_path.read_text(encoding="utf-8"))
    schema_fields = collect_schema_properties(load_json(schema_path))
    missing_in_schema = sorted(contract_fields - schema_fields)
    return {
        "passed": not missing_in_schema,
        "contract_field_count": len(contract_fields),
        "schema_property_count": len(schema_fields),
        "missing_in_schema": missing_in_schema,
    }


def run_package(root: Path, evidence_refs: list[str], retry_count: int) -> int:
    if not root.is_dir():
        raise ValidationInputError(f"package_root_not_found:{root}")
    manifest = load_yaml(root / "manifest.yaml")
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

    placeholder_hits: list[dict[str, str]] = []
    audits: list[ArtifactAudit] = []
    for rel in sorted(actual & expected):
        body = (root / rel).read_text(encoding="utf-8")
        if rel != "scripts/validate_package.py":
            placeholder_hits.extend(
                {"path": rel, "token": match.group(0)} for match in PLACEHOLDER_RE.finditer(body)
            )
        audits.append(audit_artifact(root, rel, actual))

    low_scores = [audit.as_dict() for audit in audits if not audit.passed]
    consistency = contract_schema_consistency(root)
    checks: dict[str, Any] = {
        "missing_required_files": missing,
        "unexpected_files": unexpected,
        "placeholder_hits": placeholder_hits,
        "artifacts_below_threshold": low_scores,
        "contract_schema_consistency": [] if consistency.get("passed") else [consistency],
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "$package", f"Repair findings: {values[:20]}")
        for key, values in checks.items()
        if values
    ]
    score_distribution: dict[str, int] = {}
    for audit in audits:
        score_distribution[str(audit.score)] = score_distribution.get(str(audit.score), 0) + 1
    evidence = {
        "expected_files": len(expected),
        "actual_files": len(actual),
        "quality_gate_version": "v1.0",
        "rubric_scale": "0-20; 10 dimensions x 2 points",
        "tier_thresholds": THRESHOLD_BY_TIER,
        "measurement_method": "utf8_bytes+regex_lexeme_v1",
        "score_distribution": score_distribution,
        "passed_artifacts": sum(1 for audit in audits if audit.passed),
        "failed_artifacts": len(low_scores),
        "artifact_audits": [audit.as_dict() for audit in audits],
        "checks": checks,
        "contract_schema_consistency": consistency,
        "input_path": str(root),
    }
    return emit(
        result_object(
            JUDGE,
            failed,
            evidence,
            evidence_refs or [f"directory:{root}"],
            repairs,
            retry_count=retry_count,
        )
    )


def write_self_test_package(root: Path, broken: bool) -> None:
    (root / "scripts").mkdir(parents=True)
    (root / "references").mkdir(parents=True)
    (root / "schemas").mkdir(parents=True)
    manifest = {
        "skill_code": "self-test",
        "operation_code": "SELF_TEST",
        "canonical_store": "memory",
        "source_authority": ["self-test"],
        "package_contract": {"readback_required": True},
        "quality_policy": {"audit_scope": "ALL"},
        "files": {
            "root": ["SKILL.md", "manifest.yaml"],
            "references": ["references/story-pack-contract.md"],
            "schemas": ["schemas/story-pack.schema.json"],
            "scripts": ["scripts/validate_package.py"],
        },
        "workflow": {"steps": [{"order": i} for i in range(1, 14)]},
        "limits": {"no_merge": True},
    }
    import yaml

    (root / "manifest.yaml").write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
    skill = """---\nname: self-test\n---\n# Self test\n## Misión\nPurpose.\n## Entradas mínimas\nInput.\n## Procedimiento\nPaso 1.\n## Output\nEntregable.\n## Ejemplo positivo\nPASS_WITH_EVIDENCE.\n## Prohibiciones\nBLOCKED.\n""" + ("x" * 3900)
    (root / "SKILL.md").write_text(skill, encoding="utf-8")
    contract = """# Contract\n## Objetivo\n## Entradas\n## Procedimiento\n## Output\n## Ejemplo positivo\n## Ejemplo negativo\n```text\nidentity, context_budget\n```\n""" + ("x" * 900)
    (root / "references/story-pack-contract.md").write_text(contract, encoding="utf-8")
    properties = {"identity": {"type": "object"}}
    if not broken:
        properties["context_budget"] = {"type": "object"}
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "Self test",
        "type": "object",
        "required": ["identity", "context_budget"],
        "properties": properties,
        "additionalProperties": False,
        "examples": [{"identity": {}, "context_budget": {}}],
    }
    (root / "schemas/story-pack.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    (root / "scripts/validate_package.py").write_text(Path(__file__).read_text(encoding="utf-8"), encoding="utf-8")


def self_test() -> int:
    results: dict[str, Any] = {}
    for name, broken in (("positive", False), ("negative", True)):
        with tempfile.TemporaryDirectory(prefix=f"lf_gate_{name}_") as tmp:
            root = Path(tmp)
            write_self_test_package(root, broken)
            actual = {
                path.relative_to(root).as_posix()
                for path in root.rglob("*")
                if path.is_file()
            }
            audits = [audit_artifact(root, rel, actual) for rel in sorted(actual)]
            consistency = contract_schema_consistency(root)
            results[name] = {
                "all_scores_pass": all(item.passed for item in audits),
                "consistency_pass": consistency.get("passed"),
                "scores": {item.path: item.score for item in audits},
                "missing_in_schema": consistency.get("missing_in_schema", []),
            }
    passed = (
        results["positive"]["consistency_pass"] is True
        and results["negative"]["consistency_pass"] is False
        and "context_budget" in results["negative"]["missing_in_schema"]
    )
    output = {
        "judge_code": JUDGE,
        "result": "PASS_WITH_EVIDENCE" if passed else "FAIL",
        "compliance_bit": 1 if passed else 0,
        "self_test": results,
        "assertion": "positive accepted; negative rejected for contract/schema mismatch",
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


def run() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input", type=Path, nargs="?", help="Package root directory")
    cli.add_argument("--evidence-ref", action="append", default=[])
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--self-test", action="store_true")
    args = cli.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("package_root_required")
    return run_package(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
