#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import lf_contract_check_self_change_admission_v1 as guard  # noqa: E402

API_URL = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"
EXECUTION_ID_RE = re.compile(r"^[A-Za-z0-9._:/-]{1,200}$")


class CarrierError(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str = "") -> None:
    raise CarrierError(code, detail)


def _event() -> Mapping[str, Any]:
    path = os.environ.get("GITHUB_EVENT_PATH", "").strip()
    if not path:
        _fail("BLOCK_SELF_CHANGE_EVENT_MISSING")
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        _fail("BLOCK_SELF_CHANGE_EVENT_INVALID", type(exc).__name__)
    if not isinstance(data, Mapping):
        _fail("BLOCK_SELF_CHANGE_EVENT_INVALID")
    return data


def _token() -> str:
    token = os.environ.get("GH_TOKEN", "").strip() or os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        _fail("BLOCK_SELF_CHANGE_GITHUB_TOKEN_MISSING")
    return token


def _api(path: str) -> Any:
    req = urllib.request.Request(
        f"{API_URL}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {_token()}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "lf-independent-change-admission-v1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:300]
        _fail("BLOCK_SELF_CHANGE_GITHUB_API", f"{exc.code}:{path}:{body}")
    except Exception as exc:
        _fail("BLOCK_SELF_CHANGE_GITHUB_API", f"{type(exc).__name__}:{path}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        _fail("BLOCK_SELF_CHANGE_GITHUB_JSON", path)


def _repo_and_pr(event: Mapping[str, Any]) -> tuple[str, int]:
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if not repo:
        repo_obj = event.get("repository")
        if isinstance(repo_obj, Mapping):
            repo = str(repo_obj.get("full_name") or "")
    pr = event.get("pull_request")
    if not isinstance(pr, Mapping):
        _fail("BLOCK_SELF_CHANGE_PR_EVENT")
    number = pr.get("number") or event.get("number")
    if not isinstance(number, int) or number < 1:
        _fail("BLOCK_SELF_CHANGE_PR_NUMBER")
    return repo, number


def _pr_context() -> dict[str, Any]:
    event = _event()
    repo, number = _repo_and_pr(event)
    pr = _api(f"/repos/{urllib.parse.quote(repo, safe='/')}/pulls/{number}")
    if not isinstance(pr, Mapping):
        _fail("BLOCK_SELF_CHANGE_PR_READBACK")
    event_pr = event["pull_request"]
    event_head = str((event_pr.get("head") or {}).get("sha") or "")
    event_base = str((event_pr.get("base") or {}).get("sha") or "")
    observed_head = str((pr.get("head") or {}).get("sha") or "")
    observed_base = str((pr.get("base") or {}).get("sha") or "")
    if event_head != observed_head:
        _fail("BLOCK_SELF_CHANGE_HEAD_MISMATCH", f"event={event_head} observed={observed_head}")
    if event_base != observed_base:
        _fail("BLOCK_SELF_CHANGE_BASE_EVENT_MISMATCH", f"event={event_base} observed={observed_base}")

    changed: list[str] = []
    page = 1
    while True:
        rows = _api(
            f"/repos/{urllib.parse.quote(repo, safe='/')}/pulls/{number}/files"
            f"?per_page=100&page={page}"
        )
        if not isinstance(rows, list):
            _fail("BLOCK_SELF_CHANGE_CHANGED_FILES_API")
        for row in rows:
            if not isinstance(row, Mapping) or not isinstance(row.get("filename"), str):
                _fail("BLOCK_SELF_CHANGE_CHANGED_FILES_API")
            changed.append(str(row["filename"]))
        if len(rows) < 100:
            break
        page += 1
        if page > 30:
            _fail("BLOCK_SELF_CHANGE_CHANGED_FILES_LIMIT")

    expected_count = pr.get("changed_files")
    if isinstance(expected_count, int) and expected_count != len(changed):
        _fail(
            "BLOCK_SELF_CHANGE_CHANGED_FILES_INCOMPLETE",
            f"api={len(changed)} expected={expected_count}",
        )
    head_repo_obj = (pr.get("head") or {}).get("repo")
    head_repo = str(head_repo_obj.get("full_name") or "") if isinstance(head_repo_obj, Mapping) else ""
    if not head_repo:
        _fail("BLOCK_SELF_CHANGE_HEAD_REPOSITORY_MISSING")
    return {
        "event": event,
        "repository": repo,
        "pr_number": number,
        "pr": pr,
        "event_head_sha": event_head,
        "event_base_sha": event_base,
        "observed_head_sha": observed_head,
        "observed_base_sha": observed_base,
        "head_repository": head_repo,
        "changed_files": sorted(set(changed)),
    }


def _write_output(name: str, value: str) -> None:
    output = os.environ.get("GITHUB_OUTPUT", "").strip()
    if output:
        with Path(output).open("a", encoding="utf-8") as fh:
            fh.write(f"{name}={value}\n")


def classify_live() -> dict[str, Any]:
    ctx = _pr_context()
    decision = guard.classify_paths(ctx["changed_files"])
    result = {
        **decision,
        "pr_number": ctx["pr_number"],
        "head_sha": ctx["event_head_sha"],
        "base_sha": ctx["event_base_sha"],
        "changed_files": ctx["changed_files"],
    }
    _write_output("applicable", "true" if decision["applicable"] else "false")
    _write_output("status", str(decision["status"]))
    print(json.dumps(result, sort_keys=True))
    return result


def _content(repo: str, path: str, ref: str) -> tuple[bytes, str]:
    quoted_repo = urllib.parse.quote(repo, safe="/")
    quoted_path = urllib.parse.quote(path, safe="/")
    data = _api(f"/repos/{quoted_repo}/contents/{quoted_path}?ref={urllib.parse.quote(ref, safe='')}")
    if not isinstance(data, Mapping) or data.get("type") != "file":
        _fail("BLOCK_SELF_CHANGE_CONTENT_READBACK", path)
    blob = str(data.get("sha") or "")
    if guard.HEX40.fullmatch(blob) is None:
        _fail("BLOCK_SELF_CHANGE_CANDIDATE_BLOB_MISSING", path)
    if data.get("encoding") != "base64" or not isinstance(data.get("content"), str):
        _fail("BLOCK_SELF_CHANGE_CONTENT_ENCODING", path)
    try:
        content = base64.b64decode(str(data["content"]), validate=False)
    except Exception:
        _fail("BLOCK_SELF_CHANGE_CONTENT_ENCODING", path)
    return content, blob


def _current_main(repo: str) -> str:
    data = _api(f"/repos/{urllib.parse.quote(repo, safe='/')}/git/ref/heads/main")
    sha = str(((data or {}).get("object") or {}).get("sha") or "") if isinstance(data, Mapping) else ""
    if guard.HEX40.fullmatch(sha) is None:
        _fail("BLOCK_SELF_CHANGE_CURRENT_MAIN_SHA", sha)
    return sha


def _compare_post_head(repo: str, code_head: str, head: str) -> tuple[bool, list[str]]:
    data = _api(
        f"/repos/{urllib.parse.quote(repo, safe='/')}/compare/"
        f"{urllib.parse.quote(code_head, safe='')}...{urllib.parse.quote(head, safe='')}"
    )
    if not isinstance(data, Mapping):
        _fail("BLOCK_SELF_CHANGE_COMPARE_READBACK")
    status = str(data.get("status") or "")
    merge_base = str(((data.get("merge_base_commit") or {}).get("sha")) or "")
    files = data.get("files")
    if not isinstance(files, list):
        _fail("BLOCK_SELF_CHANGE_COMPARE_FILES")
    if len(files) >= 300:
        _fail("BLOCK_SELF_CHANGE_COMPARE_FILE_LIMIT")
    paths = []
    for row in files:
        if not isinstance(row, Mapping) or not isinstance(row.get("filename"), str):
            _fail("BLOCK_SELF_CHANGE_COMPARE_FILES")
        paths.append(str(row["filename"]))
    return status in {"ahead", "identical"} and merge_base == code_head, sorted(set(paths))


def _base_observed_anchors(base_sha: str) -> dict[str, dict[str, str]]:
    try:
        actual = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except subprocess.CalledProcessError:
        _fail("BLOCK_SELF_CHANGE_BASE_CHECKOUT_READBACK")
    if actual != base_sha:
        _fail("BLOCK_SELF_CHANGE_BASE_CHECKOUT_MISMATCH", f"{actual}!={base_sha}")
    out: dict[str, dict[str, str]] = {}
    for path in guard.ANCHOR_SURFACES:
        file_path = Path(path)
        if not file_path.is_file():
            _fail("BLOCK_SELF_CHANGE_ANCHOR_MISSING", path)
        blob_line = subprocess.check_output(
            ["git", "ls-tree", "HEAD", "--", path], text=True
        ).strip()
        parts = blob_line.split()
        if len(parts) < 3 or guard.HEX40.fullmatch(parts[2]) is None:
            _fail("BLOCK_SELF_CHANGE_BASE_BLOB", path)
        out[path] = {
            "git_blob": parts[2],
            "sha256": hashlib.sha256(file_path.read_bytes()).hexdigest(),
        }
    return out


def _pg_env() -> dict[str, str]:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    if not password:
        _fail("BLOCK_SELF_CHANGE_DB_PASSWORD_MISSING")
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": os.environ.get("SUPABASE_POOLER_HOST", POOLER_HOST),
            "PGPORT": "5432",
            "PGUSER": f"postgres.{os.environ.get('SUPABASE_PROJECT_ID', PROJECT_ID)}",
            "PGPASSWORD": password,
            "PGDATABASE": "postgres",
            "PGSSLMODE": "require",
        }
    )
    return env


