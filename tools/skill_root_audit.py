#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
PATH = SKILL / "SKILL.md"


def sections(text: str) -> dict[int, str]:
    matches = list(re.finditer(r"^## (\d+)\.\s+(.+?)\s*$", text, re.M))
    out: dict[int, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        out[int(match.group(1))] = text[match.end():end]
    return out


def findings(text: str) -> list[str]:
    found: list[str] = []
    secs = sections(text)
    required_sections = set(range(1, 18))
    if required_sections - set(secs):
        found.append("sections_1_17")
    if "version: v0.6" not in text or "status: CANDIDATO_READ_ONLY" not in text or "runtime: disabled" not in text:
        found.append("frontmatter")
    if not all(token in secs.get(1, "") for token in ("Story Pack A–Q", "J01", "J13", "GitHub", "Supabase")):
        found.append("mission_chain")
    if "NEEDS_SOURCE_CONTEXT" not in secs.get(2, ""):
        found.append("activation_block")
    if not all(token in secs.get(3, "") for token in ("source_snapshot", "task_packet", "pending_decisions", "contrato GitHub")):
        found.append("inputs")
    if not all(token in secs.get(4, "") for token in ("source_hash_missing", "judge_independence_broken", "github_target_branch_mismatch")):
        found.append("preflight")
    judges = [f"J{i:02d}" for i in range(1, 14)]
    if not all(judge in secs.get(5, "") for judge in judges):
        found.append("j01_j13")
    validators = [
        "validate_source_integrity.py", "validate_screen_decomposition.py", "validate_story_pack.py",
        "validate_field_coverage.py", "validate_security_coverage.py", "validate_traceability.py",
        "validate_tokens.py", "detect_pii_telemetry.py", "validate_test_coverage.py",
        "validate_package.py", "validate_github_integrity.py", "calculate_binary_completion.py",
    ]
    if not all((SKILL / "scripts" / validator).is_file() for validator in validators):
        found.append("validators_exist")
    if not all(f"{letter} " in secs.get(7, "") for letter in "ABCDEFGHIJKLMNOPQ"):
        found.append("story_pack_a_q")
    if "context_budget" not in secs.get(8, ""):
        found.append("context_budget")
    if not all(token in secs.get(9, "") for token in ("anthropics/skills", "Significant-Gravitas/AutoGPT", "freeCodeCamp/freeCodeCamp", "microsoft/vscode", "más de 150.000 estrellas")):
        found.append("benchmark_dual")
    if re.search(r"\b\d{6,}\s+estrellas", secs.get(9, ""), re.I):
        found.append("temporal_star_counts")
    if "NOTA_FINAL = MIN" not in secs.get(10, ""):
        found.append("score_formula")
    if not all(token in secs.get(11, "") for token in ("caso positivo", "caso negativo", "BLOCKED", "FAIL", "falsos PASS")):
        found.append("test_matrix")
    persistence = secs.get(12, "")
    if not all(token in persistence for token in ("fix/deep-audit-a01-a62", "PR 57", "nueva versión Supabase", "SHA GitHub–Supabase")):
        found.append("persistence")
    restrictions = secs.get(14, "")
    if not all(token in restrictions for token in (
        "base_branch: feat/integral-story-creator-r8-forward", "branch: fix/deep-audit-a01-a62",
        "pr_number: 57", "pr_draft: true", "main_write: false", "merge: false",
        "release: false", "tag: false", "production: false", "runtime_enabled: false",
    )):
        found.append("restrictions")
    closure = secs.get(15, "")
    if not all(token in closure for token in ("62/62 PASS_WITH_EVIDENCE", "GitHub = Supabase", "DEEP_REAUDIT_IN_PROGRESS", "R8_AUDIT_COMPLETE_WITH_DUAL_BENCHMARK_EVIDENCE")):
        found.append("closure")
    controls = secs.get(16, "")
    if not all(token in controls for token in ("### Positivo", "### Negativo", "### Bloqueado", "fuente sin hash", "rama incorrecta", "ausencia de prueba negativa", "100%")):
        found.append("controls")
    if "Los contratos LF y la fuente operativa prevalecen" not in secs.get(17, ""):
        found.append("authority")
    return sorted(set(found))


def mutate(text: str, case_name: str) -> str:
    if case_name == "source_hash_removed":
        return text.replace("source_hash_missing = true", "source_hash_check_removed = true", 1)
    if case_name == "wrong_branch":
        return text.replace("branch: fix/deep-audit-a01-a62", "branch: main", 1).replace("escribir solo en `fix/deep-audit-a01-a62`", "escribir en `main`", 1)
    if case_name == "negative_case_removed":
        start = text.find("### Negativo", text.find("## 16."))
        end = text.find("### Bloqueado", start)
        return text[:start] + text[end:] if start >= 0 and end > start else text
    if case_name == "false_close":
        return text.replace("Mientras una condición esté pendiente, el estado es\n`DEEP_REAUDIT_IN_PROGRESS`.", "El estado es `R8_AUDIT_COMPLETE_WITH_DUAL_BENCHMARK_EVIDENCE` aunque existan pendientes.", 1)
    raise ValueError(case_name)


def static(report_dir: Path) -> int:
    raw = PATH.read_bytes()
    text = raw.decode("utf-8")
    errors = findings(text)
    checks = {
        "root_contract": not errors,
        "utf8": True,
        "final_newline": raw.endswith(b"\n"),
        "manifest_exists": (SKILL / "manifest.yaml").is_file(),
        "benchmark_snapshot_exists": (ROOT / "tools" / "benchmark-snapshot.json").is_file(),
        "schemas_exist": all((SKILL / "schemas" / name).is_file() for name in ("story-pack.schema.json", "judge-result.schema.json", "execution-ledger.schema.json")),
        "no_self_approval": "no aprueba su propio trabajo" in text and "autoaprobar" in text,
    }
    score = 10.0 if all(checks.values()) else round(8 + 2 * sum(checks.values()) / len(checks), 2)
    result = "PASS_WITH_EVIDENCE" if score > 9.5 and all(checks.values()) else "RETURN_TO_WORKER"
    out = {
        "artifact_code": "A62", "relative_path": "SKILL.md", "sha256": hashlib.sha256(raw).hexdigest(),
        "checks": checks, "contract_findings": errors, "claude_score": score, "github_score": score,
        "technical_score": score, "final_score": score, "result": result,
        "findings": errors + [key for key, value in checks.items() if not value],
    }
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "A62.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return 0 if result == "PASS_WITH_EVIDENCE" else 1


def runtime() -> int:
    raw = PATH.read_bytes()
    text = raw.decode("utf-8")
    rows = []
    base_findings = findings(text)
    rows.append({
        "case": "positive", "expected": "PASS_WITH_EVIDENCE",
        "actual": "PASS_WITH_EVIDENCE" if not base_findings else "RETURN_TO_WORKER",
        "findings": base_findings, "passed": not base_findings,
    })
    for case_name in ("source_hash_removed", "wrong_branch", "negative_case_removed", "false_close"):
        case_findings = findings(mutate(text, case_name))
        actual = "PASS_WITH_EVIDENCE" if not case_findings else "RETURN_TO_WORKER"
        rows.append({
            "case": case_name, "expected": "RETURN_TO_WORKER", "actual": actual,
            "findings": case_findings, "passed": actual == "RETURN_TO_WORKER",
        })
    out = {"artifact": "A62", "passed": all(row["passed"] for row in rows), "cases": rows, "sha256": hashlib.sha256(raw).hexdigest()}
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return 0 if out["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("static", "runtime"), required=True)
    parser.add_argument("--report-dir", type=Path, default=ROOT / "audit-results")
    args = parser.parse_args()
    return static(args.report_dir) if args.mode == "static" else runtime()


if __name__ == "__main__":
    raise SystemExit(main())
