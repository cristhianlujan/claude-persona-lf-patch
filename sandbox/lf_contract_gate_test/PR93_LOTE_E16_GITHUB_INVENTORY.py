#!/usr/bin/env python3
"""Authenticated, paginated GitHub Actions inventory for PR93 E.16 CA-N93."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_MATRIX = (
    ("lf-contract-check", "push"),
    ("lf-contract-check", "pull_request"),
    ("Validate LF Packs", "push"),
    ("Validate LF Packs", "pull_request"),
)
ALLOWED_STATUSES = {"requested", "waiting", "pending", "queued", "in_progress", "completed"}
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
FAILED_CONCLUSIONS = {
    "failure",
    "cancelled",
    "timed_out",
    "action_required",
    "startup_failure",
    "stale",
}


def fail(code: str, message: str) -> None:
    raise ValueError(f"{code}: {message}")


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def parse_link_header(value: str | None) -> dict[str, str]:
    links: dict[str, str] = {}
    if not value:
        return links
    for part in value.split(","):
        section = part.strip().split(";")
        if len(section) < 2:
            continue
        url = section[0].strip()
        if not (url.startswith("<") and url.endswith(">")):
            continue
        for parameter in section[1:]:
            key, _, raw = parameter.strip().partition("=")
            if key == "rel":
                links[raw.strip('"')] = url[1:-1]
    return links


def request_json(url: str, token: str) -> tuple[dict[str, Any], dict[str, str]]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "pr93-e16-actions-inventory",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(MAX_RESPONSE_BYTES + 1)
            headers = {key.lower(): value for key, value in response.headers.items()}
        if len(data) > MAX_RESPONSE_BYTES:
            fail("FAIL_E16_ACTIONS_API_RESPONSE_TOO_LARGE", "response exceeds 16 MiB")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        fail("FAIL_E16_ACTIONS_API_HTTP", f"HTTP {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        fail("FAIL_E16_ACTIONS_API_NETWORK", str(exc.reason))
    try:
        value = json.loads(data.decode("utf-8", "strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail("FAIL_E16_ACTIONS_API_JSON", str(exc))
    if not isinstance(value, dict):
        fail("FAIL_E16_ACTIONS_API_SHAPE", "response must be a JSON object")
    return value, headers


def validate_page_url(
    url: str,
    *,
    expected_origin: tuple[str, str],
    expected_path: str,
    head_sha: str,
) -> None:
    parsed = urllib.parse.urlsplit(url)
    if parsed.username is not None or parsed.password is not None:
        fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination URL must not contain credentials")
    if (parsed.scheme, parsed.netloc) != expected_origin:
        fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination changed API origin")
    if parsed.path != expected_path:
        fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination changed endpoint path")
    query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
    if query.get("head_sha") != [head_sha] or query.get("per_page") != ["100"]:
        fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination changed canonical filters")
    page_values = query.get("page")
    if page_values is None or len(page_values) != 1 or not page_values[0].isdigit():
        fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination page is invalid")


def fetch_runs(
    repository: str,
    head_sha: str,
    token: str,
    api_base: str,
) -> tuple[list[dict[str, Any]], int, int]:
    owner, separator, repo = repository.partition("/")
    if not separator or not owner or not repo or "/" in repo:
        fail("FAIL_E16_REPOSITORY_INVALID", "repository must be owner/name")
    base = urllib.parse.urlsplit(api_base.rstrip("/"))
    if not base.scheme or not base.netloc or base.username is not None or base.password is not None:
        fail("FAIL_E16_ACTIONS_API_BASE_INVALID", "api-base must be an absolute URL without credentials")
    expected_origin = (base.scheme, base.netloc)
    expected_path = f"{base.path.rstrip('/')}/repos/{owner}/{repo}/actions/runs"
    query = urllib.parse.urlencode({"head_sha": head_sha, "per_page": 100, "page": 1})
    next_url: str | None = urllib.parse.urlunsplit(
        (base.scheme, base.netloc, expected_path, query, "")
    )
    runs: list[dict[str, Any]] = []
    pages = 0
    visited: set[str] = set()
    reported_total: int | None = None
    while next_url is not None:
        validate_page_url(
            next_url,
            expected_origin=expected_origin,
            expected_path=expected_path,
            head_sha=head_sha,
        )
        if next_url in visited:
            fail("FAIL_E16_ACTIONS_API_PAGINATION", "pagination loop detected")
        visited.add(next_url)
        pages += 1
        if pages > 100:
            fail("FAIL_E16_ACTIONS_API_PAGINATION", "page limit exceeded")
        payload, headers = request_json(next_url, token)
        total_count = payload.get("total_count")
        if not isinstance(total_count, int) or total_count < 0:
            fail("FAIL_E16_ACTIONS_API_SHAPE", "total_count must be a non-negative integer")
        if reported_total is None:
            reported_total = total_count
        elif total_count != reported_total:
            fail("FAIL_E16_ACTIONS_API_PAGINATION", "total_count changed between pages")
        page_runs = payload.get("workflow_runs")
        if not isinstance(page_runs, list):
            fail("FAIL_E16_ACTIONS_API_SHAPE", "workflow_runs must be a list")
        for item in page_runs:
            if not isinstance(item, dict):
                fail("FAIL_E16_ACTIONS_API_SHAPE", "every workflow run must be an object")
            runs.append(item)
        next_url = parse_link_header(headers.get("link")).get("next")
    if reported_total is None:
        fail("FAIL_E16_ACTIONS_API_SHAPE", "no API page was fetched")
    if len(runs) != reported_total:
        fail(
            "FAIL_E16_ACTIONS_API_PAGINATION",
            f"observed {len(runs)} runs but API reported total_count={reported_total}",
        )
    return runs, pages, reported_total


def positive_int(value: object, *, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        fail("FAIL_E16_ACTIONS_API_SHAPE", f"{field} must be a positive integer")
    return value


def compact_run(run: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": positive_int(run.get("id"), field="id"),
        "name": run.get("name"),
        "event": run.get("event"),
        "head_sha": run.get("head_sha"),
        "head_branch": run.get("head_branch"),
        "status": run.get("status"),
        "conclusion": run.get("conclusion"),
        "run_number": positive_int(run.get("run_number"), field="run_number"),
        "run_attempt": positive_int(run.get("run_attempt", 1), field="run_attempt"),
        "created_at": run.get("created_at"),
        "updated_at": run.get("updated_at"),
        "html_url": run.get("html_url"),
        "workflow_id": run.get("workflow_id"),
        "path": run.get("path"),
    }


def select_inventory(runs: list[dict[str, Any]], head_sha: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    exact = [run for run in runs if run.get("head_sha") == head_sha]
    selected: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    for workflow, event in EXPECTED_MATRIX:
        candidates = [
            run for run in exact
            if run.get("name") == workflow and run.get("event") == event
        ]
        if not candidates:
            missing.append({"workflow": workflow, "event": event})
            continue
        latest = max(
            candidates,
            key=lambda run: (
                positive_int(run.get("run_number"), field="run_number"),
                positive_int(run.get("run_attempt", 1), field="run_attempt"),
                positive_int(run.get("id"), field="id"),
            ),
        )
        compact = compact_run(latest)
        conclusion = compact["conclusion"]
        status = compact["status"]
        if status not in ALLOWED_STATUSES:
            fail(
                "FAIL_E16_ACTIONS_RUN_STATUS_INVALID",
                f"{workflow}/{event} status={status}",
            )
        if conclusion in FAILED_CONCLUSIONS:
            fail(
                "FAIL_E16_ACTIONS_RUN_FAILED",
                f"{workflow}/{event} latest run conclusion={conclusion}",
            )
        if status == "completed" and conclusion != "success":
            fail(
                "FAIL_E16_ACTIONS_RUN_NOT_SUCCESS",
                f"{workflow}/{event} completed with conclusion={conclusion}",
            )
        selected.append(compact)
    return selected, missing


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--head-sha", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--api-base", default="https://api.github.com")
    parser.add_argument("--matrix-wait-seconds", type=float, default=30.0)
    parser.add_argument("--poll-interval-seconds", type=float, default=2.0)
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        fail("FAIL_E16_GITHUB_TOKEN_MISSING", "GITHUB_TOKEN is required")
    if not isinstance(args.repository, str) or not args.repository:
        fail("FAIL_E16_REPOSITORY_INVALID", "repository is required")
    if not isinstance(args.head_sha, str) or SHA_RE.fullmatch(args.head_sha) is None:
        fail("FAIL_E16_HEAD_SHA_INVALID", "head SHA must be 40 lowercase hexadecimal characters")

    if args.matrix_wait_seconds < 0:
        fail("FAIL_E16_ACTIONS_WAIT_INVALID", "matrix-wait-seconds must be non-negative")
    if args.poll_interval_seconds <= 0:
        fail("FAIL_E16_ACTIONS_WAIT_INVALID", "poll-interval-seconds must be positive")

    deadline = time.monotonic() + args.matrix_wait_seconds
    poll_attempts = 0
    while True:
        poll_attempts += 1
        runs, pages, reported_total = fetch_runs(args.repository, args.head_sha, token, args.api_base)
        wrong_head_ids = [run.get("id") for run in runs if run.get("head_sha") != args.head_sha]
        if wrong_head_ids:
            fail(
                "FAIL_E16_ACTIONS_API_FILTER_MISMATCH",
                f"API returned runs for another head: {wrong_head_ids}",
            )
        selected, missing = select_inventory(runs, args.head_sha)
        if not missing:
            break
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            fail("FAIL_E16_ACTIONS_MATRIX_INCOMPLETE", canonical_json(missing).strip())
        time.sleep(min(args.poll_interval_seconds, remaining))
    all_matching_runs = sorted(
        (compact_run(run) for run in runs),
        key=lambda run: (run["run_number"], run["run_attempt"], run["id"]),
    )
    selected_pending = [run for run in selected if run["status"] != "completed"]
    selected_latest_failure = any(
        run["conclusion"] in FAILED_CONCLUSIONS
        or (run["status"] == "completed" and run["conclusion"] != "success")
        for run in selected
    )
    matrix_complete = len(selected) == len(EXPECTED_MATRIX) and not missing

    record = {
        "schema_version": "pr93-e16-actions-inventory/v1",
        "declaration_kind": "MEASURED_AUTHENTICATED_API",
        "repository": args.repository,
        "head_sha": args.head_sha,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "api": {
            "authenticated": True,
            "pagination_complete": True,
            "pages_fetched": pages,
            "reported_total_count": reported_total,
            "matching_runs_observed": sum(run.get("head_sha") == args.head_sha for run in runs),
            "poll_attempts": poll_attempts,
        },
        "expected_matrix": [
            {"workflow": workflow, "event": event}
            for workflow, event in EXPECTED_MATRIX
        ],
        "all_matching_runs": all_matching_runs,
        "selected_runs": selected,
        "matrix_complete": matrix_complete,
        "selected_latest_known_failure_present": selected_latest_failure,
        "selected_pending_present": bool(selected_pending),
        "selected_pending_count": len(selected_pending),
        "selected_pending_runs": selected_pending,
        "historical_failure_present": any(
            run.get("conclusion") in FAILED_CONCLUSIONS for run in runs
        ),
        "runtime_or_merge_claimed": False,
    }
    output = args.output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(canonical_json(record))
    except FileExistsError:
        fail("FAIL_E16_ACTIONS_INVENTORY_EXISTS", f"output already exists: {output}")
    if selected_pending:
        print(f"NOTICE_E16_ACTIONS_PENDING={len(selected_pending)}")
    for run in selected:
        print(
            "E16_ACTIONS_RUN="
            f"{run['name']}|{run['event']}|{run['id']}|{run['status']}|{run['conclusion']}"
        )
    print(
        "PASS_E16_CANONICAL_ACTIONS_INVENTORY="
        f"{len(selected)}/{len(EXPECTED_MATRIX)}"
    )
    print(f"E16_ACTIONS_INVENTORY={output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
