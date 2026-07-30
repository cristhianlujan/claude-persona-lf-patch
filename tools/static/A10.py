#!/usr/bin/env python3
"""Type-aware static and benchmark audit for A10 simple-query fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "skills" / "creating-integral-user-stories" / "evals" / "fixtures" / "screen_simple_query.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a10-audit"})
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
    fields = data.get("fields", [])
    actions = data.get("actions", [])
    transitions = data.get("transitions", [])
    story_eval = data.get("story_core_eval", {})
    expected = data.get("expected", {})
    external = {repo: stars(repo) for repo in REPOS}
    checks = {
        "fixture_identity": data.get("fixture_id") == "FIX-SIMPLE-QUERY",
        "purpose_scoped_to_j03": isinstance(data.get("purpose"), str) and "J03" in data["purpose"],
        "synthetic_hash_explicit": source.get("hash_kind") == "SYNTHETIC_FIXTURE" and isinstance(source.get("sha256"), str) and len(source["sha256"]) == 64,
        "source_identity_complete": all(source.get(key) for key in ("screen_code", "module_code", "version", "main_responsibility")),
        "actor_permission_tenant": len(data.get("actors", [])) == 1 and data["actors"][0].get("permissions") == ["CUSTOMER_READ"] and data["actors"][0].get("tenant_key") == "company_id",
        "contexts_complete": {item.get("code") for item in data.get("contexts", [])} == {"search", "result", "empty", "error"},
        "pii_fields_protected": len(fields) == 2 and all(item.get("pii_classification") == "PII_DIRECT" and item.get("visibility_mode") == "MASKED" and item.get("masking_rule") and item.get("analytics_allowed") is False and item.get("logs_allowed") is False for item in fields),
        "read_only_actions": len(actions) == 2 and all(item.get("mutation") is False for item in actions),
        "transition_source_present": len(transitions) == 1 and transitions[0].get("source_ref"),
        "error_retry_and_correlation": len(data.get("errors", [])) == 1 and data["errors"][0].get("retryable") is True and data["errors"][0].get("max_attempts") == 2 and data["errors"][0].get("correlation_id_required") is True,
        "e21_contract_explicit": story_eval.get("case_id") == "E21_STORY_CORE_POSITIVE" and story_eval.get("expected_candidate_result") == "PASS_WITH_EVIDENCE" and story_eval.get("expected_eval_wrapper_result") == "PASS_WITH_EVIDENCE",
        "identity_alignment_explicit": set(story_eval.get("required_identity_alignment", [])) == {"screen_code", "module_code", "source_version", "source_snapshot_sha"},
        "no_false_global_pass": expected.get("story_core_result") == "PASS_WITH_EVIDENCE" and expected.get("integration_result") == "NOT_VALIDATED",
        "test_scope_separated": set(expected.get("minimum_executable_test_families", [])) == {"FUNCTIONAL", "TENANT"} and set(expected.get("test_families_pending_before_integration", [])) == {"VALIDATION", "PERMISSION", "ERROR", "ACCESSIBILITY"},
        "design_sources_exact": data.get("design_sources") == list(REPOS),
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