def _psql_json(sql: str, *, variables: Mapping[str, str] | None = None) -> Any:
    cmd = [
        "docker",
        "run",
        "--rm",
        "-i",
        "-e",
        "PGHOST",
        "-e",
        "PGPORT",
        "-e",
        "PGUSER",
        "-e",
        "PGPASSWORD",
        "-e",
        "PGDATABASE",
        "-e",
        "PGSSLMODE",
        "postgres:17.6",
        "psql",
        "-X",
        "-A",
        "-t",
        "-q",
        "-v",
        "ON_ERROR_STOP=1",
    ]
    for key, value in (variables or {}).items():
        cmd.extend(["-v", f"{key}={value}"])
    completed = subprocess.run(
        cmd,
        input=sql,
        text=True,
        capture_output=True,
        env=_pg_env(),
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " | ")[:500]
        _fail("BLOCK_SELF_CHANGE_DB_READBACK", detail)
    raw = completed.stdout.strip()
    if not raw:
        _fail("BLOCK_SELF_CHANGE_DB_EMPTY")
    line = raw.splitlines()[-1]
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        _fail("BLOCK_SELF_CHANGE_DB_JSON", line[:300])


def _anchors() -> list[dict[str, Any]]:
    sql = r"""
select coalesce(jsonb_agg(to_jsonb(g) order by g.path),'[]'::jsonb)::text
from public.get_lf_repository_governance_bundle_v4() g
where g.path in (
  '.github/workflows/lf-contract-check.yml',
  'scripts/lf_contract_check.py'
);
"""
    data = _psql_json(sql)
    if not isinstance(data, list):
        _fail("BLOCK_SELF_CHANGE_ANCHOR_SHAPE")
    return data


