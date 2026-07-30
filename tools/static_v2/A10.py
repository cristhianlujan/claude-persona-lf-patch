#!/usr/bin/env python3
"""A10 v2 static audit: derive alignment requirements from E21 itself."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
TARGET = SKILL / "evals" / "fixtures" / "screen_simple_query.json"
REGISTRY = SKILL / "evals" / "evals.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")
REQUIRED_FAMILIES = {"FUNCTIONAL", "VALIDATION", "PERMISSION", "TENANT", "ERROR", "ACCESSIBILITY"}


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a10-v2-audit"})
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
    fixture = json.loads(raw.decode("utf-8"))
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    case_id = fixture["story_core_eval"]["case_id"]
    case = next((item for item in registry.get("executable_cases", []) if item.get("id") == case_id), None)
    candidate = case.get("candidate_story_pack") if isinstance(case, dict) else None
    identity = candidate.get("identity", {}) if isinstance(candidate, dict) else {}
    candidate_families = {item.get("family") for item in candidate.get("tests", []) if isinstance(item, dict) and item.get("family")} if isinstance(candidate, dict) else set()
    source = fixture.get("source_snapshot", {})
    expected = fixture.get("expected", {})
    fields = fixture.get("fields", [])
    external = {repo: stars(repo) for repo in REPOS}
    checks = {
        "fixture_identity": fixture.get("fixture_id") == "FIX-SIMPLE-QUERY",
        "e21_exists": isinstance(case, dict) and isinstance(candidate, dict),
        "source_identity_matches_e21": source.get("screen_code") == identity.get("screen_code") and source.get("module_code") == identity.get("module_code") and source.get("version") == identity.get("source_version") and source.get("sha256") == identity.get("source_snapshot_sha"),
        "synthetic_hash_explicit": source.get("hash_kind") == "SYNTHETIC_FIXTURE_ALIGNED_TO_E21" and isinstance(source.get("sha256"), str) and len(source["sha256"]) == 64,
        "pii_fields_protected": len(fields) >= 1 and all(item.get("pii_classification") == "PII_DIRECT" and item.get("visibility_mode") == "MASKED" and item.get("masking_rule") and item.get("analytics_allowed") is False and item.get("logs_allowed") is False for item in fields if isinstance(item, dict)),
        "read_only_actions": all(item.get("mutation") is False for item in fixture.get("actions", []) if isinstance(item, dict)),
        "story_core_not_global_pass": expected.get("story_core_result") == "PASS_WITH_EVIDENCE" and expected.get("integration_result") == "NOT_VALIDATED",
        "minimum_families_match_e21": set(expected.get("minimum_executable_test_families", [])) == candidate_families,
        "pending_families_exact": set(expected.get("test_families_pending_before_integration", [])) == REQUIRED_FAMILIES - candidate_families,
        "design_sources_exact": fixture.get("design_sources") == list(REPOS),
        "all_repos_over_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A10",
        "relative_path": "evals/fixtures/screen_simple_query.json",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "checks": checks,
        "candidate_identity": identity,
        "candidate_test_families": sorted(candidate_families),
        "benchmark_stars": external,
        "claude_score": score,
        "github_score": score,
        "technical_score": score,
        "final_score": score,
        "result": "PASS_WITH_EVIDENCE" if passed and score > 9.5 else "RETURN_TO_WORKER",
        "findings": [name for name, ok in checks.items() if not ok],
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / "A10.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A10.md").write_text(f"# A10\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A10", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
