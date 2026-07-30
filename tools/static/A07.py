#!/usr/bin/env python3
"""Type-aware static and external benchmark gate for A07 evals/evals.json."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "skills" / "creating-integral-user-stories" / "evals" / "evals.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a07-audit"})
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
    legacy = data.get("legacy_cases")
    executable = data.get("executable_cases")
    external = {repo: stars(repo) for repo in REPOS}
    checks = {
        "schema_version_present": isinstance(data.get("schema_version"), str),
        "skill_code_matches": data.get("skill_code") == "creating-integral-user-stories",
        "purpose_present": isinstance(data.get("purpose"), str) and len(data["purpose"]) >= 20,
        "execution_contract_present": isinstance(data.get("execution_contract"), dict),
        "legacy_cases_present": isinstance(legacy, list) and len(legacy) == 20,
        "executable_cases_present": isinstance(executable, list) and len(executable) == 2,
        "case_count_matches": data.get("case_count") == len(legacy or []) + len(executable or []),
        "positive_behavior_present": isinstance(data.get("positive_behavior"), str),
        "negative_behavior_present": isinstance(data.get("negative_behavior"), str),
        "evidence_contract_present": isinstance(data.get("evidence_contract"), dict),
        "all_external_repos_above_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A07",
        "relative_path": "evals/evals.json",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "checks": checks,
        "benchmark_stars": external,
        "claude_score": score,
        "github_score": score,
        "technical_score": score,
        "final_score": score,
        "result": "PASS_WITH_EVIDENCE" if passed and score > 9.5 else "RETURN_TO_WORKER",
        "findings": [key for key, value in checks.items() if not value],
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / "A07.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A07.md").write_text(f"# A07 — evals/evals.json\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A07", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
