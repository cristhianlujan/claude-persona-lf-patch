"""Execute the LF package quality gate for J11.

The gate audits every manifest artifact with a deterministic 0-20 rubric,
checks package inventory and internal references, reconciles the Story Pack
contract with its JSON Schema, and proves both acceptance and rejection through
``--self-test``. It never writes application data.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

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
GATE_VERSION = "v1.1"
THRESHOLD_BY_TIER = {"NUCLEO": 18, "SOPORTE": 14}
TOKEN_RE = re.compile(r"\w+|[^\w\s]", re.UNICODE)
PLACEHOLDER_RE = re.compile(r"\b(?:TODO|TBD|FIXME|LOREM_IPSUM|PENDIENTE_RELLENAR)\b")
PATH_RE = re.compile(
    r"(?<![A-Za-z0-9_/])"
    r"(?:SKILL\.md|manifest\.yaml|"
    r"(?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/"
    r"[A-Za-z0-9_./-]+\.(?:md|yaml|yml|json|py))"
)
FORBIDDEN_ASSIGNMENT_RE = re.compile(
    r"(?:^\s*(?:[-*]\s*)?(?:status|estado)\s*[:=]\s*`?"
    r"(?:VALIDATED|PRODUCTION|APROBADO_FINAL|VIGENTE)\b|"
    r"\"(?:status|state)\"\s*:\s*\""
    r"(?:VALIDATED|PRODUCTION|APROBADO_FINAL|VIGENTE)\")",
    re.IGNORECASE | re.MULTILINE,
)
SNAKE_FIELD_RE = re.compile(r"^[a-z][a-z0-9_]{2,}$")

CORE_EXACT = {
    "SKILL.md",
    "manifest.yaml",
    "references/field-contract.md",
    "references/screen-decomposition-protocol.md",
    "references/story-pack-contract.md",
}
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
            "measurement_method": "utf8_bytes+regex_lexeme_v1",
            "dimensions": [
                {"name": item.name, "passed": item.passed, "evidence": item.evidence}
                for item in self.dimensions
            ],
        }


def manifest_paths(manifest: dict[str, Any]) -> list[str]:
    files = manifest.get("files", {})
    if not isinstance(files, dict):
        raise ValidationInputError("manifest.files_must_be_object")
    paths: list[str] = []
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
    if rel == "scripts/lf_common.py":
        return "SHARED_MODULE"
    if rel.startswith("evals/fixtures/"):
        return "FIXTURE"
    for prefix, kind in (
        ("agents/", "AGENT"),
        ("perfiles/", "PROFILE"),
        ("references/", "REFERENCE"),
        ("schemas/", "SCHEMA"),
        ("scripts/", "SCRIPT"),
        ("judges/", "JUDGE"),
        ("evals/", "EVAL"),
        ("templates/", "TEMPLATE"),
    ):
        if rel.startswith(prefix):
            return kind
    raise ValidationInputError(f"artifact_type_not_defined:{rel}")


def artifact_tier(rel: str) -> str:
    if rel in CORE_EXACT:
        return "NUCLEO"
    if rel.startswith("evals/fixtures/") or rel.startswith(("perfiles/", "templates/")):
        return "SOPORTE"
    if rel in SUPPORT_REFERENCES:
        return "SOPORTE"
    if rel.startswith(("agents/", "judges/", "schemas/", "scripts/", "evals/")):
        return "NUCLEO"
    raise ValidationInputError(f"tier_not_defined:{rel}")


def parsed_payload(path: Path, body: str) -> Any:
    if path.suffix == ".json":
        return json.loads(body)
    if path.suffix in {".yaml", ".yml"}:
        return load_yaml(path)
    if path.suffix == ".py":
        return ast.parse(body, filename=path.as_posix())
    return None


def has_any(text: str, terms: Iterable[str]) -> bool:
    lowered = text.lower()
    return any(term.lower() in lowered for term in terms)


def mapping_has(data: Any, *keys: str) -> bool:
    return isinstance(data, dict) and all(key in data for key in keys)


def reference_state(body: str, rel: str, actual: set[str]) -> tuple[bool, str]:
    refs = sorted(set(PATH_RE.findall(body)) - {rel})
    broken = [ref for ref in refs if ref not in actual]
    return not broken, f"refs={len(refs)} broken={broken[:10]}"


def forbidden_state(body: str, rel: str) -> tuple[bool, str]:
    if rel in {"manifest.yaml", "scripts/validate_package.py"}:
        return True, "policy_definition_exempt"
    hits = sorted(set(match.group(0).strip() for match in FORBIDDEN_ASSIGNMENT_RE.finditer(body)))
    return not hits, f"forbidden_assignments={hits}"


def markdown_dimensions(body: str) -> list[Dimension]:
    lower = body.lower()
    h1 = bool(re.search(r"(?m)^#\s+\S", body))
    h2_count = len(re.findall(r"(?m)^##\s+", body))
    numbered_steps = len(re.findall(r"(?m)^\s*\d+\.\s+", body))
    code_or_table = "```" in body or bool(re.search(r"(?m)^\|.+\|$", body))
    purpose = h1 and (
        h2_count > 0
        or has_any(lower, ("contrato", "protocolo", "perfil", "agent", "misión", "objetivo"))
    )
    inputs = has_any(
        lower,
        (
            "entrada", "required_inputs", "claves obligatorias", "campos obligatorios",
            "fuente requerida", "prerrequisito", "source_snapshot",
        ),
    ) or code_or_table
    procedure = has_any(
        lower,
        (
            "procedimiento", "workflow", "flujo", "secuencia obligatoria", "reglas duras",
            "reglas de ejecución", "condiciones de paso", "paso 1", "ciclo",
        ),
    ) or numbered_steps >= 2
    output = has_any(
        lower,
        ("salida", "output", "entregable", "schema", "formato", "contrato", "secciones a-q"),
    ) or code_or_table
    positive = has_any(
        lower,
        (
            "ejemplo positivo", "caso positivo", "pass_with_evidence", "condiciones de paso",
            "assertions", "obligatori", "debe tener", "required",
        ),
    )
    negative = has_any(
        lower,
        (
            "ejemplo negativo", "caso negativo", "prohib", "acciones prohibidas", "reglas duras",
            "falla", "blocked", "return_to_worker", "no puede", "no emitir",
        ),
    )
    return [
        Dimension("purpose_scope", purpose, f"h1={h1} h2={h2_count}"),
        Dimension("input_contract", inputs, "inputs_or_structured_contract"),
        Dimension("deterministic_procedure", procedure, f"numbered_steps={numbered_steps}"),
        Dimension("output_contract", output, "output_or_structured_format"),
        Dimension("positive_behavior", positive, "positive_rule_or_assertion"),
        Dimension("negative_behavior", negative, "negative_rule_or_stop_condition"),
    ]


def type_dimensions(rel: str, kind: str, body: str, parsed: Any) -> list[Dimension]:
    lower = body.lower()
    if kind in {"AGENT", "PROFILE", "REFERENCE", "SKILL_MD"}:
        return markdown_dimensions(body)

    if kind == "JUDGE":
        data = parsed if isinstance(parsed, dict) else {}
        return [
            Dimension("purpose_scope", mapping_has(data, "judge_code", "scope"), "judge_code+scope"),
            Dimension("input_contract", bool(data.get("required_inputs")), "required_inputs_nonempty"),
            Dimension("deterministic_procedure", mapping_has(data, "pass_if", "fail_if", "block_if"), "pass/fail/block"),
            Dimension("output_contract", mapping_has(data, "output", "result_values"), "output+result_values"),
            Dimension("positive_behavior", bool(data.get("pass_if")), "pass_if_nonempty"),
            Dimension("negative_behavior", bool(data.get("fail_if")) and bool(data.get("block_if")), "fail_if+block_if"),
        ]

    if kind == "SCHEMA":
        data = parsed if isinstance(parsed, dict) else {}
        serialized = json.dumps(data, ensure_ascii=False)
        has_shape = "properties" in data or "items" in data
        has_constraint = any(
            token in serialized
            for token in ('"enum"', '"required"', '"minLength"', '"minItems"', '"pattern"', '"additionalProperties"')
        )
        return [
            Dimension("purpose_scope", mapping_has(data, "$schema", "title", "type"), "$schema+title+type"),
            Dimension("input_contract", bool(data.get("required")) or has_shape, "required_or_shape"),
            Dimension("deterministic_procedure", has_shape, "properties_or_items"),
            Dimension("output_contract", data.get("type") in {"object", "array"}, "bounded_root_type"),
            Dimension("positive_behavior", has_shape and bool(data.get("required") or data.get("examples")), "valid_shape_defined"),
            Dimension("negative_behavior", has_constraint, "rejecting_constraint"),
        ]

    if kind in {"SCRIPT", "SHARED_MODULE"}:
        tree = parsed if isinstance(parsed, ast.AST) else None
        functions = {
            node.name
            for node in ast.walk(tree)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        } if tree else set()
        input_contract = has_any(
            lower,
            ("argparse", "argv_path", "add_common_input", "load_json", "load_yaml", "parser("),
        )
        positive_path = has_any(
            lower,
            ("pass_with_evidence", "compliance_bit", "self-test", "self_test"),
        ) or ("failed = []" in lower and "emit(" in lower)
        negative_path = has_any(
            lower,
            ("failed.append", "failure(", "validationinputerror", "raise ", "except", "return_to_worker", "blocked"),
        )
        return [
            Dimension("purpose_scope", bool(ast.get_docstring(tree)) if tree else False, "module_docstring"),
            Dimension("input_contract", input_contract, "cli_or_file_input"),
            Dimension("deterministic_procedure", len(functions) >= 1, f"functions={sorted(functions)}"),
            Dimension("output_contract", has_any(lower, ("result_object", "emit(", "print(", "return")), "structured_output"),
            Dimension("positive_behavior", positive_path, "positive_result_path"),
            Dimension("negative_behavior", negative_path, "negative_result_path"),
        ]

    if kind == "EVAL":
        data = parsed if isinstance(parsed, dict) else {}
        serialized = json.dumps(data, ensure_ascii=False).lower()
        registry = any(key in data for key in ("cases", "assertions", "triggers"))
        return [
            Dimension("purpose_scope", registry, "eval_collection"),
            Dimension("input_contract", any(term in serialized for term in ("fixture_ref", "prompt", "target", "input")), "input_or_target"),
            Dimension("deterministic_procedure", any(term in serialized for term in ("assertions", "condition", "check", "rule")), "assertion_or_rule"),
            Dimension("output_contract", any(term in serialized for term in ("expected_result", "expected_output", "result", "repair")), "expected_or_repair_output"),
            Dimension("positive_behavior", any(term in serialized for term in ('"positive"', "pass_with_evidence", "compliance_bit")), "positive_case_or_result"),
            Dimension("negative_behavior", any(term in serialized for term in ('"negative"', "return_to_worker", "blocked", '"fail"')), "negative_case_or_result"),
        ]

    if kind == "FIXTURE":
        data = parsed if isinstance(parsed, dict) else {}
        keys = set(data)
        structural = bool(keys & {"fields", "actions", "contexts", "permissions", "steps", "screen_code"})
        negative_signal = bool(keys & {"missing", "sensitive", "invalid", "expected_result"}) or any(
            term in rel for term in ("insufficient", "sensitive", "invalid")
        )
        return [
            Dimension("purpose_scope", bool(keys & {"screen_code", "case_id", "id", "version"}), "fixture_identity"),
            Dimension("input_contract", len(keys) >= 3, f"root_keys={len(keys)}"),
            Dimension("deterministic_procedure", structural, "domain_structure"),
            Dimension("output_contract", bool(keys & {"version", "expected_result", "screen_code"}), "version_or_expected_result"),
            Dimension("positive_behavior", structural, "executable_shape"),
            Dimension("negative_behavior", negative_signal, "negative_signal_when_applicable"),
        ]

    if kind == "TEMPLATE":
        placeholder = bool(re.search(r"<[^>]+>|\{\{[^}]+\}\}", body))
        return [
            Dimension("purpose_scope", placeholder, "template_placeholders"),
            Dimension("input_contract", placeholder and len(body) >= 700, "fillable_contract"),
            Dimension("deterministic_procedure", has_any(lower, ("given", "when", "then", "required", "judge", "evidence")), "structured_sections"),
            Dimension("output_contract", body.strip().startswith(("{", "#", "judge_code", "---")), "renderable_root"),
            Dimension("positive_behavior", has_any(lower, ("pass_with_evidence", "candidato_read_only", "given", "expected")), "valid_target_state"),
            Dimension("negative_behavior", has_any(lower, ("blocked", "failed", "pending_decision", "out_of_scope", "repair", "prohibited")), "failure_or_pending_state"),
        ]

    if kind == "MANIFEST":
        data = parsed if isinstance(parsed, dict) else {}
        workflow = data.get("workflow", {}) if isinstance(data.get("workflow"), dict) else {}
        steps = workflow.get("steps", []) if isinstance(workflow, dict) else []
        package = data.get("package_contract", {}) if isinstance(data.get("package_contract"), dict) else {}
        limits = data.get("limits", {}) if isinstance(data.get("limits"), dict) else {}
        return [
            Dimension("purpose_scope", mapping_has(data, "skill_code", "operation_code", "package_contract"), "identity+package_contract"),
            Dimension("input_contract", mapping_has(data, "source_authority", "canonical_store"), "sources+canonical_store"),
            Dimension("deterministic_procedure", isinstance(steps, list) and len(steps) == 13, f"workflow_steps={len(steps) if isinstance(steps, list) else 0}"),
            Dimension("output_contract", mapping_has(data, "files", "quality_policy"), "files+quality_policy"),
            Dimension("positive_behavior", package.get("readback_required") is True, "readback_required"),
            Dimension("negative_behavior", limits.get("no_merge") is True, "no_merge_hard_limit"),
        ]

    raise ValidationInputError(f"unsupported_artifact_type:{kind}")


def audit_artifact(root: Path, rel: str, actual: set[str]) -> ArtifactAudit:
    path = root / rel
    try:
        body = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ValidationInputError(f"input_not_utf8:{rel}") from exc
    kind = artifact_type(rel)
    try:
        parsed = parsed_payload(path, body)
        syntax_ok = True
        syntax_evidence = "utf8_and_parser_ok"
    except (json.JSONDecodeError, SyntaxError, ValidationInputError) as exc:
        parsed = False
        syntax_ok = False
        syntax_evidence = str(exc)
    low, high = BYTE_BANDS[kind]
    refs_ok, refs_evidence = reference_state(body, rel, actual)
    status_ok, status_evidence = forbidden_state(body, rel)
    dimensions = [
        Dimension("syntax_parse", syntax_ok, syntax_evidence),
        Dimension("byte_band", low <= len(body.encode("utf-8")) <= high, f"bytes={len(body.encode('utf-8'))} band={low}-{high}"),
        Dimension("internal_references", refs_ok, refs_evidence),
        Dimension("forbidden_status_assignment", status_ok, status_evidence),
        *type_dimensions(rel, kind, body, parsed),
    ]
    if len(dimensions) != 10:
        raise ValidationInputError(f"rubric_dimension_count_invalid:{rel}:{len(dimensions)}")
    tier = artifact_tier(rel)
    return ArtifactAudit(
        path=rel,
        artifact_type=kind,
        tier=tier,
        threshold=THRESHOLD_BY_TIER[tier],
        score=sum(2 for item in dimensions if item.passed),
        dimensions=tuple(dimensions),
        bytes_count=len(body.encode("utf-8")),
        token_count=len(TOKEN_RE.findall(body)),
    )


def collect_schema_properties(node: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        props = node.get("properties")
        if isinstance(props, dict):
            found.update(str(key) for key in props)
        for value in node.values():
            found.update(collect_schema_properties(value))
    elif isinstance(node, list):
        for item in node:
            found.update(collect_schema_properties(item))
    return found


def story_contract_fields(body: str) -> set[str]:
    fields: set[str] = set()
    for block in re.findall(r"```text\s*(.*?)```", body, flags=re.DOTALL | re.IGNORECASE):
        for line in block.splitlines():
            if "," not in line or "=" in line:
                continue
            for raw in line.split(","):
                token = raw.strip().strip("`.* ")
                if SNAKE_FIELD_RE.fullmatch(token):
                    fields.add(token)
    return fields


def contract_schema_consistency(root: Path) -> dict[str, Any]:
    contract_path = root / "references/story-pack-contract.md"
    schema_path = root / "schemas/story-pack.schema.json"
    if not contract_path.is_file() or not schema_path.is_file():
        return {"passed": False, "missing_files": [str(contract_path), str(schema_path)]}
    contract_fields = story_contract_fields(contract_path.read_text(encoding="utf-8"))
    schema_fields = collect_schema_properties(load_json(schema_path))
    missing = sorted(contract_fields - schema_fields)
    return {
        "passed": not missing,
        "contract_field_count": len(contract_fields),
        "schema_property_count": len(schema_fields),
        "missing_in_schema": missing,
    }


def package_audit(root: Path) -> dict[str, Any]:
    if not root.is_dir():
        raise ValidationInputError(f"package_root_not_found:{root}")
    manifest = load_yaml(root / "manifest.yaml")
    if not isinstance(manifest, dict):
        raise ValidationInputError("manifest_must_be_object")
    expected = set(manifest_paths(manifest)) | {"SKILL.md", "manifest.yaml"}
    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
    }
    audits = [audit_artifact(root, rel, actual) for rel in sorted(expected & actual)]
    placeholders: list[dict[str, str]] = []
    for rel in sorted(expected & actual):
        if rel == "scripts/validate_package.py":
            continue
        body = (root / rel).read_text(encoding="utf-8")
        placeholders.extend({"path": rel, "token": m.group(0)} for m in PLACEHOLDER_RE.finditer(body))
    consistency = contract_schema_consistency(root)
    return {
        "expected": expected,
        "actual": actual,
        "missing": sorted(expected - actual),
        "unexpected": sorted(actual - expected),
        "placeholders": placeholders,
        "audits": audits,
        "consistency": consistency,
    }


def package_input_sha256(root: Path) -> str:
    """Hash a package directory deterministically from paths and file contents."""
    digest = hashlib.sha256()
    files = sorted(
        path for path in root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
    )
    for path in files:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
        digest.update(b"\n")
    return digest.hexdigest()


def emit_package_result(root: Path, evidence_refs: list[str], retry_count: int) -> int:
    audit = package_audit(root)
    low_scores = [item.as_dict() for item in audit["audits"] if not item.passed]
    checks = {
        "missing_required_files": audit["missing"],
        "unexpected_files": audit["unexpected"],
        "placeholder_hits": audit["placeholders"],
        "artifacts_below_threshold": low_scores,
        "contract_schema_consistency": [] if audit["consistency"].get("passed") else [audit["consistency"]],
    }
    failed = [f"{key}={len(value)}" for key, value in checks.items() if value]
    repairs = [failure(key, "$package", f"Repair findings: {value[:20]}") for key, value in checks.items() if value]
    distribution: dict[str, int] = {}
    for item in audit["audits"]:
        distribution[str(item.score)] = distribution.get(str(item.score), 0) + 1
    evidence = {
        "quality_gate_version": GATE_VERSION,
        "rubric_scale": "0-20; 10 dimensions x 2 points",
        "tier_thresholds": THRESHOLD_BY_TIER,
        "measurement_method": "utf8_bytes+regex_lexeme_v1",
        "expected_files": len(audit["expected"]),
        "actual_files": len(audit["actual"]),
        "passed_artifacts": sum(1 for item in audit["audits"] if item.passed),
        "failed_artifacts": len(low_scores),
        "score_distribution": distribution,
        "artifact_audits": [item.as_dict() for item in audit["audits"]],
        "contract_schema_consistency": audit["consistency"],
        "checks": checks,
        "input_path": str(root),
        "input_sha256": package_input_sha256(root),
    }
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        evidence_refs or [f"directory:{root}"],
        repairs,
        retry_count=retry_count,
    ))


def write_self_test_package(root: Path, broken: bool) -> None:
    for folder in ("scripts", "references", "schemas"):
        (root / folder).mkdir(parents=True, exist_ok=True)
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
    skill = """---\nname: self-test\nstatus: CANDIDATO_READ_ONLY\n---\n# Self test\n## 1. Misión\nPurpose.\n## 2. Entradas\nInput.\n## 3. Procedimiento\n1. Execute.\n2. Verify.\n## 4. Salida\nEntregable.\n## 5. Ejemplo positivo\nPASS_WITH_EVIDENCE.\n## 6. Prohibiciones\nBLOCKED.\n""" + ("x" * 3900)
    (root / "SKILL.md").write_text(skill, encoding="utf-8")
    contract = """# Contrato de prueba\n## Objetivo\n## Entradas\n## Secuencia obligatoria\n1. Read.\n2. Verify.\n## Salida\n## Condiciones de paso\n## Reglas duras\n```text\nidentity, context_budget\n```\n""" + ("x" * 900)
    (root / "references/story-pack-contract.md").write_text(contract, encoding="utf-8")
    properties: dict[str, Any] = {"identity": {"type": "object"}}
    if not broken:
        properties["context_budget"] = {"type": "object"}
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "Self test",
        "description": "x" * 1000,
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
            audit = package_audit(root)
            results[name] = {
                "all_artifacts_meet_threshold": all(item.passed for item in audit["audits"]),
                "scores": {item.path: item.score for item in audit["audits"]},
                "consistency_pass": audit["consistency"].get("passed"),
                "missing_in_schema": audit["consistency"].get("missing_in_schema", []),
            }
    passed = (
        results["positive"]["all_artifacts_meet_threshold"] is True
        and results["positive"]["consistency_pass"] is True
        and results["negative"]["consistency_pass"] is False
        and "context_budget" in results["negative"]["missing_in_schema"]
    )
    print(json.dumps({
        "judge_code": JUDGE,
        "result": "PASS_WITH_EVIDENCE" if passed else "FAIL",
        "compliance_bit": 1 if passed else 0,
        "quality_gate_version": GATE_VERSION,
        "assertion": "positive accepted; negative rejected for contract/schema mismatch",
        "self_test": results,
    }, ensure_ascii=False, sort_keys=True))
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
    return emit_package_result(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
