"""Deterministic package quality gate for J11_SKILL_PACKAGE.

Audits the manifest inventory, syntax, internal references, placeholder hygiene,
artifact quality dimensions, and Story Pack contract/schema consistency. The
validator is read-only and proves positive and negative behavior with --self-test.
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
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, load_yaml, main_guard, result_object

JUDGE = "J11_SKILL_PACKAGE"
GATE_VERSION = "v1.2"
THRESHOLD = {"NUCLEO": 18, "SOPORTE": 14}
BANDS = {
    "AGENT": (700, 30000), "PROFILE": (1000, 12000), "REFERENCE": (900, 30000),
    "MANIFEST": (3000, 50000), "SCHEMA": (1000, 50000), "SCRIPT": (900, 50000),
    "SHARED_MODULE": (900, 50000), "JUDGE": (900, 12000), "EVAL": (1000, 30000),
    "FIXTURE": (120, 8000), "SKILL_MD": (4000, 30000), "TEMPLATE": (700, 30000),
}
PLACEHOLDER = re.compile(r"\b(?:TODO|TBD|FIXME|LOREM_IPSUM|PENDIENTE_RELLENAR)\b")
PATH_REF = re.compile(r"(?<![A-Za-z0-9_/])(?:SKILL\.md|manifest\.yaml|(?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/[A-Za-z0-9_./-]+\.(?:md|yaml|yml|json|py))")
FORBIDDEN = re.compile(r"(?:^\s*(?:[-*]\s*)?(?:status|estado)\s*[:=]\s*`?(?:VALIDATED|PRODUCTION|APROBADO_FINAL|VIGENTE)\b|\"(?:status|state)\"\s*:\s*\"(?:VALIDATED|PRODUCTION|APROBADO_FINAL|VIGENTE)\")", re.I | re.M)
SNAKE = re.compile(r"^[a-z][a-z0-9_]{2,}$")

CORE_EXACT = {"SKILL.md", "manifest.yaml", "references/field-contract.md", "references/screen-decomposition-protocol.md", "references/story-pack-contract.md"}
SUPPORT_REFS = {
    "references/accessibility-responsive-contract.md", "references/analytics-observability-contract.md",
    "references/audit-traceability-contract.md", "references/observations-errors-contract.md",
    "references/security-privacy-contract.md", "references/supabase-source-map.md",
    "references/test-derivation-contract.md", "references/tokens-messages-contract.md",
}


@dataclass(frozen=True)
class Dimension:
    name: str
    passed: bool
    evidence: str


@dataclass(frozen=True)
class Audit:
    path: str
    kind: str
    tier: str
    score: int
    threshold: int
    dimensions: tuple[Dimension, ...]
    bytes_count: int

    @property
    def passed(self) -> bool:
        return self.score >= self.threshold

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": self.path, "artifact_type": self.kind, "tier": self.tier,
            "score": self.score, "threshold": self.threshold, "passed": self.passed,
            "bytes": self.bytes_count, "measurement_method": "utf8_bytes+structured_rubric_v2",
            "dimensions": [{"name": d.name, "passed": d.passed, "evidence": d.evidence} for d in self.dimensions],
        }


def manifest_paths(manifest: dict[str, Any]) -> list[str]:
    files = manifest.get("files")
    if not isinstance(files, dict):
        raise ValidationInputError("manifest.files_must_be_object")
    paths: list[str] = []
    for values in files.values():
        if isinstance(values, list):
            paths.extend(str(value) for value in values)
    external = manifest.get("external_profiles", {})
    if isinstance(external, dict) and isinstance(external.get("files"), list):
        paths.extend(str(value) for value in external["files"])
    return sorted(set(paths))


def artifact_type(rel: str) -> str:
    if rel == "SKILL.md": return "SKILL_MD"
    if rel == "manifest.yaml": return "MANIFEST"
    if rel == "scripts/lf_common.py": return "SHARED_MODULE"
    if rel.startswith("evals/fixtures/"): return "FIXTURE"
    for prefix, kind in (("agents/", "AGENT"), ("perfiles/", "PROFILE"), ("references/", "REFERENCE"), ("schemas/", "SCHEMA"), ("scripts/", "SCRIPT"), ("judges/", "JUDGE"), ("evals/", "EVAL"), ("templates/", "TEMPLATE")):
        if rel.startswith(prefix): return kind
    raise ValidationInputError(f"artifact_type_not_defined:{rel}")


def artifact_tier(rel: str) -> str:
    if rel in CORE_EXACT: return "NUCLEO"
    if rel.startswith(("agents/", "judges/", "schemas/", "scripts/", "evals/")) and not rel.startswith("evals/fixtures/"): return "NUCLEO"
    if rel.startswith(("perfiles/", "templates/", "evals/fixtures/")) or rel in SUPPORT_REFS: return "SOPORTE"
    raise ValidationInputError(f"tier_not_defined:{rel}")


def parse(path: Path, body: str) -> Any:
    if path.suffix == ".json": return json.loads(body)
    if path.suffix in {".yaml", ".yml"}: return load_yaml(path)
    if path.suffix == ".py": return ast.parse(body, filename=path.as_posix())
    return None


def markdown_dimensions(body: str) -> list[Dimension]:
    low = body.lower()
    h1 = bool(re.search(r"(?m)^#\s+\S", body))
    h2 = len(re.findall(r"(?m)^##\s+", body))
    steps = len(re.findall(r"(?m)^\s*\d+\.\s+", body))
    structured = "```" in body or bool(re.search(r"(?m)^\|.+\|$", body))
    has = lambda *terms: any(term in low for term in terms)
    return [
        Dimension("purpose_scope", h1 and (h2 > 0 or has("misión", "objetivo", "contrato", "perfil")), f"h1={h1} h2={h2}"),
        Dimension("input_contract", structured or has("entrada", "required_inputs", "prerrequisito", "source_snapshot"), "inputs_or_structure"),
        Dimension("deterministic_procedure", steps >= 2 or has("procedimiento", "workflow", "secuencia obligatoria"), f"steps={steps}"),
        Dimension("output_contract", structured or has("salida", "output", "entregable", "schema"), "output_or_structure"),
        Dimension("positive_behavior", has("caso positivo", "ejemplo positivo", "pass_with_evidence", "assertions"), "positive_rule"),
        Dimension("negative_behavior", has("caso negativo", "ejemplo negativo", "blocked", "return_to_worker", "prohib"), "negative_rule"),
    ]


def structured_dimensions(rel: str, kind: str, body: str, parsed: Any) -> list[Dimension]:
    if kind in {"AGENT", "PROFILE", "REFERENCE", "SKILL_MD"}: return markdown_dimensions(body)
    data = parsed if isinstance(parsed, dict) else {}
    serialized = json.dumps(data, ensure_ascii=False, sort_keys=True, default=str).lower() if isinstance(data, (dict, list)) else body.lower()
    if kind == "JUDGE":
        return [
            Dimension("purpose_scope", bool(data.get("judge_code")) and bool(data.get("scope")), "judge identity"),
            Dimension("input_contract", bool(data.get("required_inputs")), "required_inputs"),
            Dimension("deterministic_procedure", bool(data.get("pass_if")) and bool(data.get("block_if")), "pass+block"),
            Dimension("output_contract", bool(data.get("output")) and bool(data.get("result_values")), "output+results"),
            Dimension("positive_behavior", bool(data.get("pass_if")), "pass_if"),
            Dimension("negative_behavior", bool(data.get("fail_if")) and bool(data.get("block_if")), "fail+block"),
        ]
    if kind == "SCHEMA":
        constrained = any(token in serialized for token in ('"required"', '"enum"', '"minitems"', '"pattern"', '"additionalproperties"'))
        return [
            Dimension("purpose_scope", all(key in data for key in ("$schema", "title", "type")), "schema identity"),
            Dimension("input_contract", bool(data.get("required")) or "properties" in data, "required_or_properties"),
            Dimension("deterministic_procedure", "properties" in data or "items" in data, "shape"),
            Dimension("output_contract", data.get("type") in {"object", "array"}, "root type"),
            Dimension("positive_behavior", bool(data.get("examples")) or constrained, "positive shape"),
            Dimension("negative_behavior", constrained, "rejection constraints"),
        ]
    if kind in {"SCRIPT", "SHARED_MODULE"}:
        tree = parsed if isinstance(parsed, ast.AST) else None
        functions = [n.name for n in ast.walk(tree) if hasattr(n, "name")] if tree else []
        args = "argparse" in body
        return [
            Dimension("purpose_scope", bool(ast.get_docstring(tree)) if tree else False, "module docstring"),
            Dimension("input_contract", args or "ValidationInputError" in body or "add_common_input" in body or "load_json" in body, "cli_or_input_contract"),
            Dimension("deterministic_procedure", len(functions) >= 1, f"functions={len(functions)}"),
            Dimension("output_contract", "result_object" in body or "json.dumps" in body, "structured result"),
            Dimension("positive_behavior", "self_test" in functions or "positive" in functions or ("result_object" in body and "emit(" in body), "positive executable"),
            Dimension("negative_behavior", "failure(" in body or "negative" in functions or "ValidationInputError" in body, "negative executable"),
        ]
    if kind == "MANIFEST":
        workflow = data.get("workflow", {}) if isinstance(data.get("workflow"), dict) else {}
        steps = workflow.get("steps", []) if isinstance(workflow.get("steps"), list) else []
        return [
            Dimension("purpose_scope", all(key in data for key in ("skill_code", "operation_code", "package_contract")), "identity+package"),
            Dimension("input_contract", "source_authority" in data and "canonical_store" in data, "sources"),
            Dimension("deterministic_procedure", len(steps) == 13, f"steps={len(steps)}"),
            Dimension("output_contract", "files" in data and "quality_policy" in data, "files+quality"),
            Dimension("positive_behavior", data.get("package_contract", {}).get("readback_required") is True, "readback"),
            Dimension("negative_behavior", data.get("limits", {}).get("no_merge") is True, "no_merge"),
        ]
    if kind == "EVAL":
        return [
            Dimension("purpose_scope", any(key in data for key in ("cases", "assertions", "triggers")), "eval collection"),
            Dimension("input_contract", any(token in serialized for token in ("fixture_ref", "prompt", "target", "input")), "eval input"),
            Dimension("deterministic_procedure", any(token in serialized for token in ("assertions", "condition", "check", "rule")), "eval rules"),
            Dimension("output_contract", any(token in serialized for token in ("expected_result", "expected_output", "repair")), "expected output"),
            Dimension("positive_behavior", any(token in serialized for token in ("positive", "pass_with_evidence", "compliance_bit")), "positive case"),
            Dimension("negative_behavior", any(token in serialized for token in ("negative", "return_to_worker", "blocked", "fail")), "negative case"),
        ]
    if kind == "FIXTURE":
        nested = data.get("fixture", data)
        nested_text = json.dumps(nested, sort_keys=True).lower() if isinstance(nested, (dict, list)) else ""
        identity = any(key in data for key in ("fixture_id", "fixture_version", "screen_code", "case_id", "id", "version"))
        structural = any(f'"{key}"' in nested_text for key in ("exact_inputs", "fields", "actions", "contexts", "permissions", "steps", "screen_code"))
        assertions = data.get("assertions")
        negatives = data.get("negative_cases")
        return [
            Dimension("purpose_scope", identity or bool(str(data.get("purpose", "")).strip()), "fixture identity"),
            Dimension("input_contract", isinstance(nested, (dict, list)) and len(data) >= 3, f"root_keys={len(data)}"),
            Dimension("deterministic_procedure", structural, "nested domain input"),
            Dimension("output_contract", any(key in data for key in ("assertions", "expected_result", "evidence_path")), "assertions/evidence"),
            Dimension("positive_behavior", structural and isinstance(assertions, list) and bool(assertions), "fixture+assertions"),
            Dimension("negative_behavior", isinstance(negatives, list) and bool(negatives) or any(term in rel for term in ("insufficient", "sensitive", "invalid")), "negative cases"),
        ]
    if kind == "TEMPLATE":
        placeholder = bool(re.search(r"<[^>]+>|\{\{[^}]+\}\}", body))
        low = body.lower()
        return [
            Dimension("purpose_scope", placeholder, "template placeholders"),
            Dimension("input_contract", placeholder and len(body) >= 700, "fillable"),
            Dimension("deterministic_procedure", any(term in low for term in ("given", "when", "then", "required", "judge", "evidence")), "structured"),
            Dimension("output_contract", body.strip().startswith(("{", "#", "judge_code", "---")), "renderable root"),
            Dimension("positive_behavior", any(term in low for term in ("pass_with_evidence", "candidato_read_only", "expected")), "positive state"),
            Dimension("negative_behavior", any(term in low for term in ("blocked", "failed", "pending_decision", "repair", "prohibited")), "negative state"),
        ]
    raise ValidationInputError(f"unsupported_artifact_type:{kind}:{rel}")


def audit_artifact(root: Path, rel: str, actual: set[str]) -> Audit:
    path = root / rel
    body = path.read_text(encoding="utf-8")
    kind = artifact_type(rel)
    try:
        parsed = parse(path, body)
        syntax = True
        syntax_evidence = "utf8_and_parser_ok"
    except (json.JSONDecodeError, SyntaxError, ValidationInputError) as exc:
        parsed = None
        syntax = False
        syntax_evidence = str(exc)
    refs = sorted(set(PATH_REF.findall(body)) - {rel})
    broken = [ref for ref in refs if ref not in actual]
    forbidden = [] if rel in {"manifest.yaml", "scripts/validate_package.py"} else sorted(set(m.group(0).strip() for m in FORBIDDEN.finditer(body)))
    low, high = BANDS[kind]
    dimensions = [
        Dimension("syntax_parse", syntax, syntax_evidence),
        Dimension("byte_band", low <= len(body.encode()) <= high, f"bytes={len(body.encode())} band={low}-{high}"),
        Dimension("internal_references", not broken, f"broken={broken[:10]}"),
        Dimension("forbidden_status_assignment", not forbidden, f"hits={forbidden[:10]}"),
        *structured_dimensions(rel, kind, body, parsed),
    ]
    if len(dimensions) != 10:
        raise ValidationInputError(f"rubric_dimension_count_invalid:{rel}:{len(dimensions)}")
    tier = artifact_tier(rel)
    return Audit(rel, kind, tier, sum(2 for d in dimensions if d.passed), THRESHOLD[tier], tuple(dimensions), len(body.encode()))


def schema_properties(node: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        if isinstance(node.get("properties"), dict): found.update(str(key) for key in node["properties"])
        for value in node.values(): found.update(schema_properties(value))
    elif isinstance(node, list):
        for value in node: found.update(schema_properties(value))
    return found


def contract_fields(body: str) -> set[str]:
    fields: set[str] = set()
    for block in re.findall(r"```text\s*(.*?)```", body, re.S | re.I):
        for line in block.splitlines():
            if "," not in line or "=" in line: continue
            for raw in line.split(","):
                token = raw.strip().strip("`.* ")
                if SNAKE.fullmatch(token): fields.add(token)
    return fields


def contract_schema_consistency(root: Path) -> dict[str, Any]:
    contract = root / "references/story-pack-contract.md"
    schema = root / "schemas/story-pack.schema.json"
    if not contract.is_file() or not schema.is_file():
        return {"passed": False, "missing_files": [str(contract), str(schema)]}
    documented = contract_fields(contract.read_text(encoding="utf-8"))
    implemented = schema_properties(load_json(schema))
    missing = sorted(documented - implemented)
    return {"passed": not missing, "contract_field_count": len(documented), "schema_property_count": len(implemented), "missing_in_schema": missing}


def package_audit(root: Path) -> dict[str, Any]:
    if not root.is_dir(): raise ValidationInputError(f"package_root_not_found:{root}")
    manifest = load_yaml(root / "manifest.yaml")
    if not isinstance(manifest, dict): raise ValidationInputError("manifest_must_be_object")
    expected = set(manifest_paths(manifest)) | {"SKILL.md", "manifest.yaml"}
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"}
    audits = [audit_artifact(root, rel, actual) for rel in sorted(expected & actual)]
    placeholders: list[dict[str, str]] = []
    for rel in sorted(expected & actual):
        if rel == "scripts/validate_package.py": continue
        body = (root / rel).read_text(encoding="utf-8")
        scannable = re.sub(r"`[^`\n]+`", "", body)
        placeholders.extend({"path": rel, "token": match.group(0)} for match in PLACEHOLDER.finditer(scannable))
    return {
        "expected": expected, "actual": actual, "missing": sorted(expected - actual), "unexpected": sorted(actual - expected),
        "placeholders": placeholders, "audits": audits, "consistency": contract_schema_consistency(root),
    }


def directory_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc"):
        digest.update(path.relative_to(root).as_posix().encode()); digest.update(b"\0"); digest.update(hashlib.sha256(path.read_bytes()).digest()); digest.update(b"\n")
    return digest.hexdigest()


def emit_package_result(root: Path, evidence_refs: list[str], retry_count: int) -> int:
    audit = package_audit(root)
    low = [item.as_dict() for item in audit["audits"] if not item.passed]
    checks = {
        "missing_required_files": audit["missing"], "unexpected_files": audit["unexpected"],
        "placeholder_hits": audit["placeholders"], "artifacts_below_threshold": low,
        "contract_schema_consistency": [] if audit["consistency"].get("passed") else [audit["consistency"]],
    }
    failed = [f"{key}={len(value)}" for key, value in checks.items() if value]
    repairs = [failure(key, "$package", f"Repair findings: {value[:20]}") for key, value in checks.items() if value]
    evidence = {
        "quality_gate_version": GATE_VERSION, "rubric_scale": "0-20; 10 dimensions x 2 points",
        "tier_thresholds": THRESHOLD, "measurement_method": "utf8_bytes+structured_rubric_v2",
        "expected_files": len(audit["expected"]), "actual_files": len(audit["actual"]),
        "passed_artifacts": sum(1 for item in audit["audits"] if item.passed), "failed_artifacts": len(low),
        "artifact_audits": [item.as_dict() for item in audit["audits"]], "contract_schema_consistency": audit["consistency"],
        "checks": checks, "input_path": str(root), "input_sha256": directory_sha256(root),
    }
    return emit(result_object(JUDGE, failed, evidence, evidence_refs or [f"directory:{root}"], repairs, retry_count=retry_count))


def write_self_test(root: Path, broken: bool) -> None:
    for folder in ("scripts", "references", "schemas"): (root / folder).mkdir(parents=True, exist_ok=True)
    import yaml
    manifest = {
        "skill_code": "self-test", "operation_code": "SELF_TEST", "canonical_store": "memory", "source_authority": ["self-test"],
        "package_contract": {"readback_required": True}, "quality_policy": {"audit_scope": "ALL"},
        "files": {"root": ["SKILL.md", "manifest.yaml"], "references": ["references/story-pack-contract.md"], "schemas": ["schemas/story-pack.schema.json"], "scripts": ["scripts/validate_package.py"]},
        "workflow": {"steps": [{"order": i} for i in range(1, 14)]}, "limits": {"no_merge": True},
    }
    (root / "manifest.yaml").write_text(yaml.safe_dump(manifest, sort_keys=False))
    (root / "SKILL.md").write_text("---\nname: self-test\nstatus: CANDIDATO_READ_ONLY\n---\n# Self test\n## Misión\nPurpose.\n## Entradas\nInput.\n## Procedimiento\n1. Execute.\n2. Verify.\n## Salida\nOutput.\n## Caso positivo\nPASS_WITH_EVIDENCE.\n## Caso negativo\nBLOCKED.\n" + "x" * 3900)
    (root / "references/story-pack-contract.md").write_text("# Contract\n## Objective\n## Inputs\n## Procedure\n1. Read.\n2. Verify.\n## Output\n## Positive\nPASS_WITH_EVIDENCE.\n## Negative\nBLOCKED.\n```text\nidentity, context_budget\n```\n" + "x" * 900)
    props: dict[str, Any] = {"identity": {"type": "object"}}
    if not broken: props["context_budget"] = {"type": "object"}
    schema = {"$schema": "http://json-schema.org/draft-07/schema#", "title": "Self test", "description": "x" * 1000, "type": "object", "required": ["identity", "context_budget"], "properties": props, "additionalProperties": False, "examples": [{"identity": {}, "context_budget": {}}]}
    (root / "schemas/story-pack.schema.json").write_text(json.dumps(schema))
    (root / "scripts/validate_package.py").write_text(Path(__file__).read_text())


def self_test() -> int:
    results: dict[str, Any] = {}
    for name, broken in (("positive", False), ("negative", True)):
        with tempfile.TemporaryDirectory(prefix=f"lf_gate_{name}_") as tmp:
            root = Path(tmp); write_self_test(root, broken); audit = package_audit(root)
            results[name] = {"all_artifacts_meet_threshold": all(item.passed for item in audit["audits"]), "consistency_pass": audit["consistency"].get("passed"), "missing_in_schema": audit["consistency"].get("missing_in_schema", [])}
    passed = results["positive"]["all_artifacts_meet_threshold"] and results["positive"]["consistency_pass"] and not results["negative"]["consistency_pass"] and "context_budget" in results["negative"]["missing_in_schema"]
    print(json.dumps({"judge_code": JUDGE, "result": "PASS_WITH_EVIDENCE" if passed else "FAIL", "compliance_bit": int(passed), "quality_gate_version": GATE_VERSION, "self_test": results}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input", nargs="?", type=Path)
    cli.add_argument("--evidence-ref", action="append", default=[])
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--self-test", action="store_true")
    args = cli.parse_args()
    if args.self_test: return self_test()
    if args.input is None: raise ValidationInputError("package_root_required")
    return emit_package_result(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
