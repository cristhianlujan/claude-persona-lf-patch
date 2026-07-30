#!/usr/bin/env python3
"""Type-aware static and benchmark audit for A09 sensitive-fields fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "skills" / "creating-integral-user-stories" / "evals" / "fixtures" / "screen_sensitive_fields.json"
REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")
PII = {"PII_INDIRECT", "PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}


def stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-a09-audit"})
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
    actors = data.get("actors", [])
    fields = data.get("fields", [])
    actions = data.get("actions", [])
    chain = data.get("field_chain_eval", {})
    expected = data.get("expected", {})
    external = {repo: stars(repo) for repo in REPOS}
    field_codes = [item.get("code") for item in fields if isinstance(item, dict)]
    checks = {
        "fixture_identity": data.get("fixture_id") == "FIX-SENSITIVE-FIELDS",
        "purpose_specific": isinstance(data.get("purpose"), str) and len(data["purpose"]) >= 80,
        "source_versioned_and_hashed": isinstance(source.get("version"), str) and isinstance(source.get("sha256"), str) and len(source["sha256"]) == 64,
        "actors_have_permissions_and_tenant": isinstance(actors, list) and len(actors) >= 2 and all(isinstance(item, dict) and item.get("permissions") and item.get("tenant_key") for item in actors),
        "five_unique_fields": len(fields) == 5 and len(set(field_codes)) == 5,
        "all_fields_classified": all(isinstance(item, dict) and item.get("pii_classification") in PII for item in fields),
        "pii_telemetry_denied": all(item.get("analytics_allowed") is False and item.get("logs_allowed") is False for item in fields if isinstance(item, dict)),
        "source_refs_present": all(isinstance(item.get("source_ref"), str) and item["source_ref"] for item in fields + actions if isinstance(item, dict)),
        "mutations_controlled": len(actions) >= 2 and all(item.get("mutation") is True and item.get("permission") and item.get("audit_required") is True and item.get("idempotency_required") is True for item in actions if isinstance(item, dict)),
        "validator_local_scope_explicit": chain.get("case_scope") == "VALIDATOR_LOCAL_SUITE" and str(chain.get("case_source", "")).startswith("scripts/validate_field_coverage.py#"),
        "four_required_executions": isinstance(chain.get("required_executions"), list) and len(chain["required_executions"]) == 4,
        "negative_must_be_rejected": chain.get("negative_must_be_rejected") is True,
        "expected_counts_consistent": expected.get("pii_fields") == 5 and expected.get("pii_fields_analytics_allowed") == 0 and expected.get("editable_fields_without_audit") == 0 and expected.get("logs_with_unmasked_pii") == 0,
        "design_sources_exact": data.get("design_sources") == list(REPOS),
        "all_repos_over_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": "A09",
        "relative_path": "evals/fixtures/screen_sensitive_fields.json",
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
    (args.report_dir / "A09.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.report_dir / "A09.md").write_text(f"# A09\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": "A09", "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
