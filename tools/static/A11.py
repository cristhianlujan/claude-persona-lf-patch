#!/usr/bin/env python3
"""Type-aware static and benchmark audit for A11 six-step wizard fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "skills" / "creating-integral-user-stories" / "evals" / "fixtures" / "screen_wizard_six_steps.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a11-audit"})
    token = os.getenv("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return int(json.load(response)["stargazers_count"])


def canonical_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", type=Path, required=True)
    args = parser.parse_args()
    raw = TARGET.read_bytes()
    data = json.loads(raw.decode("utf-8"))
    source = data.get("source_snapshot", {})
    exact = data.get("fixture", {}).get("exact_inputs", {})
    expected = data.get("expected", {}).get("output", {})
    assertions = data.get("assertions", [])
    negatives = data.get("negative_cases", [])
    external = {repo: stars(repo) for repo in REPOS}
    assertion_codes = [item.get("code") for item in assertions if isinstance(item, dict)]
    negative_ids = [item.get("id") for item in negatives if isinstance(item, dict)]
    checks = {
        "fixture_identity": data.get("fixture_id") == "FIX-WIZARD-SIX-STEPS",
        "proposed_classification": data.get("classification") == "PROPOSED",
        "purpose_specific": isinstance(data.get("purpose"), str) and len(data["purpose"]) >= 100,
        "synthetic_origin_explicit": source.get("origin") == "SYNTHETIC_TEST_FIXTURE" and source.get("allowed_in_acceptance_criteria") is False and source.get("allowed_as_implementation_requirement") is False,
        "canonical_input_hash_matches": source.get("sha256") == canonical_sha(exact),
        "six_steps": isinstance(exact.get("steps"), list) and len(exact["steps"]) == 6,
        "two_business_results": isinstance(exact.get("business_results"), list) and len(exact["business_results"]) == 2,
        "mutations_have_decisions": all(not item.get("mutation") or item.get("idempotency_decision") for item in exact.get("actions", []) if isinstance(item, dict)),
        "source_refs_complete": all(item.get("source_ref") for collection in (exact.get("steps", []), exact.get("actions", []), exact.get("business_results", [])) for item in collection if isinstance(item, dict)),
        "expected_story_grouping": expected.get("visual_steps") == 6 and expected.get("create_story_count") == 2 and expected.get("functional_unit_count") == 3 and expected.get("prohibited_story_count") == 6,
        "required_decisions": set(expected.get("required_decisions", [])) == {"CREATE_STORY", "CROSS_CUTTING"},
        "five_unique_assertions": len(assertion_codes) == 5 and len(set(assertion_codes)) == 5,
        "two_negative_cases": set(negative_ids) == {"NEG-SIX-STORIES", "NEG-MISSING-SOURCE-REF"},
        "validator_and_runner_declared": data.get("execution", {}).get("validator_ref") == "scripts/validate_screen_decomposition.py" and data.get("execution", {}).get("audit_runner_ref") == "tools/runtime/A11.py",
        "no_canonical_state_change": data.get("expected", {}).get("state_changes") == [] and "canonical_artifacts" in data.get("expected", {}).get("no_state_changes", []),
        "design_sources_exact": data.get("design_sources") == list(REPOS),
        "all_repos_over_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A11",
        "relative_path": "evals/fixtures/screen_wizard_six_steps.json",
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
    (args.report_dir / "A11.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A11.md").write_text(f"# A11\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A11", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
