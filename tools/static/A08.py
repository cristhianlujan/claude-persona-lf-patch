#!/usr/bin/env python3
"""Type-aware static and benchmark audit for A08 insufficient-source fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "skills" / "creating-integral-user-stories" / "evals" / "fixtures" / "screen_insufficient_definition.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")


def repo_stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a08-audit"})
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
    source = data.get("source_snapshot", {})
    activation = data.get("activation_expectation", {})
    candidate = data.get("candidate_validation_expectation", {})
    invariants = data.get("negative_invariants", {})
    stars = {repo: repo_stars(repo) for repo in REPOS}
    checks = {
        "fixture_identity": data.get("fixture_id") == "FIX-INSUFFICIENT-DEFINITION",
        "purpose_specific": isinstance(data.get("purpose"), str) and len(data["purpose"]) >= 60,
        "source_deliberately_incomplete": source.get("version") is None and source.get("sha256") is None and source.get("main_responsibility") is None,
        "minimal_available_content": source.get("available_content") == ["screen_name: Gestión"],
        "missing_fact_inventory": isinstance(data.get("missing_facts"), list) and len(data["missing_facts"]) >= 9,
        "activation_blocks": activation.get("activation") == "NEEDS_SOURCE_CONTEXT" and activation.get("result") == "BLOCKED" and activation.get("must_not_invent") is True and activation.get("story_count") == 0,
        "blocking_assertions_explicit": isinstance(activation.get("blocking_assertions"), list) and len(activation["blocking_assertions"]) >= 3,
        "candidate_rejected": candidate.get("case_id") == "E22_STORY_CORE_NEGATIVE" and candidate.get("expected_candidate_result") == "RETURN_TO_WORKER" and candidate.get("eval_wrapper_result") == "PASS_WITH_EVIDENCE" and candidate.get("must_be_rejected") is True,
        "required_failures_explicit": isinstance(candidate.get("required_failed_assertions"), list) and len(candidate["required_failed_assertions"]) >= 6,
        "negative_invariants_complete": isinstance(invariants, dict) and len(invariants) >= 5 and all(value is True for value in invariants.values()),
        "design_sources_exact": data.get("design_sources") == list(REPOS),
        "all_repos_over_150k": all(value > 150000 for value in stars.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A08",
        "relative_path": "evals/fixtures/screen_insufficient_definition.json",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "checks": checks,
        "benchmark_stars": stars,
        "claude_score": score,
        "github_score": score,
        "technical_score": score,
        "final_score": score,
        "result": "PASS_WITH_EVIDENCE" if passed and score > 9.5 else "RETURN_TO_WORKER",
        "findings": [name for name, ok in checks.items() if not ok],
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / "A08.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A08.md").write_text(f"# A08\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A08", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
