#!/usr/bin/env python3
"""Sequential, evidence-first audit for the 62 creating-integral-user-stories artifacts.

The runner never changes canonical artifacts. It emits one JSON report per artifact and
fails when a gate is not demonstrated. Scores are derived from explicit checks; they
are not accepted from an artifact's prior validation_evidence.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

try:
    import jsonschema
except ImportError:  # pragma: no cover
    jsonschema = None

ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = ROOT / "skills" / "creating-integral-user-stories"

ARTIFACTS: list[tuple[str, str]] = [
    ("A01", "agents/cross-cutting-enricher.md"),
    ("A02", "agents/field-contract-author.md"),
    ("A03", "agents/screen-decomposer.md"),
    ("A04", "agents/story-core-author.md"),
    ("A05", "agents/test-deriver.md"),
    ("A06", "evals/assertions.json"),
    ("A07", "evals/evals.json"),
    ("A08", "evals/fixtures/screen_insufficient_definition.json"),
    ("A09", "evals/fixtures/screen_sensitive_fields.json"),
    ("A10", "evals/fixtures/screen_simple_query.json"),
    ("A11", "evals/fixtures/screen_wizard_six_steps.json"),
    ("A12", "evals/trigger-evals.json"),
    ("A13", "judges/analytics-observability.yaml"),
    ("A14", "judges/audit-traceability.yaml"),
    ("A15", "judges/field-contracts.yaml"),
    ("A16", "judges/observations-errors.yaml"),
    ("A17", "judges/screen-decomposition.yaml"),
    ("A18", "judges/security-privacy.yaml"),
    ("A19", "judges/skill-package.yaml"),
    ("A20", "judges/story-core.yaml"),
    ("A21", "judges/test-coverage.yaml"),
    ("A22", "judges/tokens-messages.yaml"),
    ("A23", "manifest.yaml"),
    ("A24", "perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md"),
    ("A25", "perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md"),
    ("A26", "perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md"),
    ("A27", "references/field-contract.md"),
    ("A28", "references/observations-errors-contract.md"),
    ("A29", "references/story-pack-contract.md"),
    ("A30", "schemas/story-pack.schema.json"),
    ("A31", "scripts/detect_pii_telemetry.py"),
    ("A32", "scripts/lf_common.py"),
    ("A33", "scripts/validate_field_coverage.py"),
    ("A34", "scripts/validate_package.py"),
    ("A35", "scripts/validate_security_coverage.py"),
    ("A36", "scripts/validate_story_pack.py"),
    ("A37", "scripts/validate_tokens.py"),
    ("A38", "scripts/validate_traceability.py"),
    ("A39", "perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md"),
    ("A40", "perfiles/PERFIL_STORY_TEST_DERIVER_LF.md"),
    ("A41", "references/test-derivation-contract.md"),
    ("A42", "judges/source-integrity.yaml"),
    ("A43", "references/screen-decomposition-protocol.md"),
    ("A44", "schemas/screen-decomposition.schema.json"),
    ("A45", "references/security-privacy-contract.md"),
    ("A46", "references/audit-traceability-contract.md"),
    ("A47", "references/tokens-messages-contract.md"),
    ("A48", "references/analytics-observability-contract.md"),
    ("A49", "references/accessibility-responsive-contract.md"),
    ("A50", "references/supabase-source-map.md"),
    ("A51", "schemas/task-packet.schema.json"),
    ("A52", "schemas/coverage-report.schema.json"),
    ("A53", "schemas/execution-ledger.schema.json"),
    ("A54", "templates/story-pack.template.json"),
    ("A55", "templates/story-pack.template.md"),
    ("A56", "templates/judge-contract.template.yaml"),
    ("A57", "scripts/calculate_binary_completion.py"),
    ("A58", "judges/github-integrity.yaml"),
    ("A59", "judges/integration-close.yaml"),
    ("A60", "templates/execution-report.template.md"),
    ("A61", "schemas/judge-result.schema.json"),
    ("A62", "SKILL.md"),
]
BY_CODE = dict(ARTIFACTS)

BENCHMARKS = {
    "anthropics/skills": {
        "minimum_stars": 150_000,
        "role": "Claude Skill structure, activation, progressive disclosure and eval iteration",
    },
    "microsoft/vscode": {
        "minimum_stars": 150_000,
        "role": "prerequisites, explicit workflows, stop conditions and verifiable outputs",
    },
    "freeCodeCamp/freeCodeCamp": {
        "minimum_stars": 150_000,
        "role": "deterministic constraints and valid/invalid test cases",
    },
    "Significant-Gravitas/AutoGPT": {
        "minimum_stars": 150_000,
        "role": "state persistence, cycle limits and workspace safety",
    },
}

FENCE = re.compile(r"```(?P<lang>[A-Za-z0-9_+-]*)\n(?P<body>.*?)\n```", re.S)
HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$", re.M)
PATH_REF = re.compile(r"`((?:agents|perfiles|references|schemas|templates|scripts|judges|evals)/[^`]+)`")
PLACEHOLDER = re.compile(r"<[^>]+>|\bTBD\b|\bTODO\b|\.\.\.")
FORBIDDEN_ASSIGNMENT = re.compile(
    r"(?:status|result|estado)\s*[:=]\s*[`\"']?(VALIDATED|APPROVED|VIGENTE|PRODUCTION_READY|PRODUCTION_AUTHORIZED)[`\"']?",
    re.I,
)

@dataclass
class Check:
    name: str
    passed: bool
    evidence: Any
    critical: bool = True

@dataclass
class Report:
    artifact_code: str
    relative_path: str
    sha256: str = ""
    bytes: int = 0
    checks: list[Check] = field(default_factory=list)
    examples: list[dict[str, Any]] = field(default_factory=list)
    benchmark_stars: dict[str, int] = field(default_factory=dict)
    claude_score: float = 0.0
    github_score: float = 0.0
    technical_score: float = 0.0
    final_score: float = 0.0
    result: str = "NOT_VALIDATED"
    findings: list[str] = field(default_factory=list)

    def add(self, name: str, passed: bool, evidence: Any, critical: bool = True) -> None:
        self.checks.append(Check(name, passed, evidence, critical))
        if critical and not passed:
            self.findings.append(f"{name}: {evidence}")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_text(path: Path) -> tuple[bytes, str]:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise ValueError("utf8_bom_detected")
    return data, data.decode("utf-8")


def github_repo_stars(repo: str) -> int:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-deep-audit"},
    )
    token = os.getenv("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    return int(payload["stargazers_count"])


def verify_benchmarks(report: Report) -> None:
    for repo, config in BENCHMARKS.items():
        try:
            stars = github_repo_stars(repo)
            report.benchmark_stars[repo] = stars
            report.add(f"benchmark_{repo}", stars >= config["minimum_stars"], {"stars": stars, **config})
        except Exception as exc:  # network absence is a blocking evidence gap
            report.add(f"benchmark_{repo}", False, f"unavailable:{type(exc).__name__}:{exc}")


def heading_before(text: str, position: int) -> str:
    result = ""
    for match in HEADING.finditer(text, 0, position):
        result = match.group(2).strip()
    return result


def parse_fences(report: Report, text: str) -> list[tuple[str, str, str]]:
    blocks: list[tuple[str, str, str]] = []
    for index, match in enumerate(FENCE.finditer(text), start=1):
        lang = match.group("lang").lower()
        body = match.group("body")
        heading = heading_before(text, match.start())
        blocks.append((heading, lang, body))
        if PLACEHOLDER.search(body):
            report.add(f"fence_{index}_{lang or 'text'}_instructional", True, heading, critical=False)
            continue
        try:
            if lang == "json":
                json.loads(body)
            elif lang in {"yaml", "yml"}:
                if yaml is None:
                    raise RuntimeError("pyyaml_missing")
                yaml.safe_load(body)
            elif lang in {"python", "py"}:
                ast.parse(body)
            elif lang in {"bash", "sh", "shell"}:
                if "curl | sh" in body or "curl|sh" in body:
                    raise ValueError("unsafe_pipe_to_shell")
            report.add(f"fence_{index}_{lang or 'text'}_parse", True, heading, critical=False)
        except Exception as exc:
            report.add(f"fence_{index}_{lang or 'text'}_parse", False, f"{heading}:{exc}")
    return blocks


def parse_document(report: Report, path: Path, text: str) -> Any:
    suffix = path.suffix.lower()
    if suffix == ".json":
        value = json.loads(text)
        report.add("json_parse", True, type(value).__name__)
        if path.name.endswith("schema.json"):
            if jsonschema is None:
                report.add("jsonschema_dependency", False, "jsonschema_missing")
            else:
                jsonschema.Draft7Validator.check_schema(value)
                report.add("json_schema_check", True, value.get("$id") or value.get("title"))
        return value
    if suffix in {".yaml", ".yml"}:
        if yaml is None:
            report.add("yaml_dependency", False, "pyyaml_missing")
            return None
        value = yaml.safe_load(text)
        report.add("yaml_parse", isinstance(value, (dict, list)), type(value).__name__)
        return value
    if suffix == ".py":
        compile(text, str(path), "exec")
        report.add("python_compile", True, sys.version)
        return ast.parse(text)
    if suffix == ".md":
        headings = [match.group(2) for match in HEADING.finditer(text)]
        report.add("markdown_has_headings", bool(headings), headings[:20])
        return parse_fences(report, text)
    report.add("supported_extension", False, suffix)
    return None


def check_references(report: Report, text: str) -> None:
    refs = sorted(set(PATH_REF.findall(text)))
    missing = [ref for ref in refs if not (SKILL_ROOT / ref).exists()]
    report.add("internal_references_resolve", not missing, {"count": len(refs), "missing": missing})


def check_forbidden_assignments(report: Report, text: str) -> None:
    matches = sorted(set(FORBIDDEN_ASSIGNMENT.findall(text)))
    report.add("forbidden_status_assignment", not matches, matches)


def section_presence(text: str, alternatives: Iterable[str]) -> bool:
    lower = text.lower()
    return any(item.lower() in lower for item in alternatives)


def benchmark_scores(report: Report, path: Path, text: str, parsed: Any) -> None:
    suffix = path.suffix.lower()
    claude_checks: list[bool] = []
    github_checks: list[bool] = []

    if suffix == ".md":
        claude_checks = [
            section_presence(text, ["misión", "propósito", "purpose"]),
            section_presence(text, ["activación", "cuándo usar", "activation"]),
            section_presence(text, ["entrada", "inputs"]),
            section_presence(text, ["preflight", "prerrequisitos"]),
            section_presence(text, ["procedimiento", "workflow", "protocolo"]),
            section_presence(text, ["salida", "output", "handoff"]),
            section_presence(text, ["ejemplo", "example"]),
            section_presence(text, ["reparación", "retry", "repair"]),
            section_presence(text, ["bloque", "stop condition", "detener"]),
            section_presence(text, ["evidencia", "evidence"]),
        ]
        github_checks = [
            bool(re.search(r"\b(PASS|READY_FOR_JUDGE|RETURN_TO_WORKER|BLOCKED|FAIL)\b", text)),
            "SHA-256" in text or "sha256" in text.lower(),
            section_presence(text, ["positivo", "positive"]),
            section_presence(text, ["negativo", "negative"]),
            section_presence(text, ["assertion", "constraint"]),
            section_presence(text, ["comando", "command", "python scripts/"]),
            section_presence(text, ["retry_limit", "retry limit", "reintento"]),
            section_presence(text, ["prohib", "forbidden"]),
            section_presence(text, ["source_ref", "fuente"]),
            section_presence(text, ["runtime", "validador", "validator"]),
        ]
    elif suffix in {".yaml", ".yml"} and isinstance(parsed, dict):
        claude_checks = [key in parsed for key in ("scope", "required_inputs", "preflight", "assertions", "output")]
        claude_checks += [
            bool(parsed.get("positive_behavior") or parsed.get("positive_cases") or parsed.get("self_test_command")),
            bool(parsed.get("negative_cases")),
            bool(parsed.get("repair_matrix")),
            bool(parsed.get("block_if")),
            bool(parsed.get("required_evidence")),
        ]
        github_checks = [
            bool(parsed.get("validator_ref") or parsed.get("validators")),
            bool(parsed.get("runtime_command") or parsed.get("self_test_command")),
            bool(parsed.get("assertions")),
            bool(parsed.get("pass_if")),
            bool(parsed.get("block_if")),
            bool(parsed.get("fail_if")),
            bool(parsed.get("repair_matrix")),
            bool(parsed.get("output")),
            bool(parsed.get("prohibitions")),
            int(parsed.get("retry_limit", -1)) == 2,
        ]
    elif suffix == ".json" and isinstance(parsed, (dict, list)):
        blob = text.lower()
        claude_checks = [
            len(text) > 100,
            not bool(PLACEHOLDER.search(text)),
            "expected" in blob or "required" in blob,
            "negative" in blob or "minimum" in blob or "maxitems" in blob,
            "source" in blob or "$id" in blob,
            "evidence" in blob or "description" in blob,
            "result" in blob or "type" in blob,
            "error" in blob or "blocking" in blob or "allof" in blob,
            "version" in blob or "$schema" in blob,
            True,
        ]
        github_checks = [
            "type" in blob,
            "required" in blob,
            "additionalproperties" in blob or isinstance(parsed, list),
            "enum" in blob or "const" in blob or "expected" in blob,
            "pattern" in blob or "source" in blob,
            "minimum" in blob or "minitems" in blob or "negative" in blob,
            "maximum" in blob or "maxitems" in blob or "blocking" in blob,
            "evidence" in blob,
            "result" in blob or "status" in blob,
            True,
        ]
    elif suffix == ".py":
        blob = text.lower()
        claude_checks = [
            bool(ast.get_docstring(ast.parse(text))),
            "argparse" in blob,
            "evidence" in blob,
            "failed" in blob,
            "blocked" in blob or "validationinputerror" in blob,
            "repair" in blob,
            "sha" in blob or "hash" in blob,
            "result" in blob,
            "return" in blob,
            "if __name__" in blob,
        ]
        github_checks = [
            "def " in blob,
            "try:" in blob or "validationinputerror" in blob,
            "json" in blob,
            "argparse" in blob,
            "failed_assertions" in blob or "failed" in blob,
            "evidence" in blob,
            "retry" in blob,
            "main_guard" in blob or "sys.exit" in blob or "raise systemexit" in blob,
            "positive" in blob or "self_test" in blob,
            "negative" in blob or "failure(" in blob,
        ]

    def score(values: list[bool]) -> float:
        if not values:
            return 0.0
        return round(8.0 + 2.0 * (sum(values) / len(values)), 2)

    report.claude_score = score(claude_checks)
    report.github_score = score(github_checks)
    report.add("claude_benchmark_rubric", report.claude_score > 9.5, {"score": report.claude_score, "checks": claude_checks})
    report.add("github_benchmark_rubric", report.github_score > 9.5, {"score": report.github_score, "checks": github_checks})


def extract_named_examples(text: str) -> dict[str, dict[str, Any]]:
    examples: dict[str, dict[str, Any]] = {}
    for match in FENCE.finditer(text):
        if match.group("lang").lower() != "json":
            continue
        heading = heading_before(text, match.start())
        normalized = heading.lower()
        if not ("caso positivo j" in normalized or "caso negativo j" in normalized):
            continue
        examples[heading] = json.loads(match.group("body"))
    return examples


def parse_emitted_json(stdout: str) -> dict[str, Any]:
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    for line in reversed(lines):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError(f"json_result_not_found:{stdout[-500:]}")


def check_expected_checks(payload: dict[str, Any], result: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    expected = payload.get("expected_checks")
    if not isinstance(expected, dict):
        return True, {"declared": False}
    actual = result.get("evidence", {}).get("checks", {})
    mismatches: dict[str, Any] = {}
    for key, wanted in expected.items():
        value = actual.get(key)
        count = len(value) if isinstance(value, (list, dict, tuple, set)) else int(value or 0)
        if wanted == ">0" and count <= 0:
            mismatches[key] = {"expected": wanted, "actual": count}
        elif wanted == 0 and count != 0:
            mismatches[key] = {"expected": wanted, "actual": count}
    return not mismatches, {"declared": True, "mismatches": mismatches, "actual": actual}


def run_a01_examples(report: Report, text: str) -> None:
    examples = extract_named_examples(text)
    expected_names = [f"Caso {polarity} J{judge:02d}" for judge in range(5, 10) for polarity in ("positivo", "negativo")]
    missing = [name for name in expected_names if name not in examples]
    report.add("a01_ten_examples_present", not missing, {"found": sorted(examples), "missing": missing})
    if missing:
        return

    mapping = {
        5: [sys.executable, "scripts/validate_field_coverage.py", "{input}", "--judge", "J05_OBSERVATIONS_ERRORS"],
        6: [sys.executable, "scripts/validate_security_coverage.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        7: [sys.executable, "scripts/validate_traceability.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        8: [sys.executable, "scripts/validate_tokens.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        9: [sys.executable, "scripts/detect_pii_telemetry.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
    }
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_DEEP_AUDIT_RUNNER")
    for name in expected_names:
        judge = int(re.search(r"J(\d+)", name).group(1))
        expected_result = "PASS_WITH_EVIDENCE" if "positivo" in name else "RETURN_TO_WORKER"
        payload = examples[name]
        with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
            json.dump(payload, handle, ensure_ascii=False)
            handle.write("\n")
            temp_path = Path(handle.name)
        command = [part.format(input=str(temp_path)) for part in mapping[judge]]
        proc = subprocess.run(command, cwd=SKILL_ROOT, env=env, text=True, capture_output=True, timeout=60)
        try:
            emitted = parse_emitted_json(proc.stdout)
            actual_result = emitted.get("result")
            expected_ok, expected_detail = check_expected_checks(payload, emitted)
            passed = actual_result == expected_result and expected_ok
            detail = {
                "heading": name,
                "command": command,
                "exit_code": proc.returncode,
                "expected_result": expected_result,
                "actual_result": actual_result,
                "assertions_total": emitted.get("assertions_total"),
                "assertions_passed": emitted.get("assertions_passed"),
                "failed_assertions": emitted.get("failed_assertions"),
                "blocking_assertions": emitted.get("blocking_assertions"),
                "expected_checks": expected_detail,
                "input_sha256": emitted.get("input_sha256"),
                "output_sha256": emitted.get("output_sha256"),
                "evidence_sha256": emitted.get("evidence_sha256"),
            }
        except Exception as exc:
            passed = False
            detail = {"heading": name, "command": command, "exit_code": proc.returncode, "stdout": proc.stdout[-1000:], "stderr": proc.stderr[-1000:], "error": str(exc)}
        finally:
            temp_path.unlink(missing_ok=True)
        report.examples.append(detail)
        report.add(f"example_{name.replace(' ', '_').lower()}", passed, detail)


def run_python_self_test(report: Report, path: Path, text: str) -> None:
    if "--self-test" not in text:
        report.add("python_self_test", True, "not_declared", critical=False)
        return
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_DEEP_AUDIT_RUNNER")
    proc = subprocess.run([sys.executable, str(path), "--self-test"], cwd=SKILL_ROOT, env=env, text=True, capture_output=True, timeout=120)
    report.add("python_self_test", proc.returncode == 0, {"exit_code": proc.returncode, "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:]})


def technical_score(report: Report) -> None:
    critical = [check for check in report.checks if check.critical]
    ratio = sum(check.passed for check in critical) / len(critical) if critical else 0.0
    report.technical_score = round(8.0 + 2.0 * ratio, 2)
    report.final_score = min(report.claude_score, report.github_score, report.technical_score)
    report.result = "PASS_WITH_EVIDENCE" if not report.findings and report.final_score > 9.5 else "RETURN_TO_WORKER"


def audit(code: str, verify_external: bool = True) -> Report:
    if code not in BY_CODE:
        raise SystemExit(f"unknown artifact code: {code}")
    relative = BY_CODE[code]
    path = SKILL_ROOT / relative
    report = Report(code, relative)
    report.add("file_exists", path.is_file(), str(path))
    if not path.is_file():
        technical_score(report)
        return report
    try:
        data, text = read_text(path)
    except Exception as exc:
        report.add("utf8_decode", False, str(exc))
        technical_score(report)
        return report
    report.sha256 = sha256_bytes(data)
    report.bytes = len(data)
    report.add("utf8_without_bom", True, True)
    report.add("lf_line_endings", b"\r\n" not in data and b"\r" not in data, {"crlf": data.count(b"\r\n"), "cr": data.count(b"\r")})
    report.add("final_newline", data.endswith(b"\n"), data[-10:].decode("utf-8", "replace"))
    report.add("non_empty", bool(text.strip()), len(text))
    try:
        parsed = parse_document(report, path, text)
    except Exception as exc:
        parsed = None
        report.add("document_parse", False, f"{type(exc).__name__}:{exc}")
    check_references(report, text)
    check_forbidden_assignments(report, text)
    benchmark_scores(report, path, text, parsed)
    if verify_external:
        verify_benchmarks(report)
    if code == "A01":
        run_a01_examples(report, text)
    if path.suffix.lower() == ".py":
        run_python_self_test(report, path, text)
    technical_score(report)
    return report


def write_report(report: Report, directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    payload = asdict(report)
    (directory / f"{report.artifact_code}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        f"# {report.artifact_code} — {report.relative_path}", "",
        f"- Resultado: **{report.result}**",
        f"- Claude: **{report.claude_score:.2f}**",
        f"- GitHub: **{report.github_score:.2f}**",
        f"- Técnica: **{report.technical_score:.2f}**",
        f"- Final MIN: **{report.final_score:.2f}**",
        f"- SHA-256: `{report.sha256}`", "",
        "## Hallazgos", "",
    ]
    lines.extend([f"- {item}" for item in report.findings] or ["- Ninguno."])
    lines += ["", "## Checks", ""]
    lines.extend(f"- {'PASS' if c.passed else 'FAIL'} — `{c.name}`: `{json.dumps(c.evidence, ensure_ascii=False)[:500]}`" for c in report.checks)
    (directory / f"{report.artifact_code}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--artifact", choices=sorted(BY_CODE), required=True)
    cli.add_argument("--report-dir", type=Path, default=ROOT / "audit-results")
    cli.add_argument("--skip-external", action="store_true")
    args = cli.parse_args()
    report = audit(args.artifact, verify_external=not args.skip_external)
    write_report(report, args.report_dir)
    print(json.dumps({
        "artifact": report.artifact_code,
        "path": report.relative_path,
        "result": report.result,
        "claude_score": report.claude_score,
        "github_score": report.github_score,
        "technical_score": report.technical_score,
        "final_score": report.final_score,
        "findings": report.findings,
        "sha256": report.sha256,
    }, ensure_ascii=False, sort_keys=True))
    return 0 if report.result == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
