"""Fail-closed classifier for the non-migration Merge Train status route.

The status is published only for a complete, migration-free file list and an
unchanged pull-request head. API failures never produce the required status.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

API = "https://api.github.com"
MIGRATION_PREFIX = "supabase/migrations/"
MAX_FILES = 3000
PAGE_SIZE = 100
STATUS_CONTEXT = "lf-merge-train/verified"
STATUS_DESCRIPTION = "no migrations; train not required"


@dataclass(frozen=True)
class Classification:
    requires_train: bool
    reason: str


def classify_files(files: list[dict[str, Any]], *, pagination_complete: bool) -> Classification:
    """Classify REST file records. Unknown or capped input requires the Train."""
    if not pagination_complete:
        return Classification(True, "file list incomplete")
    if len(files) >= MAX_FILES:
        return Classification(True, "GitHub file list reached 3000-file limit")
    for item in files:
        if not isinstance(item, dict):
            return Classification(True, "malformed file record")
        filename = item.get("filename")
        previous = item.get("previous_filename")
        if not isinstance(filename, str) or (previous is not None and not isinstance(previous, str)):
            return Classification(True, "file path missing or malformed")
        # Status is deliberately ignored: additions, edits, deletions and renames
        # all route through the Train if either side is under the migration tree.
        if filename.startswith(MIGRATION_PREFIX) or (previous or "").startswith(MIGRATION_PREFIX):
            return Classification(True, "migration path changed")
    return Classification(False, "no migration paths changed")


def should_publish_success(
    files: list[dict[str, Any]], *, pagination_complete: bool,
    expected_head: str, observed_head: str,
) -> tuple[bool, str]:
    classification = classify_files(files, pagination_complete=pagination_complete)
    if classification.requires_train:
        return False, classification.reason
    if not expected_head or expected_head != observed_head:
        return False, "pull-request head changed during verification"
    return True, "verified exact head has no migration paths"


class ApiError(RuntimeError):
    pass


def api_request(path: str, token: str, *, method: str = "GET", body: dict[str, Any] | None = None) -> Any:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        f"{API}{path}", data=data, method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            **({"Content-Type": "application/json"} if data is not None else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as exc:
        raise ApiError(str(exc)) from exc


def pull_files(repo: str, number: int, token: str) -> tuple[list[dict[str, Any]], bool]:
    files: list[dict[str, Any]] = []
    for page in range(1, 31):
        try:
            result = api_request(
                f"/repos/{repo}/pulls/{number}/files?per_page={PAGE_SIZE}&page={page}", token
            )
        except ApiError:
            return files, False
        if not isinstance(result, list):
            return files, False
        files.extend(result)
        if len(files) >= MAX_FILES:
            return files, True
        if len(result) < PAGE_SIZE:
            return files, True
    return files, False


def parse_pr_numbers(event_path: str | None, dispatch_input: str | None) -> tuple[list[int], dict[int, str]]:
    expected_heads: dict[int, str] = {}
    if event_path:
        try:
            event = json.loads(Path(event_path).read_text(encoding="utf-8"))
            pr = event.get("pull_request")
            if isinstance(pr, dict):
                number = int(pr["number"])
                expected_heads[number] = str(pr["head"]["sha"])
                return [number], expected_heads
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
            pass
    raw = dispatch_input or ""
    parts = [part for part in re.split(r"[,\s]+", raw.strip()) if part]
    if not parts or any(not part.isdecimal() or int(part) <= 0 for part in parts):
        raise ValueError("pr_number must contain one or more positive PR numbers")
    numbers = list(dict.fromkeys(int(part) for part in parts))
    return numbers, expected_heads


def write_summary(message: str) -> None:
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(message.rstrip() + "\n")
    print(message)


def process_pull(repo: str, number: int, event_head: str | None, read_token: str, app_token: str) -> bool:
    prefix = f"PR #{number}: "
    try:
        pull = api_request(f"/repos/{repo}/pulls/{number}", read_token)
    except ApiError as exc:
        write_summary(prefix + f"BLOCKED; could not read PR ({exc}); no status published.")
        return False
    if not isinstance(pull, dict) or pull.get("state") != "open" or pull.get("base", {}).get("ref") != "main":
        write_summary(prefix + "not an open PR against main; no status published.")
        return True
    initial_head = pull.get("head", {}).get("sha")
    if not isinstance(initial_head, str) or (event_head and event_head != initial_head):
        write_summary(prefix + "event head is stale or missing; no status published.")
        return True

    files, complete = pull_files(repo, number, read_token)
    classification = classify_files(files, pagination_complete=complete)
    if classification.requires_train:
        write_summary(prefix + f"{classification.reason}; requires Train; no {STATUS_CONTEXT} status published.")
        return True

    try:
        latest = api_request(f"/repos/{repo}/pulls/{number}", read_token)
    except ApiError as exc:
        write_summary(prefix + f"BLOCKED; could not re-read head ({exc}); no status published.")
        return False
    latest_head = latest.get("head", {}).get("sha") if isinstance(latest, dict) else None
    if latest_head != initial_head or latest.get("base", {}).get("ref") != "main":
        write_summary(prefix + "head/base changed during verification; no status published.")
        return True

    try:
        api_request(
            f"/repos/{repo}/statuses/{initial_head}", app_token, method="POST",
            body={"state": "success", "context": STATUS_CONTEXT, "description": STATUS_DESCRIPTION},
        )
    except ApiError as exc:
        write_summary(prefix + f"status publication failed ({exc}); continuing with the next PR.")
        return False
    write_summary(prefix + f"SUCCESS {STATUS_CONTEXT} on {initial_head}: {STATUS_DESCRIPTION}.")
    return True


def main() -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    read_token = os.environ.get("GH_READ_TOKEN", "")
    app_token = os.environ.get("APP_TOKEN", "")
    if not repo or not read_token or not app_token:
        print("BLOCKED: repository or token missing; no status published.", file=sys.stderr)
        return 1
    numbers, event_heads = parse_pr_numbers(
        os.environ.get("GITHUB_EVENT_PATH"), os.environ.get("PR_NUMBER_INPUT")
    )
    failed_numbers: list[int] = []
    for number in numbers:
        if not process_pull(repo, number, event_heads.get(number), read_token, app_token):
            failed_numbers.append(number)
    if failed_numbers:
        write_summary("Backfill incomplete; failed PRs: " + ", ".join(f"#{number}" for number in failed_numbers) + ".")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
