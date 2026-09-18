#!/usr/bin/env python3
"""Authenticated exact-head readback for the current E.16 GitHub Actions carrier."""
from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
ALLOWED_EVENTS = {"push", "pull_request", "workflow_dispatch"}
ALLOWED_STATUSES = {"requested", "waiting", "pending", "queued", "in_progress", "completed"}
FAILED_CONCLUSIONS = {"failure", "cancelled", "timed_out", "action_required", "startup_failure", "stale"}
MAX_RESPONSE_BYTES = 2 * 1024 * 1024


def fail(code: str, message: str) -> None:
    raise ValueError(f"{code}: {message}")


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def positive_int(value: object, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        fail("FAIL_E16_ACTIONS_API_SHAPE", f"{field} must be positive integer")
    return value


def request_json(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "pr93-e16-current-carrier-readback",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(MAX_RESPONSE_BYTES + 1)
        if len(data) > MAX_RESPONSE_BYTES:
            fail("FAIL_E16_ACTIONS_API_RESPONSE_TOO_LARGE", "response exceeds 2 MiB")
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
    return value


def run_url(repository: str, run_id: int, api_base: str) -> str:
    owner, sep, repo = repository.partition("/")
    if not sep or not owner or not repo or "/" in repo:
        fail("FAIL_E16_REPOSITORY_INVALID", "repository must be owner/name")
    base = urllib.parse.urlsplit(api_base.rstrip("/"))
    if not base.scheme or not base.netloc or base.username is not None or base.password is not None:
        fail("FAIL_E16_ACTIONS_API_BASE_INVALID", "api-base invalid")
    path = f"{base.path.rstrip('/')}/repos/{owner}/{repo}/actions/runs/{run_id}"
    return urllib.parse.urlunsplit((base.scheme, base.netloc, path, "", ""))


def compact_run(run: dict[str, Any]) -> dict[str, Any]:
    return {
        key: run.get(key)
        for key in (
            "id",
            "name",
            "event",
            "head_sha",
            "head_branch",
            "status",
            "conclusion",
            "run_number",
            "run_attempt",
            "created_at",
            "updated_at",
            "html_url",
            "workflow_id",
            "path",
        )
    }


def validate_current_run(
    run: dict[str, Any],
    *,
    run_id: int,
    workflow_name: str,
    event_name: str,
    head_sha: str,
) -> dict[str, Any]:
    observed_id = positive_int(run.get("id"), "id")
    if observed_id != run_id:
        fail("FAIL_E16_ACTIONS_RUN_ID_MISMATCH", f"expected={run_id} observed={observed_id}")
    if run.get("name") != workflow_name:
        fail(
            "FAIL_E16_ACTIONS_WORKFLOW_MISMATCH",
            f"expected={workflow_name!r} observed={run.get('name')!r}",
        )
    if run.get("event") != event_name:
        fail(
            "FAIL_E16_ACTIONS_EVENT_MISMATCH",
            f"expected={event_name!r} observed={run.get('event')!r}",
        )
    if run.get("head_sha") != head_sha:
        fail(
            "FAIL_E16_ACTIONS_HEAD_MISMATCH",
            f"expected={head_sha} observed={run.get('head_sha')}",
        )
    positive_int(run.get("run_number"), "run_number")
    positive_int(run.get("run_attempt", 1), "run_attempt")
    status = run.get("status")
    conclusion = run.get("conclusion")
    if status not in ALLOWED_STATUSES:
        fail("FAIL_E16_ACTIONS_RUN_STATUS_INVALID", f"status={status}")
    if conclusion in FAILED_CONCLUSIONS:
        fail("FAIL_E16_ACTIONS_RUN_FAILED", f"conclusion={conclusion}")
    if status == "completed" and conclusion != "success":
        fail("FAIL_E16_ACTIONS_RUN_NOT_SUCCESS", f"conclusion={conclusion}")
    return compact_run(run)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--head-sha", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--api-base", default="https://api.github.com")
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        fail("FAIL_E16_GITHUB_TOKEN_MISSING", "GITHUB_TOKEN is required")
    if not isinstance(args.repository, str) or not args.repository:
        fail("FAIL_E16_REPOSITORY_INVALID", "repository is required")
    if not isinstance(args.head_sha, str) or SHA_RE.fullmatch(args.head_sha) is None:
        fail("FAIL_E16_HEAD_SHA_INVALID", "head SHA invalid")

    workflow_name = (os.environ.get("GITHUB_WORKFLOW") or "").strip()
    if not workflow_name:
        fail("FAIL_E16_WORKFLOW_IDENTITY_MISSING", "GITHUB_WORKFLOW is required")
    event_name = (os.environ.get("GITHUB_EVENT_NAME") or "").strip()
    if event_name not in ALLOWED_EVENTS:
        fail("FAIL_E16_EVENT_IDENTITY_INVALID", f"unsupported event={event_name!r}")
    raw_run_id = (os.environ.get("GITHUB_RUN_ID") or "").strip()
    if not raw_run_id.isdigit() or int(raw_run_id) <= 0:
        fail("FAIL_E16_RUN_ID_INVALID", "GITHUB_RUN_ID must be a positive integer")
    run_id = int(raw_run_id)

    payload = request_json(run_url(args.repository, run_id, args.api_base), token)
    current = validate_current_run(
        payload,
        run_id=run_id,
        workflow_name=workflow_name,
        event_name=event_name,
        head_sha=args.head_sha,
    )

    pending = current["status"] != "completed"
    record = {
        "schema_version": "pr93-e16-actions-inventory/v3",
        "declaration_kind": "MEASURED_AUTHENTICATED_API",
        "repository": args.repository,
        "head_sha": args.head_sha,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "applicability_authority": "CI_FAST_DEEP_LANE_ROUTER",
        "carrier_scope": "CURRENT_CARRIER_ONLY",
        "cross_carrier_wait_required": False,
        "current_run": current,
        "current_run_visible": True,
        "current_run_pending": pending,
        "current_run_terminal_success": current["status"] == "completed" and current["conclusion"] == "success",
        "runtime_or_merge_claimed": False,
    }
    output = args.output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with output.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(canonical_json(record))
    except FileExistsError:
        fail("FAIL_E16_ACTIONS_INVENTORY_EXISTS", f"output already exists: {output}")

    print(
        "E16_ACTIONS_CURRENT_RUN="
        f"{current['name']}|{current['event']}|{current['id']}|{current['status']}|{current['conclusion']}"
    )
    print("PASS_E16_CURRENT_CARRIER_ACTIONS_READBACK=1/1")
    print(f"E16_ACTIONS_INVENTORY={output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(str(exc), file=os.sys.stderr)
        raise SystemExit(2)