def _execution_readback(execution_id: str) -> dict[str, Any]:
    if EXECUTION_ID_RE.fullmatch(execution_id) is None:
        _fail("BLOCK_SELF_CHANGE_EXECUTION_ID", execution_id[:100])
    sql = r"""
select jsonb_build_object(
  'execution',
    (select to_jsonb(e)
       from public.lf_operation_execution e
      where e.execution_id = :'execution_id'
      limit 1),
  'steps',
    coalesce(
      (select jsonb_agg(to_jsonb(s) order by s.step_order)
         from public.lf_operation_execution_steps s
        where s.execution_id = :'execution_id'),
      '[]'::jsonb
    ),
  'blocker_count',
    (select max(j.blocked_count)
       from public.v_lf_operation_execution_judge j
      where j.execution_id = :'execution_id')
)::text;
"""
    data = _psql_json(sql, variables={"execution_id": execution_id})
    if not isinstance(data, Mapping):
        _fail("BLOCK_SELF_CHANGE_EXECUTION_READBACK_SHAPE")
    return dict(data)


def validate_live() -> dict[str, Any]:
    ctx = _pr_context()
    classification = guard.classify_paths(ctx["changed_files"])
    if not classification["applicable"]:
        result = {**classification, "pr_number": ctx["pr_number"]}
        print(json.dumps(result, sort_keys=True))
        return result

    receipts = guard.receipt_paths(ctx["changed_files"])
    if len(receipts) != 1:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_CARDINALITY", json.dumps(receipts))
    receipt_path = receipts[0]
    receipt_bytes, _ = _content(
        ctx["head_repository"], receipt_path, ctx["event_head_sha"]
    )
    try:
        receipt = json.loads(receipt_bytes)
    except json.JSONDecodeError:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_SHAPE")
    if not isinstance(receipt, Mapping):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_SHAPE")

    protected = classification["protected_touched"]
    candidate_blobs: dict[str, str] = {}
    for path in protected:
        _, blob = _content(ctx["head_repository"], path, ctx["event_head_sha"])
        candidate_blobs[path] = blob

    code_head = str(receipt.get("candidate_code_head") or "")
    if guard.HEX40.fullmatch(code_head) is None:
        _fail("BLOCK_SELF_CHANGE_CODE_HEAD", code_head)
    ancestor, post_paths = _compare_post_head(
        ctx["head_repository"], code_head, ctx["event_head_sha"]
    )

    execution_id = str(receipt.get("execution_id") or "")
    payload = {
        "repository": ctx["repository"],
        "base_branch": str((ctx["pr"].get("base") or {}).get("ref") or ""),
        "event_base_sha": ctx["event_base_sha"],
        "current_main_sha": _current_main(ctx["repository"]),
        "event_head_sha": ctx["event_head_sha"],
        "observed_head_sha": ctx["observed_head_sha"],
        "pr_number": ctx["pr_number"],
        "changed_files": ctx["changed_files"],
        "receipt_path": receipt_path,
        "receipt": receipt,
        "code_head_is_ancestor": ancestor,
        "post_code_head_files": post_paths,
        "candidate_blob_sha_by_path": candidate_blobs,
        "anchors": _anchors(),
        "base_observed_anchors": _base_observed_anchors(ctx["event_base_sha"]),
        "execution_readback": _execution_readback(execution_id),
    }
    result = guard.evaluate_admission(payload)
    print(json.dumps(result, sort_keys=True))
    return result


