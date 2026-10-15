#!/usr/bin/env python3
"""Read-only evidence report for PASE observation windows.

Live mode uses only `gh api` GET requests. Fixture mode is exercised by the
companion unittest and does not contact GitHub.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any, Mapping


CHECK_ALIASES = {
    "pase": "pase",
    "pase-merge-gate": "pase-merge-gate",
    "pase / migration_source_parity": "pase-migration-source-parity",
    "pase-migration-source-parity": "pase-migration-source-parity",
}
MIGRATION_PREFIX = "supabase/migrations/"


def parse_time(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise ValueError("timestamps must include a timezone")
    return parsed.astimezone(timezone.utc)


def canonical_check(value: str) -> str:
    normalized = re.sub(r"\s+", " ", value.strip().lower())
    if normalized not in CHECK_ALIASES:
        raise ValueError(f"unsupported check: {value}")
    return CHECK_ALIASES[normalized]


def check_matches(name: str, check: str) -> bool:
    value = re.sub(r"[^a-z0-9]+", "-", str(name).lower()).strip("-")
    if check == "pase":
        return value in {"pase", "lf-independent-change-admission", "lf-independent-change-admission-pase"}
    if check == "pase-merge-gate":
        return "pase-merge-gate" in value
    return "pase" in value and "migration-source-parity" in value


def _parse_optional_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return parse_time(value)
    except (ValueError, TypeError):
        return None


def analyze_window(
    *,
    check: str,
    since: str,
    pulls: list[Mapping[str, Any]],
    check_runs_by_pr: Mapping[str, list[Mapping[str, Any]]],
    files_by_pr: Mapping[str, list[str]],
    failure_paths_by_run: Mapping[str, list[str]] | None = None,
    changed_after_failure_by_run: Mapping[str, list[str]] | None = None,
    now: str | None = None,
) -> dict[str, Any]:
    selected_check = canonical_check(check)
    start = parse_time(since)
    current = parse_time(now) if now else datetime.now(timezone.utc)
    failure_paths_by_run = failure_paths_by_run or {}
    changed_after_failure_by_run = changed_after_failure_by_run or {}
    reports: list[dict[str, Any]] = []
    false_block_candidates: list[dict[str, Any]] = []
    unresolved_failure_evidence: list[dict[str, Any]] = []

    for pull in pulls:
        number = int(pull["number"])
        key = str(number)
        qualifying = []
        for run in check_runs_by_pr.get(key, []):
            run_name = run.get("name") or run.get("check_name") or run.get("workflow_name") or ""
            observed = _parse_optional_time(run.get("started_at") or run.get("created_at"))
            if check_matches(str(run_name), selected_check) and observed and observed >= start:
                qualifying.append(run)
        if not qualifying:
            continue
        qualifying.sort(key=lambda row: _parse_optional_time(row.get("started_at") or row.get("created_at")) or start)
        latest = qualifying[-1]
        conclusion = latest.get("conclusion") or ("in_progress" if latest.get("status") != "completed" else "unknown")
        files = sorted(set(files_by_pr.get(key, [])))
        has_migration = any(path.startswith(MIGRATION_PREFIX) for path in files)
        row = {
            "pr": number,
            "title": pull.get("title", ""),
            "state": pull.get("state", "unknown"),
            "merged": bool(pull.get("merged_at")),
            "head_sha": latest.get("head_sha") or pull.get("head_sha"),
            "check_run_id": str(latest.get("id", "")),
            "conclusion": str(conclusion).lower(),
            "attempts": [
                {
                    "check_run_id": str(run.get("id", "")),
                    "conclusion": str(run.get("conclusion") or "in_progress").lower(),
                    "started_at": run.get("started_at") or run.get("created_at"),
                }
                for run in qualifying
            ],
            "with_migration": has_migration,
        }
        reports.append(row)

        if pull.get("merged_at"):
            merged_at = _parse_optional_time(pull.get("merged_at"))
            for failed_run in qualifying:
                if str(failed_run.get("conclusion") or "").lower() != "failure":
                    continue
                run_id = str(failed_run.get("id", ""))
                failure_paths = set(failure_paths_by_run.get(run_id, []))
                changed_after = set(changed_after_failure_by_run.get(run_id, []))
                failed_at = _parse_optional_time(failed_run.get("completed_at") or failed_run.get("started_at"))
                if not failure_paths or not merged_at or not failed_at:
                    unresolved_failure_evidence.append({
                        "pr": number,
                        "check_run_id": run_id,
                        "reason": "missing failure path annotations or comparable timestamps",
                    })
                elif merged_at >= failed_at and not (failure_paths & changed_after):
                    false_block_candidates.append({
                        "pr": number,
                        "check_run_id": run_id,
                        "failure_paths": sorted(failure_paths),
                        "changed_after_failure": sorted(changed_after),
                        "candidate_reason": "merged after failure without a later change to annotated failure paths",
                    })

    reports.sort(key=lambda row: row["pr"])
    with_migration = sum(1 for row in reports if row["with_migration"])
    without_migration = len(reports) - with_migration
    elapsed_hours = max(0.0, (current - start).total_seconds() / 3600)
    thresholds = {
        "elapsed_hours": round(elapsed_hours, 2),
        "at_least_24_hours": elapsed_hours >= 24,
        "total_prs": len(reports),
        "at_least_30_prs": len(reports) >= 30,
        "with_migration": with_migration,
        "at_least_5_with_migration": with_migration >= 5,
        "without_migration": without_migration,
        "at_least_5_without_migration": without_migration >= 5,
        "false_block_candidates": len(false_block_candidates),
        "zero_false_block_candidates": len(false_block_candidates) == 0,
        "unresolved_failure_evidence": len(unresolved_failure_evidence),
        "all_failure_paths_reviewed": len(unresolved_failure_evidence) == 0,
    }
    thresholds["window_ready"] = all(
        value for key, value in thresholds.items()
        if key.startswith("at_least_") or key.startswith("all_") or key == "zero_false_block_candidates"
    )
    return {
        "check": selected_check,
        "since": start.isoformat(),
        "thresholds": thresholds,
        "pull_requests": reports,
        "false_block_candidates": false_block_candidates,
        "unresolved_failure_evidence": unresolved_failure_evidence,
    }


def gh_json(repo: str, endpoint: str) -> Any:
    completed = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", f"repos/{repo}/{endpoint}"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"gh api failed: {completed.stderr.strip()}")
    return json.loads(completed.stdout)


def flatten_pages(value: Any, collection_key: str | None = None) -> list[Any]:
    if not isinstance(value, list):
        pages = [value]
    else:
        pages = value
    flattened: list[Any] = []
    for page in pages:
        if collection_key and isinstance(page, Mapping):
            rows = page.get(collection_key, [])
            if isinstance(rows, list):
                flattened.extend(rows)
        elif isinstance(page, list):
            flattened.extend(page)
        else:
            flattened.append(page)
    return flattened


def collect_live(repo: str, check: str, since: str) -> dict[str, Any]:
    pulls = flatten_pages(gh_json(repo, "pulls?state=all&sort=updated&direction=desc&per_page=100"))
    since_dt = parse_time(since)
    relevant = [p for p in pulls if (_parse_optional_time(p.get("updated_at")) or datetime.min.replace(tzinfo=timezone.utc)) >= since_dt]
    runs_by_pr: dict[str, list[Mapping[str, Any]]] = {}
    files_by_pr: dict[str, list[str]] = {}
    failure_paths: dict[str, list[str]] = {}
    later_changes: dict[str, list[str]] = {}

    for pull in relevant:
        number = str(pull["number"])
        sha = pull.get("head", {}).get("sha")
        if not sha:
            continue
        commits = flatten_pages(gh_json(repo, f"pulls/{number}/commits?per_page=100"))
        commit_shas = sorted({row.get("sha") for row in commits if isinstance(row, Mapping) and row.get("sha")} | {sha})
        gathered: dict[str, Mapping[str, Any]] = {}
        for commit_sha in commit_shas:
            raw_runs = flatten_pages(gh_json(repo, f"commits/{commit_sha}/check-runs?per_page=100"), "check_runs")
            for row in raw_runs:
                if isinstance(row, Mapping) and row.get("id") is not None:
                    gathered[str(row["id"])] = row
        runs_by_pr[number] = list(gathered.values())
        files = flatten_pages(gh_json(repo, f"pulls/{number}/files?per_page=100"))
        files_by_pr[number] = [row.get("filename", "") for row in files if isinstance(row, Mapping)]
        for run in runs_by_pr[number]:
            name = run.get("name") or ""
            run_when = _parse_optional_time(run.get("started_at") or run.get("created_at"))
            if not check_matches(name, canonical_check(check)) or not run_when or run_when < since_dt or run.get("conclusion") != "failure":
                continue
            run_id = str(run.get("id", ""))
            annotations = flatten_pages(gh_json(repo, f"check-runs/{run_id}/annotations?per_page=100"))
            failure_paths[run_id] = sorted({item.get("path", "") for item in annotations if isinstance(item, Mapping) and item.get("path")})
            failed_sha = run.get("head_sha")
            if failed_sha and failed_sha != sha and pull.get("merged_at"):
                comparison = gh_json(repo, f"compare/{failed_sha}...{sha}")
                data = comparison[-1] if isinstance(comparison, list) and comparison else comparison
                later_changes[run_id] = sorted({item.get("filename", "") for item in data.get("files", []) if item.get("filename")})

    normalized_pulls = [{
        "number": p["number"], "title": p.get("title", ""), "state": p.get("state", "unknown"),
        "merged_at": p.get("merged_at"), "head_sha": p.get("head", {}).get("sha"),
    } for p in relevant]
    return analyze_window(
        check=check, since=since, pulls=normalized_pulls,
        check_runs_by_pr=runs_by_pr, files_by_pr=files_by_pr,
        failure_paths_by_run=failure_paths,
        changed_after_failure_by_run=later_changes,
    )


def render_markdown(report: Mapping[str, Any]) -> str:
    th = report["thresholds"]
    lines = [
        f"# Observation window: {report['check']}", "",
        f"Since: `{report['since']}`", "",
        f"Window ready: **{th['window_ready']}**", "",
        f"Elapsed: {th['elapsed_hours']} h | PRs: {th['total_prs']} | migration: {th['with_migration']} | no migration: {th['without_migration']} | false-block candidates: {th['false_block_candidates']}", "",
        "| PR | Check conclusion | Migration | State |",
        "|---:|---|---|---|",
    ]
    for row in report["pull_requests"]:
        lines.append(f"| #{row['pr']} | `{row['conclusion']}` | {'yes' if row['with_migration'] else 'no'} | {row['state']} |")
    lines.extend(["", "False-block candidates:"])
    if report["false_block_candidates"]:
        lines.extend(f"- #{row['pr']} run `{row['check_run_id']}`: {', '.join(row['failure_paths'])}" for row in report["false_block_candidates"])
    else:
        lines.append("- None found from the available path annotations and PR diffs.")
    if report["unresolved_failure_evidence"]:
        lines.extend(["", "Unresolved failed-run evidence:"])
        lines.extend(f"- #{row['pr']} run `{row['check_run_id']}`: {row['reason']}" for row in report["unresolved_failure_evidence"])
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--check", required=True, help="PASE, pase-merge-gate, or PASE / MIGRATION_SOURCE_PARITY")
    parser.add_argument("--since", required=True, help="ISO-8601 timestamp with timezone")
    parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
    parser.add_argument("--output")
    args = parser.parse_args(argv)
    report = collect_live(args.repo, args.check, args.since)
    output = json.dumps(report, indent=2) if args.format == "json" else render_markdown(report)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(output)
            if not output.endswith("\n"):
                handle.write("\n")
    else:
        sys.stdout.write(output + ("" if output.endswith("\n") else "\n"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
