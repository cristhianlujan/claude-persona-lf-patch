#!/usr/bin/env python3
"""Type-aware static and benchmark audit for A12 trigger evaluations."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
TARGET = SKILL / "evals" / "trigger-evals.json"
ASSERTIONS = SKILL / "evals" / "assertions.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")
EXPECTED_IDS = {"E16", "E17", "E18", "E19", "T05", "T06", "T07", "T08"}


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a12-audit"})
    token = os.getenv("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return int(json.load(response)["stargazers_count"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", type=Path, required=True)
    args = parser.parse_args()
    raw = TARGET.read_bytes()
    data = json.loads(raw.decode("utf-8"))
    assertion_registry = json.loads(ASSERTIONS.read_text(encoding="utf-8"))
    known_assertions = {item.get("id") for item in assertion_registry.get("assertions", []) if isinstance(item, dict)}
    cases = data.get("cases", [])
    ids = [item.get("id") for item in cases if isinstance(item, dict)]
    refs = {code for item in cases if isinstance(item, dict) for code in item.get("critical_assertions", [])}
    runtime = data.get("deterministic_runtime", {})
    models = data.get("model_matrix", [])
    evidence = data.get("evidence_contract", {})
    external = {repo: stars(repo) for repo in REPOS}
    checks = {
        "schema_version_v05": data.get("schema_version") == "v0.5",
        "skill_code_matches": data.get("skill_code") == "creating-integral-user-stories",
        "eight_unique_cases": data.get("case_count") == 8 and len(ids) == 8 and len(set(ids)) == 8 and set(ids) == EXPECTED_IDS,
        "activation_values_complete": set(data.get("activation_values", [])) == {"ACTIVATE", "DO_NOT_ACTIVATE", "NEEDS_SOURCE_CONTEXT"},
        "deterministic_runtime_available": runtime.get("status") == "AVAILABLE" and runtime.get("source_of_truth_for_canonical_audit") is True and set(runtime.get("required_case_ids", [])) == EXPECTED_IDS,
        "three_model_families_nonblocking": {item.get("model_family") for item in models if isinstance(item, dict)} == {"HAIKU", "SONNET", "OPUS"} and all(item.get("affects_canonical_pass") is False and set(item.get("required_case_ids", [])) == EXPECTED_IDS for item in models if isinstance(item, dict)),
        "evidence_contract_complete": set(evidence.get("required_fields", [])) >= {"executor_identity", "judge_version", "command", "started_at", "completed_at", "exit_code", "assertions_total", "assertions_passed", "failed_assertions", "blocking_assertions", "input_sha256", "output_sha256", "evidence_sha256"},
        "vacuous_pass_forbidden": evidence.get("vacuous_pass_allowed") is False,
        "all_case_assertions_known": refs.issubset(known_assertions),
        "two_assertions_per_case": all(len(item.get("assertions", [])) == 2 and len(item.get("critical_assertions", [])) == 2 for item in cases if isinstance(item, dict)),
        "case_evidence_paths_present": all(isinstance(item.get("evidence_path"), str) and item.get("evidence_path") for item in cases if isinstance(item, dict)),
        "no_state_mutation_expected": all(item.get("expected", {}).get("state_changes") == [] and "canonical_artifacts" in item.get("expected", {}).get("no_state_changes", []) for item in cases if isinstance(item, dict)),
        "design_sources_exact": data.get("design_sources") == list(REPOS),
        "all_repos_over_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A12",
        "relative_path": "evals/trigger-evals.json",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "checks": checks,
        "benchmark_stars": external,
        "claude_score": score,
        "github_score": score,
        "technical_score": score,
        "final_score": score,
        "result": "PASS_WITH_EVIDENCE" if passed and score > 9.5 else "RETURN_TO_WORKER",
        "findings": [name for name, ok in checks.items() if not ok],
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / "A12.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A12.md").write_text(f"# A12\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A12", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