def self_test() -> dict[str, Any]:
    checks = 0
    base = guard.self_test()
    if base != {"status": "PASS_SELF_TEST", "checks": 9}:
        raise AssertionError(base)
    checks += 1
    for good in (
        "EXEC-SELF-CHANGE-001",
        "exec:abc/123",
        "a.b_c-1",
    ):
        assert EXECUTION_ID_RE.fullmatch(good)
        checks += 1
    for bad in ("", "has space", "';drop table x;--", "x" * 201):
        assert EXECUTION_ID_RE.fullmatch(bad) is None
        checks += 1
    result = {"status": "PASS_CARRIER_SELF_TEST", "checks": checks, "guard_checks": 9}
    print(json.dumps(result, sort_keys=True))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("classify", "validate", "self-test"))
    args = parser.parse_args()
    try:
        if args.command == "classify":
            classify_live()
        elif args.command == "validate":
            validate_live()
        else:
            self_test()
    except guard.AdmissionError as exc:
        print(
            json.dumps(
                {"status": "BLOCK", "blocking_code": exc.code, "detail": exc.detail},
                sort_keys=True,
            )
        )
        raise SystemExit(2)
    except CarrierError as exc:
        print(
            json.dumps(
                {"status": "BLOCK", "blocking_code": exc.code, "detail": exc.detail},
                sort_keys=True,
            )
        )
        raise SystemExit(2)


if __name__ == "__main__":
    main()
